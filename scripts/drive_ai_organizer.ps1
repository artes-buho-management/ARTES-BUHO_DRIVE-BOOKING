param(
  [ValidateSet('bootstrap', 'run-once', 'daemon')]
  [string]$Mode = 'bootstrap',
  [string]$ProfileName = 'default',
  [string]$Model = $(if ($env:LOCAL_AI_MODEL) { $env:LOCAL_AI_MODEL } else { 'qwen2.5:7b-instruct' }),
  [int]$MaxFilesPerCycle = 12,
  [int]$SleepSeconds = 180,
  [int]$AiRetrySeconds = 30,
  [string]$SystemFolderName = 'DRIVE_IA_ORGANIZADOR_BOOKING',
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$script:AllowedCategories = @(
  'CONTRATOS',
  'FACTURAS',
  'CORREO',
  'AUDIO',
  'VIDEO',
  'IMAGEN',
  'HOJAS',
  'PRESENTACIONES',
  'SCRIPTS',
  'DOCUMENTOS',
  'COMPRIMIDOS',
  'OTROS'
)

$script:TokenProfile = $ProfileName
$script:AccessToken = $null
$script:SystemFolderName = $SystemFolderName
$script:LogDir = Join-Path (Join-Path $PSScriptRoot '..') 'logs'
$script:ConfigDir = Join-Path (Join-Path $PSScriptRoot '..') 'config'
$script:StatePath = Join-Path $script:ConfigDir 'drive_ai_organizer.state.json'
$script:BlocklistPath = Join-Path $script:ConfigDir 'drive_ai_organizer.blocklist.json'
$script:ActionLogPath = Join-Path $script:LogDir ("drive_ai_actions_{0}.jsonl" -f (Get-Date -Format 'yyyyMMdd'))
$script:BlockedFileIds = @{}

function Exit-IfDaemonAlreadyRunning {
  if ($Mode -ne 'daemon') {
    return
  }

  $selfPath = (Resolve-Path $PSCommandPath).Path
  $matches = Get-CimInstance Win32_Process | Where-Object {
    $_.Name -eq 'powershell.exe' -and
    $_.ProcessId -ne $PID -and
    $_.CommandLine -like "*$selfPath*" -and
    $_.CommandLine -like '*-Mode daemon*'
  }

  if ($matches) {
    Write-Output "[INFO] Otro daemon ya esta ejecutandose. Este proceso se cierra para evitar duplicados."
    exit 0
  }
}

function Ensure-Directory {
  param([string]$Path)
  if (-not (Test-Path $Path)) {
    New-Item -ItemType Directory -Path $Path | Out-Null
  }
}

function Write-RunLog {
  param(
    [string]$Message,
    [ValidateSet('INFO', 'WARN', 'ERROR')]
    [string]$Level = 'INFO'
  )

  $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  $line = "[{0}] [{1}] {2}" -f $stamp, $Level, $Message
  Write-Output $line
}

function Write-ActionLog {
  param([object]$Record)
  $json = $Record | ConvertTo-Json -Depth 20 -Compress
  Add-Content -Path $script:ActionLogPath -Value $json
}

function Load-Blocklist {
  if (Test-Path $script:BlocklistPath) {
    try {
      $data = Get-Content $script:BlocklistPath -Raw | ConvertFrom-Json
      $set = @{}
      foreach ($id in @($data.fileIds)) {
        if ($id) { $set[[string]$id] = $true }
      }
      return $set
    } catch {
      return @{}
    }
  }
  return @{}
}

function Save-Blocklist {
  $body = @{
    updatedAt = (Get-Date).ToString('o')
    fileIds = @($script:BlockedFileIds.Keys | Sort-Object)
  }
  $body | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $script:BlocklistPath
}

function Get-ClassprcPath {
  return Join-Path $HOME '.clasprc.json'
}

function Load-Classprc {
  $path = Get-ClassprcPath
  if (-not (Test-Path $path)) {
    throw "No existe $path"
  }
  return Get-Content $path -Raw | ConvertFrom-Json
}

function Save-Classprc {
  param([object]$Config)
  $path = Get-ClassprcPath
  $Config | ConvertTo-Json -Depth 50 | Set-Content -Encoding ASCII $path
}

function Get-TokenProfile {
  param([object]$Config, [string]$ProfileName)
  if (-not $Config.tokens) {
    throw "No existe bloque tokens en .clasprc.json"
  }

  $profile = $Config.tokens.$ProfileName
  if (-not $profile) {
    throw "No existe el perfil '$ProfileName' en .clasprc.json"
  }

  return $profile
}

function Ensure-AccessToken {
  param([switch]$ForceRefresh)

  $config = Load-Classprc
  $profile = Get-TokenProfile -Config $config -ProfileName $script:TokenProfile
  $nowMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $expiryMs = 0
  if ($profile.PSObject.Properties['expiry_date']) {
    $expiryMs = [int64]$profile.expiry_date
  }
  $safetyMs = 5 * 60 * 1000

  if (-not $ForceRefresh -and $profile.access_token -and ($expiryMs -gt ($nowMs + $safetyMs))) {
    return $profile.access_token
  }

  if (-not $profile.refresh_token) {
    throw 'No hay refresh_token para renovar el acceso.'
  }

  $tokenBody = @{
    client_id = $profile.client_id
    client_secret = $profile.client_secret
    refresh_token = $profile.refresh_token
    grant_type = 'refresh_token'
  }

  $refresh = Invoke-RestMethod -Method Post -Uri 'https://oauth2.googleapis.com/token' -Body $tokenBody
  $profile.access_token = $refresh.access_token
  if ($refresh.expires_in) {
    $newExpiry = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() + ([int64]$refresh.expires_in * 1000)
    if ($profile.PSObject.Properties['expiry_date']) {
      $profile.expiry_date = $newExpiry
    } else {
      $profile | Add-Member -NotePropertyName 'expiry_date' -NotePropertyValue $newExpiry -Force
    }
  }

  Save-Classprc -Config $config
  return $profile.access_token
}

function Invoke-DriveApi {
  param(
    [ValidateSet('GET', 'POST', 'PATCH', 'DELETE')]
    [string]$Method,
    [string]$Uri,
    [object]$Body,
    [string]$ContentType = 'application/json; charset=utf-8',
    [int]$MaxRetries = 5
  )

  for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
    try {
      if (-not $script:AccessToken) {
        $script:AccessToken = Ensure-AccessToken
      }

      $headers = @{ Authorization = "Bearer $script:AccessToken" }

      if ($null -ne $Body) {
        if ($ContentType -like 'application/json*') {
          $payload = $Body | ConvertTo-Json -Depth 20 -Compress
          $payloadBytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
          return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers -ContentType $ContentType -Body $payloadBytes
        }

        return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers -ContentType $ContentType -Body $Body
      }

      return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers
    } catch {
      $statusCode = $null
      try {
        $statusCode = [int]$_.Exception.Response.StatusCode
      } catch {
        $statusCode = $null
      }

      if ($statusCode -eq 401) {
        $script:AccessToken = Ensure-AccessToken -ForceRefresh
      }

      $retryable = $statusCode -in 401, 429, 500, 502, 503, 504
      if (-not $retryable -or $attempt -eq $MaxRetries) {
        throw
      }

      $sleepMs = (500 * [math]::Pow(2, $attempt - 1)) + (Get-Random -Minimum 0 -Maximum 300)
      Start-Sleep -Milliseconds $sleepMs
    }
  }
}

function Escape-DriveQueryValue {
  param([string]$Value)
  return $Value.Replace('\', '\\').Replace("'", "\'")
}

function Get-ExistingFolder {
  param(
    [string]$Name,
    [string]$ParentId
  )

  $safeName = Escape-DriveQueryValue -Value $Name
  $q = "'$ParentId' in parents and trashed=false and mimeType='application/vnd.google-apps.folder' and name='$safeName'"
  $uri = "https://www.googleapis.com/drive/v3/files?q=$([uri]::EscapeDataString($q))&pageSize=1&fields=files(id,name)"
  $resp = Invoke-DriveApi -Method GET -Uri $uri
  if ($resp.files -and $resp.files.Count -gt 0) {
    return $resp.files[0]
  }
  return $null
}

function Get-OrCreateFolder {
  param(
    [string]$Name,
    [string]$ParentId
  )

  $existing = Get-ExistingFolder -Name $Name -ParentId $ParentId
  if ($existing) {
    return $existing
  }

  if ($DryRun) {
    return [pscustomobject]@{
      id = "dryrun-$Name"
      name = $Name
    }
  }

  $body = @{
    name = $Name
    mimeType = 'application/vnd.google-apps.folder'
    parents = @($ParentId)
  }
  return Invoke-DriveApi -Method POST -Uri 'https://www.googleapis.com/drive/v3/files?fields=id,name' -Body $body
}

function Ensure-SystemStructure {
  $root = Get-OrCreateFolder -Name $script:SystemFolderName -ParentId 'root'
  $clasificados = Get-OrCreateFolder -Name '01_CLASIFICADOS' -ParentId $root.id
  $revision = Get-OrCreateFolder -Name '02_REVISION_MANUAL' -ParentId $root.id
  $errores = Get-OrCreateFolder -Name '03_ERRORES' -ParentId $root.id
  $logs = Get-OrCreateFolder -Name '99_LOGS' -ParentId $root.id

  $categoryMap = @{}
  foreach ($cat in $script:AllowedCategories) {
    $folder = Get-OrCreateFolder -Name $cat -ParentId $clasificados.id
    $categoryMap[$cat] = $folder.id
  }

  $state = [ordered]@{
    generatedAt = (Get-Date).ToString('o')
    systemRoot = $root
    folders = @{
      clasificados = $clasificados
      revision = $revision
      errores = $errores
      logs = $logs
      categorias = $categoryMap
    }
    settings = @{
      model = $Model
      maxFilesPerCycle = $MaxFilesPerCycle
      sleepSeconds = $SleepSeconds
    }
  }

  $state | ConvertTo-Json -Depth 30 | Set-Content -Encoding UTF8 $script:StatePath
  return $state
}

function Get-RootLooseFiles {
  param([int]$Limit)

  $q = "'root' in parents and trashed=false and mimeType!='application/vnd.google-apps.folder'"
  $fields = 'files(id,name,mimeType,parents,modifiedTime,size,owners(emailAddress,displayName),capabilities(canEdit,canMoveItemWithinDrive)),nextPageToken'
  $uri = "https://www.googleapis.com/drive/v3/files?q=$([uri]::EscapeDataString($q))&orderBy=modifiedTime desc&pageSize=$Limit&fields=$([uri]::EscapeDataString($fields))"
  $resp = Invoke-DriveApi -Method GET -Uri $uri
  return @($resp.files)
}

function Get-SkipReason {
  param([object]$File)

  if (-not $File) {
    return 'registro invalido'
  }

  $name = [string]$File.name
  if ($name -match '^drive_health_probe_' -or $name -match '^UPDATED_drive_health_probe_' -or $name -match '^probe_booking_') {
    return 'archivo de prueba'
  }

  if ($script:BlockedFileIds.ContainsKey([string]$File.id)) {
    return 'bloqueado por permiso'
  }

  if ($File.capabilities) {
    if ($File.capabilities.canEdit -eq $false) {
      return 'sin permiso de edicion'
    }
    if ($File.capabilities.canMoveItemWithinDrive -eq $false) {
      return 'sin permiso de movimiento'
    }
  }

  if ([string]$File.mimeType -eq 'application/vnd.google-apps.script') {
    return 'script protegido'
  }

  return $null
}

function Get-HeuristicCategory {
  param([object]$File)

  $name = ([string]$File.name).ToLower()
  $mime = ([string]$File.mimeType).ToLower()

  if ($name -match 'factura|invoice|recibo|albaran|pago') { return 'FACTURAS' }
  if ($name -match 'contrato|contract|acuerdo|booking') { return 'CONTRATOS' }
  if ($name -match 'correo|email|gmail|router') { return 'CORREO' }
  if ($name -match '\.zip$|\.rar$|\.7z$|\.tar$|\.gz$') { return 'COMPRIMIDOS' }

  if ($mime -like 'audio/*') { return 'AUDIO' }
  if ($mime -like 'video/*') { return 'VIDEO' }
  if ($mime -like 'image/*') { return 'IMAGEN' }

  if ($mime -eq 'application/vnd.google-apps.spreadsheet') { return 'HOJAS' }
  if ($mime -eq 'application/vnd.google-apps.presentation') { return 'PRESENTACIONES' }
  if ($mime -eq 'application/vnd.google-apps.script') { return 'SCRIPTS' }

  if ($mime -match 'zip|compressed|x-7z-compressed|x-rar-compressed') { return 'COMPRIMIDOS' }
  if ($mime -match 'pdf|document|word|text|plain') { return 'DOCUMENTOS' }

  return 'OTROS'
}

function Should-UseAiForFile {
  param(
    [object]$File,
    [string]$HeuristicCategory
  )

  $mime = ([string]$File.mimeType).ToLower()

  if ($mime -like 'audio/*' -or $mime -like 'video/*' -or $mime -like 'image/*') {
    return $false
  }

  if ($HeuristicCategory -in @('HOJAS', 'PRESENTACIONES', 'SCRIPTS', 'COMPRIMIDOS')) {
    return $false
  }

  return $true
}

function Convert-ClassificationJson {
  param([string]$Text)

  if (-not $Text) {
    return $null
  }

  try {
    return $Text | ConvertFrom-Json
  } catch {
    $match = [regex]::Match($Text, '\{[\s\S]*\}')
    if ($match.Success) {
      try {
        return $match.Value | ConvertFrom-Json
      } catch {
        return $null
      }
    }
    return $null
  }
}

function Wait-ForOllama {
  param(
    [string]$RequestedModel,
    [int]$RetrySeconds
  )

  while ($true) {
    try {
      $tags = Invoke-RestMethod -Method Get -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 8
      $models = @()
      if ($tags.models) {
        $models = @($tags.models | ForEach-Object { $_.name })
      }

      if ($models -contains $RequestedModel) {
        return $RequestedModel
      }

    $fallbackCandidates = @('qwen2.5:7b-instruct')
      foreach ($candidate in $fallbackCandidates) {
        if ($models -contains $candidate) {
          Write-RunLog "Modelo $RequestedModel no encontrado. Uso fallback $candidate." 'WARN'
          return $candidate
        }
      }

      Write-RunLog "IA local activa pero sin modelo utilizable. Esperando $RetrySeconds s." 'WARN'
    } catch {
      Write-RunLog "IA local no disponible (PC apagado o servicio caido). Esperando $RetrySeconds s." 'WARN'
    }

    Start-Sleep -Seconds $RetrySeconds
  }
}

function Invoke-AiClassification {
  param(
    [object]$File,
    [string]$ModelName
  )

  $heuristic = Get-HeuristicCategory -File $File

  $systemPrompt = @"
Clasifica archivos de Google Drive en UNA categoria de esta lista exacta:
CONTRATOS, FACTURAS, CORREO, AUDIO, VIDEO, IMAGEN, HOJAS, PRESENTACIONES, SCRIPTS, DOCUMENTOS, COMPRIMIDOS, OTROS.
Responde solo JSON valido:
{"categoria":"<categoria>","confianza":0.0,"motivo":"<texto corto>"}
"@

  $userPrompt = @"
nombre: $($File.name)
mimeType: $($File.mimeType)
tamanoBytes: $($File.size)
modificado: $($File.modifiedTime)
"@

  $payload = @{
    model = $ModelName
    stream = $false
    format = 'json'
    messages = @(
      @{ role = 'system'; content = $systemPrompt },
      @{ role = 'user'; content = $userPrompt }
    )
    options = @{
      temperature = 0.1
      num_ctx = 1024
      num_predict = 80
      num_thread = 6
    }
  }

  try {
    $resp = Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:11434/api/chat' -ContentType 'application/json' -Body ($payload | ConvertTo-Json -Depth 15) -TimeoutSec 120
    $raw = $resp.message.content
    $obj = Convert-ClassificationJson -Text $raw
    if ($obj -and $obj.categoria) {
      $cat = ([string]$obj.categoria).Trim().ToUpper()
      if ($script:AllowedCategories -contains $cat) {
        return [pscustomobject]@{
          categoria = $cat
          confianza = [double]$obj.confianza
          motivo = [string]$obj.motivo
          fuente = 'ia'
        }
      }
    }

    return [pscustomobject]@{
      categoria = $heuristic
      confianza = 0.45
      motivo = 'JSON IA invalido, se aplica heuristica.'
      fuente = 'heuristica'
    }
  } catch {
    return [pscustomobject]@{
      categoria = $heuristic
      confianza = 0.4
      motivo = 'Fallo temporal IA, se aplica heuristica.'
      fuente = 'heuristica'
    }
  }
}

function Move-FileToFolder {
  param(
    [object]$File,
    [string]$TargetFolderId
  )

  $fileId = [string]$File.id
  $currentParents = @()
  if ($File.parents) {
    $currentParents = @($File.parents)
  }

  $removeParents = @($currentParents | Where-Object { $_ -ne $TargetFolderId }) -join ','

  if ($DryRun) {
    return [pscustomobject]@{
      id = $fileId
      name = $File.name
      parents = @($TargetFolderId)
      dryRun = $true
    }
  }

  $params = @(
    "addParents=$TargetFolderId",
    'fields=id,name,parents'
  )
  if ($removeParents) {
    $params += "removeParents=$([uri]::EscapeDataString($removeParents))"
  }

  $uri = "https://www.googleapis.com/drive/v3/files/${fileId}?{0}" -f ($params -join '&')
  return Invoke-DriveApi -Method PATCH -Uri $uri -Body @{}
}

function Process-OneCycle {
  param([object]$State)

  $files = Get-RootLooseFiles -Limit $MaxFilesPerCycle
  if (-not $files -or $files.Count -eq 0) {
    Write-RunLog 'No hay archivos sueltos en Mi unidad para clasificar.'
    return
  }

  Write-RunLog ("Archivos detectados para revisar: {0}" -f $files.Count)
  $activeModel = $null

  foreach ($file in $files) {
    $skipReason = Get-SkipReason -File $file
    if ($skipReason) {
      Write-RunLog ("SKIP {0}: {1}" -f $file.name, $skipReason)
      Write-ActionLog -Record @{
        ts = (Get-Date).ToString('o')
        status = 'skip'
        fileId = $file.id
        fileName = $file.name
        mimeType = $file.mimeType
        reason = $skipReason
      }
      continue
    }

    $start = Get-Date
    try {
      $heuristic = Get-HeuristicCategory -File $file
      $useAi = Should-UseAiForFile -File $file -HeuristicCategory $heuristic

      if ($useAi) {
        if (-not $activeModel) {
          $activeModel = Wait-ForOllama -RequestedModel $Model -RetrySeconds $AiRetrySeconds
          Write-RunLog ("IA local lista con modelo: {0}" -f $activeModel)
        }
        $classification = Invoke-AiClassification -File $file -ModelName $activeModel
      } else {
        $classification = [pscustomobject]@{
          categoria = $heuristic
          confianza = 0.95
          motivo = 'Categoria clara por mimeType/regla.'
          fuente = 'heuristica'
        }
      }
      $category = $classification.categoria

      if (-not $State.folders.categorias.$category) {
        $category = 'OTROS'
      }

      $targetFolderId = [string]$State.folders.categorias.$category
      $result = Move-FileToFolder -File $file -TargetFolderId $targetFolderId

      $elapsed = [math]::Round(((Get-Date) - $start).TotalSeconds, 2)
      Write-RunLog ("OK {0} -> {1} ({2}s, {3})" -f $file.name, $category, $elapsed, $classification.fuente)

      Write-ActionLog -Record @{
        ts = (Get-Date).ToString('o')
        status = 'ok'
        fileId = $file.id
        fileName = $file.name
        mimeType = $file.mimeType
        category = $category
        model = $activeModel
        source = $classification.fuente
        confidence = $classification.confianza
        reason = $classification.motivo
        movedTo = $targetFolderId
        result = $result
        dryRun = [bool]$DryRun
      }
    } catch {
      $elapsed = [math]::Round(((Get-Date) - $start).TotalSeconds, 2)
      Write-RunLog ("ERROR {0} ({1}s): {2}" -f $file.name, $elapsed, $_.Exception.Message) 'ERROR'

      if ($_.Exception.Message -match '\(403\)') {
        $script:BlockedFileIds[[string]$file.id] = $true
        Save-Blocklist
      }

      Write-ActionLog -Record @{
        ts = (Get-Date).ToString('o')
        status = 'error'
        fileId = $file.id
        fileName = $file.name
        mimeType = $file.mimeType
        error = $_.Exception.Message
        dryRun = [bool]$DryRun
      }
    }
  }
}

function Bootstrap-System {
  Write-RunLog 'Creando estructura en Google Drive...'
  $state = Ensure-SystemStructure
  Write-RunLog ("Carpeta raiz del sistema: {0} ({1})" -f $state.systemRoot.name, $state.systemRoot.id)
  Write-RunLog 'Estructura lista.'
  return $state
}

function Load-OrBootstrapState {
  if (Test-Path $script:StatePath) {
    try {
      return Get-Content $script:StatePath -Raw | ConvertFrom-Json
    } catch {
      Write-RunLog 'State local invalido. Se reconstruye.' 'WARN'
      return Bootstrap-System
    }
  }

  return Bootstrap-System
}

Ensure-Directory -Path $script:LogDir
Ensure-Directory -Path $script:ConfigDir
Exit-IfDaemonAlreadyRunning
$script:BlockedFileIds = Load-Blocklist

$script:AccessToken = Ensure-AccessToken
$state = Load-OrBootstrapState

switch ($Mode) {
  'bootstrap' {
    Write-RunLog 'Bootstrap completado.'
  }
  'run-once' {
    Process-OneCycle -State $state
    Write-RunLog 'Ciclo unico completado.'
  }
  'daemon' {
    Write-RunLog ("Daemon activo. Revisa cada {0}s. Si la IA no esta disponible, espera sin fallar." -f $SleepSeconds)
    while ($true) {
      Process-OneCycle -State $state
      Start-Sleep -Seconds $SleepSeconds
    }
  }
}

param(
  [ValidateSet('run-once', 'daemon')]
  [string]$Mode = 'daemon',
  [string]$ProfileName = 'default',
  [string]$SourceFileId = 'REPLACE_WITH_ID',
  [string]$TargetFolderId = '1rieAe4JZyF39-VQSCUN_3FG4VecRW6V5',
  [string]$SourceDisplayName = 'CRM: MARKETING Y PROMOCION',
  [string]$SourceDisplayNameBase64 = '',
  [string]$BackupEmoji = ([string]([char]0xD83D) + [char]0xDE80),
  [string]$BackupEmojiCodepoint = '1F680',
  [string]$BackupEmojiSeparator = ' ',
  [switch]$NoSpaceAfterEmoji,
  [string]$BackupKey = '',
  [int]$RunHour = 14,
  [int]$RunMinute = 0,
  [int]$LoopSleepSeconds = 60,
  [switch]$ForceRun
)

$ErrorActionPreference = 'Stop'

$script:TokenProfile = $ProfileName
$script:AccessToken = $null
$script:ConfigDir = Join-Path (Join-Path $PSScriptRoot '..') 'config'
$script:LogsDir = Join-Path (Join-Path $PSScriptRoot '..') 'logs'
$script:BackupEmojiRaw = [string]$BackupEmoji
$script:BackupEmojiCodepoint = [string]$BackupEmojiCodepoint
$script:BackupEmoji = ''
$script:BackupEmojiSeparator = [string]$BackupEmojiSeparator
$script:NoSpaceAfterEmoji = [bool]$NoSpaceAfterEmoji

if (-not [string]::IsNullOrWhiteSpace($SourceDisplayNameBase64)) {
  try {
    $decodedSourceDisplayName = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($SourceDisplayNameBase64))
    if (-not [string]::IsNullOrWhiteSpace($decodedSourceDisplayName)) {
      $SourceDisplayName = $decodedSourceDisplayName
    }
  } catch {
  }
}

function Get-SafeKey {
  param([string]$Raw)
  $k = [string]$Raw
  if ([string]::IsNullOrWhiteSpace($k)) {
    $k = $SourceFileId
  }
  $k = $k.ToLowerInvariant()
  $k = [regex]::Replace($k, '[^a-z0-9_\-]+', '_')
  $k = $k.Trim('_')
  if ([string]::IsNullOrWhiteSpace($k)) {
    $k = 'backup'
  }
  return $k
}

if ([string]::IsNullOrWhiteSpace($BackupKey)) {
  $BackupKey = "backup_$($SourceFileId.Substring(0, [Math]::Min(8, $SourceFileId.Length)))"
}
$script:SafeKey = Get-SafeKey -Raw $BackupKey
$script:StatePath = Join-Path $script:ConfigDir ("crm_backup_scheduler.{0}.state.json" -f $script:SafeKey)
$script:LogPath = Join-Path $script:LogsDir ("crm_backup_{0}_{1}.jsonl" -f (Get-Date -Format 'yyyyMMdd'), $script:SafeKey)
$script:ResolvedTargetFolderId = $TargetFolderId
$script:RescueBuoy = [string]([char]0xD83D) + [char]0xDEDF

function Ensure-Dir {
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

function Write-JsonLog {
  param([object]$Record)
  ($Record | ConvertTo-Json -Depth 20 -Compress) | Add-Content -Path $script:LogPath -Encoding UTF8
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

function Ensure-AccessToken {
  param([switch]$ForceRefresh)

  $config = Load-Classprc
  if (-not $config.tokens) {
    throw "No existe bloque tokens en .clasprc.json"
  }

  $profile = $config.tokens.$script:TokenProfile
  if (-not $profile) {
    throw "No existe el perfil '$($script:TokenProfile)' en .clasprc.json"
  }

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
    [int]$MaxRetries = 5,
    [int]$TimeoutSec = 90
  )

  for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
    try {
      if (-not $script:AccessToken) {
        $script:AccessToken = Ensure-AccessToken
      }

      $headers = @{ Authorization = "Bearer $script:AccessToken" }

      if ($null -ne $Body) {
        if ($ContentType -like 'application/json*') {
          $json = $Body | ConvertTo-Json -Depth 20 -Compress
          $jsonBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
          return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers -ContentType $ContentType -Body $jsonBytes -TimeoutSec $TimeoutSec
        }
        return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers -ContentType $ContentType -Body $Body -TimeoutSec $TimeoutSec
      }

      return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers -TimeoutSec $TimeoutSec
    } catch {
      $statusCode = $null
      try { $statusCode = [int]$_.Exception.Response.StatusCode } catch { $statusCode = $null }

      if ($statusCode -eq 401) {
        $script:AccessToken = Ensure-AccessToken -ForceRefresh
      }

      $retryable = ($statusCode -eq $null) -or ($statusCode -in 401, 429, 500, 502, 503, 504)
      if (-not $retryable -or $attempt -eq $MaxRetries) {
        throw
      }

      $sleepMs = (400 * [math]::Pow(2, $attempt - 1)) + (Get-Random -Minimum 0 -Maximum 250)
      Start-Sleep -Milliseconds $sleepMs
    }
  }
}

function Escape-DriveQueryValue {
  param([string]$Value)
  return $Value.Replace('\', '\\').Replace("'", "\'")
}

function Get-EmojiFromCodepoint {
  param([string]$Codepoint)

  if ([string]::IsNullOrWhiteSpace($Codepoint)) {
    return ''
  }

  $parts = @($Codepoint -split '[,;\s]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  if ($parts.Count -eq 0) {
    return ''
  }

  $out = New-Object System.Text.StringBuilder
  foreach ($part in $parts) {
    $hex = $part.Trim().ToUpperInvariant().Replace('U+', '')
    try {
      $cp = [Convert]::ToInt32($hex, 16)
      [void]$out.Append([char]::ConvertFromUtf32($cp))
    } catch {
      return ''
    }
  }

  return $out.ToString()
}

function Initialize-BackupEmoji {
  $emoji = Get-EmojiFromCodepoint -Codepoint $script:BackupEmojiCodepoint
  if ([string]::IsNullOrWhiteSpace($emoji)) {
    $emoji = $script:BackupEmojiRaw
  }
  $script:BackupEmoji = [string]$emoji
}

function Remove-Diacritics {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) {
    return ''
  }

  $formD = $Value.Normalize([Text.NormalizationForm]::FormD)
  $buffer = New-Object System.Text.StringBuilder
  foreach ($char in $formD.ToCharArray()) {
    $cat = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($char)
    if ($cat -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
      [void]$buffer.Append($char)
    }
  }

  return $buffer.ToString().Normalize([Text.NormalizationForm]::FormC)
}

function Get-NormalizedFolderTokens {
  param([string]$FolderName)

  if ([string]::IsNullOrWhiteSpace($FolderName)) {
    return @()
  }

  $clean = Remove-Diacritics -Value $FolderName
  $clean = $clean.ToLowerInvariant()
  $clean = [regex]::Replace($clean, '[^a-z0-9]+', ' ')
  $clean = [regex]::Replace($clean, '\s+', ' ').Trim()
  if ([string]::IsNullOrWhiteSpace($clean)) {
    return @()
  }

  $ignored = @('de', 'del', 'la', 'las', 'el', 'los', 'y', 'the', 'a')
  $tokens = New-Object System.Collections.Generic.List[string]
  foreach ($part in $clean.Split(' ')) {
    if ([string]::IsNullOrWhiteSpace($part)) {
      continue
    }

    $token = $part.Trim()
    if ($ignored -contains $token) {
      continue
    }

    if ($token.Length -gt 3 -and $token.EndsWith('s')) {
      $token = $token.Substring(0, $token.Length - 1)
    }

    if (-not [string]::IsNullOrWhiteSpace($token)) {
      [void]$tokens.Add($token)
    }
  }

  return @($tokens.ToArray())
}

function Test-IsSafetyBackupFolderName {
  param([string]$FolderName)

  $tokens = Get-NormalizedFolderTokens -FolderName $FolderName
  if (-not $tokens -or $tokens.Count -eq 0) {
    return $false
  }

  $hasCopia = $false
  $hasSeguridad = $false
  foreach ($token in $tokens) {
    if ($token -match 'copi|backup|respald') {
      $hasCopia = $true
    }
    if ($token -match 'segu|safe|protec') {
      $hasSeguridad = $true
    }
  }

  return $hasCopia -and $hasSeguridad
}

function Get-SourceParentFolderId {
  $sourceMetaUri = "https://www.googleapis.com/drive/v3/files/${SourceFileId}?fields=id,name,parents"
  $sourceMeta = Invoke-DriveApi -Method GET -Uri $sourceMetaUri
  if ($sourceMeta.parents -and $sourceMeta.parents.Count -gt 0) {
    return [string]$sourceMeta.parents[0]
  }
  return 'root'
}

function Get-ChildFolders {
  param([string]$ParentId)

  $folderMime = 'application/vnd.google-apps.folder'
  $q = "trashed=false and mimeType='$folderMime' and '$ParentId' in parents"
  $items = @()
  $pageToken = $null

  do {
    $uri = "https://www.googleapis.com/drive/v3/files?q=$([uri]::EscapeDataString($q))&pageSize=200&fields=nextPageToken,files(id,name,createdTime)"
    if ($pageToken) {
      $uri = "$uri&pageToken=$([uri]::EscapeDataString($pageToken))"
    }
    $resp = Invoke-DriveApi -Method GET -Uri $uri
    if ($resp.files) {
      $items += @($resp.files)
    }
    $pageToken = $null
    if ($resp.PSObject.Properties['nextPageToken'] -and $resp.nextPageToken) {
      $pageToken = [string]$resp.nextPageToken
    }
  } while ($pageToken)

  return $items
}

function Select-BestSafetyFolder {
  param([array]$Candidates)

  if (-not $Candidates -or $Candidates.Count -eq 0) {
    return $null
  }

  $exact = @($Candidates | Where-Object {
    $joined = ((Get-NormalizedFolderTokens -FolderName $_.name) -join ' ')
    $joined -eq 'copia seguridad'
  })
  if ($exact.Count -gt 0) {
    return ($exact | Sort-Object -Property name | Select-Object -First 1)
  }

  return ($Candidates | Sort-Object @{
      Expression = { (Get-NormalizedFolderTokens -FolderName $_.name).Count }
      Ascending = $true
    }, @{
      Expression = { $_.name.Length }
      Ascending = $true
    }, @{
      Expression = { $_.name }
      Ascending = $true
    } | Select-Object -First 1)
}

function Ensure-TargetFolderId {
  $folderMime = 'application/vnd.google-apps.folder'

  if ($TargetFolderId) {
    try {
      $metaUri = "https://www.googleapis.com/drive/v3/files/${TargetFolderId}?fields=id,name,mimeType,trashed"
      $meta = Invoke-DriveApi -Method GET -Uri $metaUri
      if ($meta -and $meta.mimeType -eq $folderMime -and -not $meta.trashed) {
        [void](Write-RunLog ("Usando carpeta destino configurada: {0}" -f $meta.name))
        return $meta.id
      }
    } catch {
      [void](Write-RunLog ("Carpeta destino no valida o inaccesible ({0}). Se usara la carpeta local de seguridad." -f $TargetFolderId) 'WARN')
    }
  }

  $parentId = Get-SourceParentFolderId
  $existingFolders = Get-ChildFolders -ParentId $parentId
  $matches = @($existingFolders | Where-Object { Test-IsSafetyBackupFolderName -FolderName $_.name })

  if ($matches.Count -gt 0) {
    $selected = Select-BestSafetyFolder -Candidates $matches
    [void](Write-RunLog ("Usando carpeta de seguridad existente junto al archivo origen: {0}" -f $selected.name))
    return $selected.id
  }

  $newFolderName = "$($script:RescueBuoy) COPIA SEGURIDAD"
  $createBody = @{
    name = $newFolderName
    mimeType = $folderMime
    parents = @($parentId)
  }
  $createUri = 'https://www.googleapis.com/drive/v3/files?fields=id,name,webViewLink'
  $created = Invoke-DriveApi -Method POST -Uri $createUri -Body $createBody
  [void](Write-RunLog ("Carpeta creada automaticamente junto al archivo origen: {0}" -f $newFolderName))
  return $created.id
}

function Get-BackupName {
  param([datetime]$WhenLocal)
  $stamp = $WhenLocal.ToString('yyMMdd')
  $display = $SourceDisplayName
  if (-not [string]::IsNullOrWhiteSpace($script:BackupEmoji)) {
    $sep = $script:BackupEmojiSeparator
    if ($script:NoSpaceAfterEmoji) {
      $sep = ''
    }
    $display = "$($script:BackupEmoji)$sep$SourceDisplayName"
  }
  return "COPIA SEGURIDAD $stamp - $display"
}

function Get-WeekKey {
  param([datetime]$WhenLocal)
  $calendar = [System.Globalization.CultureInfo]::InvariantCulture.Calendar
  $weekRule = [System.Globalization.CalendarWeekRule]::FirstFourDayWeek
  $dayOfWeek = [DayOfWeek]::Monday
  $week = $calendar.GetWeekOfYear($WhenLocal, $weekRule, $dayOfWeek)
  return "{0}-W{1:D2}" -f $WhenLocal.Year, $week
}

function New-StateObject {
  return [pscustomobject]@{
    lastWeekKey = ''
    lastBackupAt = ''
    lastBackupName = ''
    lastBackupFileId = ''
  }
}

function Load-State {
  $state = New-StateObject
  if (Test-Path $script:StatePath) {
    try {
      $raw = Get-Content $script:StatePath -Raw | ConvertFrom-Json
      if ($raw.PSObject.Properties['lastWeekKey']) { $state.lastWeekKey = [string]$raw.lastWeekKey }
      if ($raw.PSObject.Properties['lastBackupAt']) { $state.lastBackupAt = [string]$raw.lastBackupAt }
      if ($raw.PSObject.Properties['lastBackupName']) { $state.lastBackupName = [string]$raw.lastBackupName }
      if ($raw.PSObject.Properties['lastBackupFileId']) { $state.lastBackupFileId = [string]$raw.lastBackupFileId }
    } catch {
      return $state
    }
  }

  return $state
}

function Save-State {
  param([object]$State)
  $State | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 $script:StatePath
}

function Find-ExistingBackupInFolder {
  param(
    [string]$DateStamp,
    [string]$SourceName
  )

  $prefix = Escape-DriveQueryValue -Value ("COPIA SEGURIDAD $DateStamp -")
  $q = "'$($script:ResolvedTargetFolderId)' in parents and trashed=false and name contains '$prefix'"
  $uri = "https://www.googleapis.com/drive/v3/files?q=$([uri]::EscapeDataString($q))&pageSize=50&fields=files(id,name,createdTime,webViewLink)"
  $resp = Invoke-DriveApi -Method GET -Uri $uri

  if (-not $resp.files -or $resp.files.Count -eq 0) {
    return $null
  }

  $candidates = @(
    $resp.files | Sort-Object -Property @{
      Expression = {
        try {
          [datetime]$_.createdTime
        } catch {
          [datetime]::MinValue
        }
      }
      Descending = $true
    }
  )

  if ([string]::IsNullOrWhiteSpace($SourceName)) {
    return $candidates[0]
  }

  $sourceNorm = [regex]::Replace((Remove-Diacritics -Value $SourceName).ToLowerInvariant(), '[^a-z0-9]+', ' ').Trim()
  foreach ($candidate in $candidates) {
    $candidateName = [string]$candidate.name
    if ($candidateName -like "*$SourceName*") {
      return $candidate
    }

    $candidateNorm = [regex]::Replace((Remove-Diacritics -Value $candidateName).ToLowerInvariant(), '[^a-z0-9]+', ' ').Trim()
    if (-not [string]::IsNullOrWhiteSpace($sourceNorm) -and $candidateNorm -like "*$sourceNorm*") {
      return $candidate
    }
  }

  return $null
}

function Create-BackupCopy {
  param([datetime]$WhenLocal)

  $stamp = $WhenLocal.ToString('yyMMdd')
  $backupName = Get-BackupName -WhenLocal $WhenLocal
  $existing = Find-ExistingBackupInFolder -DateStamp $stamp -SourceName $SourceDisplayName
  if ($existing) {
    return [pscustomobject]@{
      status = 'exists'
      backupName = $backupName
      file = $existing
    }
  }

  $uri = "https://www.googleapis.com/drive/v3/files/${SourceFileId}/copy?fields=id,name,parents,createdTime,webViewLink"
  $body = @{
    name = $backupName
    parents = @($script:ResolvedTargetFolderId)
  }
  $copy = Invoke-DriveApi -Method POST -Uri $uri -Body $body
  if (-not $copy -or -not $copy.id) {
    throw 'Google Drive devolvio una copia sin id.'
  }

  return [pscustomobject]@{
    status = 'created'
    backupName = $backupName
    file = $copy
  }
}

function Is-DueNow {
  param(
    [datetime]$NowLocal,
    [object]$State
  )

  if ($ForceRun) {
    return $true
  }

  $weekKey = Get-WeekKey -WhenLocal $NowLocal
  if ($State.lastWeekKey -eq $weekKey) {
    return $false
  }

  $daysSinceMonday = (([int]$NowLocal.DayOfWeek + 6) % 7)
  $mondayDate = $NowLocal.Date.AddDays(-$daysSinceMonday)
  $runAt = Get-Date -Year $mondayDate.Year -Month $mondayDate.Month -Day $mondayDate.Day -Hour $RunHour -Minute $RunMinute -Second 0
  if ($NowLocal -lt $runAt) {
    return $false
  }

  return $true
}

function Run-If-Due {
  $state = Load-State
  $now = Get-Date
  $weekKeyNow = Get-WeekKey -WhenLocal $now
  $needsHealingInCurrentFolder = $false

  if (-not $ForceRun -and $state.lastWeekKey -eq $weekKeyNow) {
    $stamp = $now.ToString('yyMMdd')
    $existingCurrentFolder = Find-ExistingBackupInFolder -DateStamp $stamp -SourceName $SourceDisplayName
    if ($existingCurrentFolder) {
      Write-RunLog ("No toca copia ahora. Proxima ventana: lunes {0:D2}:{1:D2}." -f $RunHour, $RunMinute)
      return
    }

    $needsHealingInCurrentFolder = $true
    Write-RunLog 'No existe copia de esta semana en la carpeta activa. Se recreara automaticamente.' 'WARN'
  }

  $due = Is-DueNow -NowLocal $now -State $state
  if (-not $due -and -not $needsHealingInCurrentFolder) {
    Write-RunLog ("No toca copia ahora. Proxima ventana: lunes {0:D2}:{1:D2}." -f $RunHour, $RunMinute)
    return
  }

  try {
    $result = Create-BackupCopy -WhenLocal $now
    $weekKey = $weekKeyNow
    $state.lastWeekKey = $weekKey
    $state.lastBackupAt = (Get-Date).ToString('o')
    $state.lastBackupName = $result.backupName
    $state.lastBackupFileId = $result.file.id
    Save-State -State $state

    Write-RunLog ("Backup {0}: {1}" -f $result.status, $result.backupName)
    Write-JsonLog -Record @{
      ts = (Get-Date).ToString('o')
      status = $result.status
      backupName = $result.backupName
      fileId = $result.file.id
      webViewLink = $result.file.webViewLink
      sourceFileId = $SourceFileId
      targetFolderId = $script:ResolvedTargetFolderId
      weekKey = $weekKey
    }
  } catch {
    Write-RunLog ("Fallo backup: {0}" -f $_.Exception.Message) 'ERROR'
    Write-JsonLog -Record @{
      ts = (Get-Date).ToString('o')
      status = 'error'
      error = $_.Exception.Message
      sourceFileId = $SourceFileId
      targetFolderId = $script:ResolvedTargetFolderId
    }
  }
}

function Exit-IfAlreadyRunningDaemon {
  if ($Mode -ne 'daemon') {
    return
  }

  $selfPath = (Resolve-Path $PSCommandPath).Path
  $keyTokenA = "-BackupKey $BackupKey"
  $keyTokenB = "-BackupKey `"$BackupKey`""
  $other = Get-CimInstance Win32_Process | Where-Object {
    $_.Name -eq 'powershell.exe' -and
    $_.ProcessId -ne $PID -and
    $_.CommandLine -like "*$selfPath*" -and
    $_.CommandLine -like '*-Mode daemon*' -and
    ($_.CommandLine.Contains($keyTokenA) -or $_.CommandLine.Contains($keyTokenB))
  }

  if ($other) {
    Write-Output "[INFO] Ya hay un daemon de backup ejecutandose. Este proceso se cierra."
    exit 0
  }
}

function Initialize-SchedulerContext {
  param([switch]$LogFailures)

  try {
    $script:AccessToken = Ensure-AccessToken
    $script:ResolvedTargetFolderId = Ensure-TargetFolderId
    return $true
  } catch {
    if ($LogFailures) {
      Write-RunLog ("No se pudo inicializar contexto ({0}): {1}" -f $BackupKey, $_.Exception.Message) 'WARN'
      Write-JsonLog -Record @{
        ts = (Get-Date).ToString('o')
        status = 'init_error'
        error = $_.Exception.Message
        sourceFileId = $SourceFileId
        targetFolderId = $TargetFolderId
        backupKey = $BackupKey
      }
    }
    $script:AccessToken = $null
    $script:ResolvedTargetFolderId = $TargetFolderId
    return $false
  }
}

Ensure-Dir -Path $script:ConfigDir
Ensure-Dir -Path $script:LogsDir
Initialize-BackupEmoji
Exit-IfAlreadyRunningDaemon

if ($Mode -eq 'run-once') {
  if (-not (Initialize-SchedulerContext -LogFailures)) {
    exit 1
  }
  Run-If-Due
  exit 0
}

$initSleepSeconds = [Math]::Max(30, [Math]::Min(300, $LoopSleepSeconds))
while (-not (Initialize-SchedulerContext -LogFailures)) {
  Start-Sleep -Seconds $initSleepSeconds
}

Write-RunLog ("Daemon backup activo ({0}). Ejecuta lunes {1:D2}:{2:D2}." -f $BackupKey, $RunHour, $RunMinute)
while ($true) {
  try {
    if (-not $script:ResolvedTargetFolderId) {
      [void](Initialize-SchedulerContext -LogFailures)
    }
    Run-If-Due
  } catch {
    Write-RunLog ("Error no controlado en daemon ({0}): {1}" -f $BackupKey, $_.Exception.Message) 'ERROR'
    Write-JsonLog -Record @{
      ts = (Get-Date).ToString('o')
      status = 'daemon_error'
      error = $_.Exception.Message
      sourceFileId = $SourceFileId
      targetFolderId = $script:ResolvedTargetFolderId
      backupKey = $BackupKey
    }
    $script:AccessToken = $null
    $script:ResolvedTargetFolderId = ''
  }
  Start-Sleep -Seconds $LoopSleepSeconds
}

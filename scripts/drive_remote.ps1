param(
  [ValidateSet('health-check', 'list', 'create-text', 'update-text', 'rename', 'delete')]
  [string]$Action = 'health-check',
  [string]$FileId,
  [string]$Name,
  [string]$Content = '',
  [string]$ParentId,
  [int]$PageSize = 10
)

$ErrorActionPreference = 'Stop'

function Get-ClassprcPath {
  return Join-Path $HOME '.clasprc.json'
}

function Save-Classprc {
  param([object]$Config)
  $path = Get-ClassprcPath
  $Config | ConvertTo-Json -Depth 50 | Set-Content -Encoding ASCII $path
}

function Get-TokenProfile {
  param([object]$Config, [string]$ProfileName = 'default')
  if (-not $Config.tokens) {
    throw "No existe bloque 'tokens' en .clasprc.json"
  }

  $profile = $Config.tokens.$ProfileName
  if (-not $profile) {
    throw "No existe el perfil '$ProfileName' en .clasprc.json"
  }

  return $profile
}

function Ensure-AccessToken {
  param([object]$Config, [string]$ProfileName = 'default')

  $profile = Get-TokenProfile -Config $Config -ProfileName $ProfileName
  $expiry = 0
  if ($profile.PSObject.Properties['expiry_date']) {
    $expiry = [int64]$profile.expiry_date
  }
  $nowMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $safetyWindowMs = 5 * 60 * 1000

  if ($profile.access_token -and ($expiry -gt ($nowMs + $safetyWindowMs))) {
    return $profile.access_token
  }

  if (-not $profile.refresh_token) {
    throw "No hay refresh_token para renovar acceso."
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

  Save-Classprc -Config $Config
  return $profile.access_token
}

function Invoke-DriveRequest {
  param(
    [ValidateSet('GET', 'POST', 'PATCH', 'DELETE')]
    [string]$Method,
    [string]$Uri,
    [string]$AccessToken,
    [object]$Body,
    [string]$ContentType = 'application/json',
    [int]$MaxRetries = 5
  )

  for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
    try {
      $headers = @{ Authorization = "Bearer $AccessToken" }

      if ($null -ne $Body) {
        if ($ContentType -eq 'application/json') {
          $jsonBody = $Body | ConvertTo-Json -Depth 20 -Compress
          return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers -ContentType $ContentType -Body $jsonBody
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

      $retryable = $false
      if ($statusCode -in 429, 500, 502, 503, 504) {
        $retryable = $true
      }

      if (-not $retryable -or $attempt -eq $MaxRetries) {
        throw
      }

      $sleepMs = (500 * [math]::Pow(2, $attempt - 1)) + (Get-Random -Minimum 0 -Maximum 250)
      Start-Sleep -Milliseconds $sleepMs
    }
  }
}

function Create-TextFile {
  param(
    [string]$AccessToken,
    [string]$FileName,
    [string]$FileContent,
    [string]$FolderId
  )

  if (-not $FileName) {
    throw "Para create-text necesitas -Name."
  }

  $metadata = @{
    name = $FileName
    mimeType = 'text/plain'
  }

  if ($FolderId) {
    $metadata.parents = @($FolderId)
  }

  $created = Invoke-DriveRequest -Method POST -Uri 'https://www.googleapis.com/drive/v3/files?fields=id,name,mimeType,parents' -AccessToken $AccessToken -Body $metadata

  $uploadUri = "https://www.googleapis.com/upload/drive/v3/files/$($created.id)?uploadType=media"
  $null = Invoke-DriveRequest -Method PATCH -Uri $uploadUri -AccessToken $AccessToken -Body $FileContent -ContentType 'text/plain'

  return Invoke-DriveRequest -Method GET -Uri "https://www.googleapis.com/drive/v3/files/$($created.id)?fields=id,name,mimeType,parents,modifiedTime" -AccessToken $AccessToken
}

function Update-TextFile {
  param(
    [string]$AccessToken,
    [string]$TargetFileId,
    [string]$FileContent
  )

  if (-not $TargetFileId) {
    throw "Para update-text necesitas -FileId."
  }

  $uploadUri = "https://www.googleapis.com/upload/drive/v3/files/${TargetFileId}?uploadType=media"
  $null = Invoke-DriveRequest -Method PATCH -Uri $uploadUri -AccessToken $AccessToken -Body $FileContent -ContentType 'text/plain'

  return Invoke-DriveRequest -Method GET -Uri "https://www.googleapis.com/drive/v3/files/${TargetFileId}?fields=id,name,mimeType,modifiedTime" -AccessToken $AccessToken
}

function Rename-File {
  param(
    [string]$AccessToken,
    [string]$TargetFileId,
    [string]$NewName
  )

  if (-not $TargetFileId -or -not $NewName) {
    throw "Para rename necesitas -FileId y -Name."
  }

  return Invoke-DriveRequest -Method PATCH -Uri "https://www.googleapis.com/drive/v3/files/${TargetFileId}?fields=id,name,modifiedTime" -AccessToken $AccessToken -Body @{ name = $NewName }
}

function Delete-File {
  param(
    [string]$AccessToken,
    [string]$TargetFileId
  )

  if (-not $TargetFileId) {
    throw "Para delete necesitas -FileId."
  }

  $null = Invoke-DriveRequest -Method DELETE -Uri "https://www.googleapis.com/drive/v3/files/$TargetFileId" -AccessToken $AccessToken
  return @{ ok = $true; deleted = $TargetFileId }
}

function Health-Check {
  param([string]$AccessToken)

  $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
  $name = "drive_health_probe_$stamp.txt"

  $created = Create-TextFile -AccessToken $AccessToken -FileName $name -FileContent "create_ok_$stamp"
  $updated = Update-TextFile -AccessToken $AccessToken -TargetFileId $created.id -FileContent "update_ok_$stamp"
  $renamed = Rename-File -AccessToken $AccessToken -TargetFileId $created.id -NewName "UPDATED_$name"
  $deleted = Delete-File -AccessToken $AccessToken -TargetFileId $created.id

  return @{
    ok = $true
    create = $created
    update = $updated
    rename = $renamed
    delete = $deleted
  }
}

$configPath = Get-ClassprcPath
if (-not (Test-Path $configPath)) {
  throw "No existe $configPath"
}

$config = Get-Content $configPath -Raw | ConvertFrom-Json
$accessToken = Ensure-AccessToken -Config $config -ProfileName 'default'

switch ($Action) {
  'list' {
    $uri = "https://www.googleapis.com/drive/v3/files?pageSize=$PageSize&fields=files(id,name,mimeType,modifiedTime)"
    $result = Invoke-DriveRequest -Method GET -Uri $uri -AccessToken $accessToken
    $result | ConvertTo-Json -Depth 20
    break
  }
  'create-text' {
    $result = Create-TextFile -AccessToken $accessToken -FileName $Name -FileContent $Content -FolderId $ParentId
    $result | ConvertTo-Json -Depth 20
    break
  }
  'update-text' {
    $result = Update-TextFile -AccessToken $accessToken -TargetFileId $FileId -FileContent $Content
    $result | ConvertTo-Json -Depth 20
    break
  }
  'rename' {
    $result = Rename-File -AccessToken $accessToken -TargetFileId $FileId -NewName $Name
    $result | ConvertTo-Json -Depth 20
    break
  }
  'delete' {
    $result = Delete-File -AccessToken $accessToken -TargetFileId $FileId
    $result | ConvertTo-Json -Depth 20
    break
  }
  default {
    $result = Health-Check -AccessToken $accessToken
    $result | ConvertTo-Json -Depth 20
    break
  }
}

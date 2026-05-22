param(
  [string]$ProfileName = 'default',
  [string]$BackupFileId = 'REPLACE_WITH_ID',
  [string]$WrongFolderId = '1DPjw4q9YYGgqlxIDvJUEaAdXl4pxEyOY',
  [string]$RightFolderId = '1rieAe4JZyF39-VQSCUN_3FG4VecRW6V5',
  [string]$DateCode = '260323',
  [string]$SourceDisplayName = 'CRM: MARKETING Y PROMOCION',
  [string]$EmojiCodepoint = '1F680'
)

$ErrorActionPreference = 'Stop'

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
  param([string]$Profile = 'default')

  $cfg = Load-Classprc
  if (-not $cfg.tokens) {
    throw 'No existe bloque tokens en .clasprc.json'
  }

  $tokenProfile = $cfg.tokens.$Profile
  if (-not $tokenProfile) {
    throw "No existe el perfil '$Profile' en .clasprc.json"
  }

  $nowMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $expiryMs = 0
  if ($tokenProfile.PSObject.Properties['expiry_date']) {
    $expiryMs = [int64]$tokenProfile.expiry_date
  }
  $safetyMs = 5 * 60 * 1000

  if ($tokenProfile.access_token -and ($expiryMs -gt ($nowMs + $safetyMs))) {
    return $tokenProfile.access_token
  }

  if (-not $tokenProfile.refresh_token) {
    throw "No hay refresh_token para el perfil '$Profile'."
  }

  $tokenBody = @{
    client_id = $tokenProfile.client_id
    client_secret = $tokenProfile.client_secret
    refresh_token = $tokenProfile.refresh_token
    grant_type = 'refresh_token'
  }

  $refresh = Invoke-RestMethod -Method Post -Uri 'https://oauth2.googleapis.com/token' -Body $tokenBody
  $tokenProfile.access_token = $refresh.access_token
  if ($refresh.expires_in) {
    $tokenProfile.expiry_date = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() + ([int64]$refresh.expires_in * 1000)
  }

  Save-Classprc -Config $cfg
  return $tokenProfile.access_token
}

function Invoke-DriveApi {
  param(
    [ValidateSet('GET', 'POST', 'PATCH', 'DELETE')]
    [string]$Method,
    [string]$Uri,
    [hashtable]$Headers,
    [object]$Body,
    [string]$ContentType = 'application/json; charset=utf-8',
    [int]$MaxRetries = 5
  )

  for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
    try {
      if ($null -ne $Body) {
        if ($ContentType -like 'application/json*') {
          $json = $Body | ConvertTo-Json -Depth 20 -Compress
          $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
          return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers -ContentType $ContentType -Body $bytes -TimeoutSec 90
        }
        return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers -ContentType $ContentType -Body $Body -TimeoutSec 90
      }

      return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers -TimeoutSec 90
    } catch {
      $statusCode = $null
      try { $statusCode = [int]$_.Exception.Response.StatusCode } catch { $statusCode = $null }

      $retryable = ($statusCode -eq $null) -or ($statusCode -in 401, 429, 500, 502, 503, 504)
      if (-not $retryable -or $attempt -eq $MaxRetries) {
        throw
      }

      $sleepMs = (400 * [math]::Pow(2, $attempt - 1)) + (Get-Random -Minimum 0 -Maximum 250)
      Start-Sleep -Milliseconds $sleepMs
    }
  }
}

function Get-EmojiFromCodepoint {
  param([string]$Codepoint)
  if ([string]::IsNullOrWhiteSpace($Codepoint)) {
    return ''
  }
  $hex = $Codepoint.Trim().ToUpperInvariant().Replace('U+', '')
  $cp = [Convert]::ToInt32($hex, 16)
  return [char]::ConvertFromUtf32($cp)
}

function Escape-DriveQueryValue {
  param([string]$Value)
  return $Value.Replace('\', '\\').Replace("'", "\'")
}

$accessToken = Ensure-AccessToken -Profile $ProfileName
$headers = @{ Authorization = "Bearer $accessToken" }
$emoji = Get-EmojiFromCodepoint -Codepoint $EmojiCodepoint
$desiredName = "COPIA SEGURIDAD $DateCode - $emoji $SourceDisplayName"

$file = $null
try {
  $metaUri = "https://www.googleapis.com/drive/v3/files/${BackupFileId}?fields=id,name,parents,webViewLink"
  $file = Invoke-DriveApi -Method GET -Uri $metaUri -Headers $headers
} catch {
  $file = $null
}

if (-not $file) {
  $prefix = Escape-DriveQueryValue -Value ("COPIA SEGURIDAD $DateCode -")
  $searchName = Escape-DriveQueryValue -Value $SourceDisplayName
  $q = "'$WrongFolderId' in parents and trashed=false and name contains '$prefix' and name contains '$searchName'"
  $searchUri = "https://www.googleapis.com/drive/v3/files?q=$([uri]::EscapeDataString($q))&pageSize=20&fields=files(id,name,parents,webViewLink)"
  $resp = Invoke-DriveApi -Method GET -Uri $searchUri -Headers $headers
  if ($resp.files -and $resp.files.Count -gt 0) {
    $file = $resp.files[0]
  }
}

if (-not $file) {
  throw 'No se encontro la copia a reparar.'
}

$currentParents = @()
if ($file.parents) {
  $currentParents = @($file.parents)
}

$removeParents = @($currentParents | Where-Object { $_ -ne $RightFolderId })
$moveUri = "https://www.googleapis.com/drive/v3/files/$($file.id)?addParents=$RightFolderId&fields=id,name,parents,webViewLink"
if ($removeParents.Count -gt 0) {
  $remove = [string]::Join(',', $removeParents)
  $moveUri += "&removeParents=$remove"
}

$moved = Invoke-DriveApi -Method PATCH -Uri $moveUri -Headers $headers -Body @{}

$renamed = $moved
if ([string]$moved.name -ne $desiredName) {
  $renameUri = "https://www.googleapis.com/drive/v3/files/$($file.id)?fields=id,name,parents,webViewLink"
  $renamed = Invoke-DriveApi -Method PATCH -Uri $renameUri -Headers $headers -Body @{ name = $desiredName }
}

Write-Output ("OK|FileId={0}|Name={1}|Parents={2}|Link={3}" -f $renamed.id, $renamed.name, ($renamed.parents -join ','), $renamed.webViewLink)

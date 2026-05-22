param(
  [string]$ProfileName = 'default',
  [int]$RedirectPort = 1508,
  [int]$TimeoutSeconds = 300
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

function Send-AuthResponse {
  param(
    [System.Net.HttpListenerContext]$Context,
    [int]$StatusCode,
    [string]$Title,
    [string]$Message
  )

  $html = @"
<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <title>$Title</title>
</head>
<body style="font-family:Segoe UI,Arial,sans-serif;padding:24px">
  <h2>$Title</h2>
  <p>$Message</p>
  <p>Puedes cerrar esta ventana.</p>
</body>
</html>
"@

  $bytes = [System.Text.Encoding]::UTF8.GetBytes($html)
  $Context.Response.StatusCode = $StatusCode
  $Context.Response.ContentType = 'text/html; charset=utf-8'
  $Context.Response.ContentLength64 = $bytes.Length
  $Context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
  $Context.Response.OutputStream.Close()
}

Add-Type -AssemblyName System.Web

$config = Load-Classprc
if (-not $config.tokens) {
  throw "No existe bloque 'tokens' en .clasprc.json"
}

$profile = $config.tokens.$ProfileName
if (-not $profile) {
  throw "No existe el perfil '$ProfileName' en .clasprc.json"
}

if ([string]::IsNullOrWhiteSpace($profile.client_id) -or [string]::IsNullOrWhiteSpace($profile.client_secret)) {
  throw "Faltan client_id/client_secret en el perfil '$ProfileName'."
}

$redirectUri = "http://localhost:$RedirectPort"
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("$redirectUri/")
$listener.Start()

$state = [Guid]::NewGuid().ToString('N')
$scopes = @(
  'https://www.googleapis.com/auth/drive',
  'https://www.googleapis.com/auth/drive.file',
  'https://www.googleapis.com/auth/drive.metadata.readonly',
  'https://www.googleapis.com/auth/script.deployments',
  'https://www.googleapis.com/auth/script.projects',
  'https://www.googleapis.com/auth/script.webapp.deploy',
  'https://www.googleapis.com/auth/service.management',
  'https://www.googleapis.com/auth/logging.read',
  'https://www.googleapis.com/auth/userinfo.email',
  'https://www.googleapis.com/auth/userinfo.profile',
  'https://www.googleapis.com/auth/cloud-platform'
)

$query = @{
  client_id = [string]$profile.client_id
  redirect_uri = $redirectUri
  response_type = 'code'
  scope = ($scopes -join ' ')
  access_type = 'offline'
  include_granted_scopes = 'true'
  prompt = 'consent'
  state = $state
}

$authUrl = 'https://accounts.google.com/o/oauth2/v2/auth?' + (($query.GetEnumerator() | ForEach-Object {
  [System.Uri]::EscapeDataString([string]$_.Key) + '=' + [System.Uri]::EscapeDataString([string]$_.Value)
}) -join '&')

Write-Output "INFO|Abre navegador para autorizar: $authUrl"
Start-Process $authUrl

$async = $listener.BeginGetContext($null, $null)
if (-not $async.AsyncWaitHandle.WaitOne($TimeoutSeconds * 1000)) {
  $listener.Stop()
  throw "Tiempo agotado esperando autorizacion ($TimeoutSeconds s)."
}

$context = $listener.EndGetContext($async)
$request = $context.Request
$qs = [System.Web.HttpUtility]::ParseQueryString($request.Url.Query)

if ($qs['error']) {
  Send-AuthResponse -Context $context -StatusCode 400 -Title 'Autorizacion cancelada' -Message ("Error: " + $qs['error'])
  $listener.Stop()
  throw ("Google devolvio error: " + $qs['error'])
}

if ($qs['state'] -ne $state) {
  Send-AuthResponse -Context $context -StatusCode 400 -Title 'Estado invalido' -Message 'No coincide el parametro state.'
  $listener.Stop()
  throw 'State invalido en callback OAuth.'
}

$code = [string]$qs['code']
if ([string]::IsNullOrWhiteSpace($code)) {
  Send-AuthResponse -Context $context -StatusCode 400 -Title 'Codigo ausente' -Message 'No se recibio code.'
  $listener.Stop()
  throw 'No se recibio codigo de autorizacion.'
}

Send-AuthResponse -Context $context -StatusCode 200 -Title 'Autorizacion correcta' -Message 'La autorizacion se recibio correctamente.'
$listener.Stop()

$tokenBody = @{
  code = $code
  client_id = [string]$profile.client_id
  client_secret = [string]$profile.client_secret
  redirect_uri = $redirectUri
  grant_type = 'authorization_code'
}

$tokenResp = Invoke-RestMethod -Method Post -Uri 'https://oauth2.googleapis.com/token' -Body $tokenBody
if (-not $tokenResp.access_token) {
  throw 'No se obtuvo access_token en el intercambio OAuth.'
}

$profile.access_token = [string]$tokenResp.access_token
if ($tokenResp.refresh_token) {
  $profile.refresh_token = [string]$tokenResp.refresh_token
}
if ($tokenResp.token_type) {
  if ($profile.PSObject.Properties['token_type']) {
    $profile.token_type = [string]$tokenResp.token_type
  } else {
    $profile | Add-Member -NotePropertyName 'token_type' -NotePropertyValue ([string]$tokenResp.token_type) -Force
  }
}
if ($tokenResp.expires_in) {
  $profile.expiry_date = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() + ([int64]$tokenResp.expires_in * 1000)
}

Save-Classprc -Config $config
Write-Output "OK|Profile=$ProfileName|ExpiresInSec=$($tokenResp.expires_in)"

param(
  [string]$Model = $(if ($env:LOCAL_AI_MODEL) { $env:LOCAL_AI_MODEL } else { 'qwen2.5:7b-instruct' }),
  [int]$MaxFilesPerCycle = 12,
  [int]$SleepSeconds = 180,
  [int]$AiRetrySeconds = 30
)

$ErrorActionPreference = 'Stop'

$organizerPath = Join-Path $PSScriptRoot 'drive_ai_organizer.ps1'
if (-not (Test-Path $organizerPath)) {
  throw "No existe $organizerPath"
}

$startupDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
if (-not (Test-Path $startupDir)) {
  throw "No existe carpeta de inicio: $startupDir"
}

$launcherPath = Join-Path $startupDir 'DriveAIAutoOrganizerBooking.vbs'
$legacyCmdPath = Join-Path $startupDir 'DriveAIAutoOrganizerBooking.cmd'
$psExe = 'C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe'

$content = @"
Set shell = CreateObject("WScript.Shell")
cmd = """$psExe"" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""$organizerPath"" -Mode daemon -Model ""$Model"" -MaxFilesPerCycle $MaxFilesPerCycle -SleepSeconds $SleepSeconds -AiRetrySeconds $AiRetrySeconds"
shell.Run cmd, 0, False
"@

$content | Set-Content -Encoding Unicode $launcherPath

if (Test-Path $legacyCmdPath) {
  Remove-Item -Force $legacyCmdPath
}

Start-Process -FilePath $psExe -ArgumentList @(
  '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $organizerPath,
  '-Mode', 'daemon',
  '-Model', $Model,
  '-MaxFilesPerCycle', $MaxFilesPerCycle,
  '-SleepSeconds', $SleepSeconds,
  '-AiRetrySeconds', $AiRetrySeconds
) -WindowStyle Hidden

Write-Output "OK|StartupLauncher=$launcherPath|Model=$Model|StartedNow=true"

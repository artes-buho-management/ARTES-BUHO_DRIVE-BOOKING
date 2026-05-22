param(
  [string]$LauncherFileName = 'Drive_Backup_Watchdog.vbs',
  [int]$LoopSleepSeconds = 300
)

$ErrorActionPreference = 'Stop'

$watchdogPath = Join-Path $PSScriptRoot 'backup_daemon_watchdog.ps1'
if (-not (Test-Path $watchdogPath)) {
  throw "No existe $watchdogPath"
}

if ($LoopSleepSeconds -lt 30) {
  $LoopSleepSeconds = 30
}

$startupDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
if (-not (Test-Path $startupDir)) {
  throw "No existe carpeta de inicio: $startupDir"
}

$launcherBase = [System.IO.Path]::GetFileNameWithoutExtension($LauncherFileName)
if ([string]::IsNullOrWhiteSpace($launcherBase)) {
  $launcherBase = 'Drive_Backup_Watchdog'
}

$launcherPath = Join-Path $startupDir ($launcherBase + '.vbs')
$legacyCmdPath = Join-Path $startupDir ($launcherBase + '.cmd')
$psExe = 'C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe'

$content = @"
Set shell = CreateObject("WScript.Shell")
cmd = """$psExe"" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""$watchdogPath"" -Mode daemon -LoopSleepSeconds $LoopSleepSeconds"
shell.Run cmd, 0, False
"@

$content | Set-Content -Encoding Unicode $launcherPath

if (Test-Path $legacyCmdPath) {
  Remove-Item -Force $legacyCmdPath
}

$args = @(
  '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $watchdogPath,
  '-Mode', 'daemon',
  '-LoopSleepSeconds', $LoopSleepSeconds
)

Start-Process -FilePath $psExe -ArgumentList $args -WindowStyle Hidden

Write-Output "OK|StartupLauncher=$launcherPath|LoopSleepSeconds=$LoopSleepSeconds|StartedNow=true"

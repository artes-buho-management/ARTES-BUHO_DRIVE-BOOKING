param(
  [string]$LauncherFileName = 'Drive_Backup_Watchdog.vbs'
)

$ErrorActionPreference = 'Stop'

$startupDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
$launcherBase = [System.IO.Path]::GetFileNameWithoutExtension($LauncherFileName)
if ([string]::IsNullOrWhiteSpace($launcherBase)) {
  $launcherBase = 'Drive_Backup_Watchdog'
}

$launcherVbsPath = Join-Path $startupDir ($launcherBase + '.vbs')
$launcherCmdPath = Join-Path $startupDir ($launcherBase + '.cmd')
$removed = New-Object System.Collections.Generic.List[string]

if (Test-Path $launcherVbsPath) {
  Remove-Item -Force $launcherVbsPath
  [void]$removed.Add($launcherVbsPath)
}

if (Test-Path $launcherCmdPath) {
  Remove-Item -Force $launcherCmdPath
  [void]$removed.Add($launcherCmdPath)
}

if ($removed.Count -eq 0) {
  Write-Output "OK|No habia launcher watchdog."
} else {
  Write-Output ("OK|Launchers watchdog eliminados: {0}" -f ($removed -join '; '))
}

param()

$ErrorActionPreference = 'Stop'

$startupDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
$launcherVbsPath = Join-Path $startupDir 'DriveAIAutoOrganizerBooking.vbs'
$launcherCmdPath = Join-Path $startupDir 'DriveAIAutoOrganizerBooking.cmd'
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
  Write-Output "OK|No habia launcher en startup."
} else {
  Write-Output ("OK|Startup launchers eliminados: {0}" -f ($removed -join '; '))
}

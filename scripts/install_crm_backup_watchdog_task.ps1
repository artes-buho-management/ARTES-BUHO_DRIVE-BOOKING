param(
  [string]$TaskName = 'DriveBackupWatchdogBooking',
  [int]$RepeatMinutes = 5
)

$ErrorActionPreference = 'Stop'

$watchdogPath = Join-Path $PSScriptRoot 'backup_daemon_watchdog.ps1'
if (-not (Test-Path $watchdogPath)) {
  throw "No existe $watchdogPath"
}

if ($RepeatMinutes -lt 1) {
  $RepeatMinutes = 1
}

$psExe = 'C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe'
$taskArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$watchdogPath`""

Write-Output "Creando tarea programada watchdog: $TaskName"

try {
  Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
} catch {
}

$action = New-ScheduledTaskAction -Execute $psExe -Argument $taskArgs
$triggerLogon = New-ScheduledTaskTrigger -AtLogOn
$triggerRepeat = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(1)) -RepetitionInterval (New-TimeSpan -Minutes $RepeatMinutes) -RepetitionDuration (New-TimeSpan -Days 3650)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew

Register-ScheduledTask `
  -TaskName $TaskName `
  -Action $action `
  -Trigger @($triggerLogon, $triggerRepeat) `
  -Settings $settings `
  -Description "Watchdog backups Drive booking (cada $RepeatMinutes min)" `
  | Out-Null

Start-ScheduledTask -TaskName $TaskName

Write-Output "OK|TaskName=$TaskName|RepeatMinutes=$RepeatMinutes|Watchdog=$watchdogPath"

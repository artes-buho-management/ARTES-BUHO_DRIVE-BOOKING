param(
  [string]$TaskName = 'DriveBackupWatchdogBooking'
)

$ErrorActionPreference = 'Stop'

try {
  Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
  Write-Output "OK|TaskName=$TaskName|Removed=true"
} catch {
  Write-Output "OK|TaskName=$TaskName|Removed=false"
}

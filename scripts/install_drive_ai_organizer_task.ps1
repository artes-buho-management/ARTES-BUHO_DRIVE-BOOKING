param(
  [string]$TaskName = 'DriveAIAutoOrganizerBooking',
  [string]$Model = $(if ($env:LOCAL_AI_MODEL) { $env:LOCAL_AI_MODEL } else { 'qwen2.5:7b-instruct' }),
  [int]$MaxFilesPerCycle = 25,
  [int]$SleepSeconds = 120,
  [int]$AiRetrySeconds = 30
)

$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot 'drive_ai_organizer.ps1'
if (-not (Test-Path $scriptPath)) {
  throw "No existe $scriptPath"
}

$psExe = 'C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe'
$taskArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -Mode daemon -Model `"$Model`" -MaxFilesPerCycle $MaxFilesPerCycle -SleepSeconds $SleepSeconds -AiRetrySeconds $AiRetrySeconds"

Write-Output "Creando tarea programada: $TaskName"
try {
  Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
} catch {
}

$action = New-ScheduledTaskAction -Execute $psExe -Argument $taskArgs
$trigger = New-ScheduledTaskTrigger -AtLogOn
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -StartWhenAvailable

try {
  Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Description 'Organizador IA local para Google Drive booking' `
    | Out-Null

  Write-Output "Lanzando tarea ahora..."
  Start-ScheduledTask -TaskName $TaskName

  Write-Output "OK|TaskName=$TaskName|Model=$Model|SleepSeconds=$SleepSeconds|MaxFilesPerCycle=$MaxFilesPerCycle"
} catch {
  Write-Output "WARN|No se pudo crear tarea programada (posible falta de permisos)."
  Write-Output "WARN|Usa este metodo alternativo sin admin:"
  Write-Output ("WARN|powershell -NoProfile -ExecutionPolicy Bypass -File .\\scripts\\install_drive_ai_startup.ps1 -Model {0} -MaxFilesPerCycle {1} -SleepSeconds {2} -AiRetrySeconds {3}" -f $Model, $MaxFilesPerCycle, $SleepSeconds, $AiRetrySeconds)
}

param(
  [ValidateSet('run-once', 'daemon')]
  [string]$Mode = 'run-once',
  [string]$SchedulerScriptPath = '',
  [string]$StartupPattern = 'CRM_Backup_*.vbs',
  [int]$LoopSleepSeconds = 300
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($SchedulerScriptPath)) {
  $SchedulerScriptPath = Join-Path $PSScriptRoot 'crm_backup_scheduler.ps1'
}

if (-not (Test-Path $SchedulerScriptPath)) {
  throw "No existe $SchedulerScriptPath"
}

function Run-WatchdogCycle {
  $startupDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
  if (-not (Test-Path $startupDir)) {
    throw "No existe carpeta startup: $startupDir"
  }

  $launchers = @(Get-ChildItem -Path $startupDir -File -Filter $StartupPattern | Sort-Object Name)
  if ($launchers.Count -eq 0) {
    Write-Output 'OK|No hay launchers de backup que vigilar.'
    return
  }

  $runningByKey = @{}
  $running = @(Get-CimInstance Win32_Process | Where-Object {
      $_.Name -eq 'powershell.exe' -and
      $_.CommandLine -like "*$SchedulerScriptPath*" -and
      $_.CommandLine -like '*-Mode daemon*'
    })
  foreach ($proc in $running) {
    if ($proc.CommandLine -match '-BackupKey\s+"?([^"\s]+)"?') {
      $runningByKey[$matches[1]] = $true
    }
  }

  $started = New-Object System.Collections.Generic.List[string]
  $already = New-Object System.Collections.Generic.List[string]

  foreach ($launcher in $launchers) {
    $raw = Get-Content $launcher.FullName -Raw
    $key = ''
    if ($raw -match '-BackupKey\s+""([^"]+)""') {
      $key = $matches[1]
    }

    if (-not [string]::IsNullOrWhiteSpace($key) -and $runningByKey.ContainsKey($key)) {
      [void]$already.Add($launcher.Name)
      continue
    }

    & cscript //nologo $launcher.FullName | Out-Null
    [void]$started.Add($launcher.Name)
  }

  Write-Output ("OK|Launchers={0}|Running={1}|Restarted={2}" -f $launchers.Count, $already.Count, $started.Count)
  if ($started.Count -gt 0) {
    Write-Output ("RESTARTED|{0}" -f ($started -join ','))
  }
}

function Exit-IfAlreadyRunningWatchdogDaemon {
  if ($Mode -ne 'daemon') {
    return
  }

  $selfPath = (Resolve-Path $PSCommandPath).Path
  $other = @(Get-CimInstance Win32_Process | Where-Object {
      $_.Name -eq 'powershell.exe' -and
      $_.ProcessId -ne $PID -and
      $_.CommandLine -like "*$selfPath*" -and
      $_.CommandLine -like '*-Mode daemon*'
    })

  if ($other.Count -gt 0) {
    Write-Output 'OK|Watchdog daemon ya activo. Este proceso se cierra.'
    exit 0
  }
}

Exit-IfAlreadyRunningWatchdogDaemon

if ($Mode -eq 'run-once') {
  Run-WatchdogCycle
  exit 0
}

if ($LoopSleepSeconds -lt 30) {
  $LoopSleepSeconds = 30
}

Write-Output ("OK|Watchdog daemon activo|Sleep={0}s" -f $LoopSleepSeconds)
while ($true) {
  try {
    Run-WatchdogCycle
  } catch {
    Write-Output ("WARN|WatchdogError|{0}" -f $_.Exception.Message)
  }
  Start-Sleep -Seconds $LoopSleepSeconds
}

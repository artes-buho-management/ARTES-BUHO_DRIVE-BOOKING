param(
  [string]$SourceFileId = 'REPLACE_WITH_ID',
  [string]$TargetFolderId = '1rieAe4JZyF39-VQSCUN_3FG4VecRW6V5',
  [string]$SourceDisplayName = 'CRM: MARKETING Y PROMOCION',
  [string]$BackupEmoji = ([string]([char]0xD83D) + [char]0xDE80),
  [string]$BackupEmojiCodepoint = '1F680',
  [string]$BackupEmojiSeparator = ' ',
  [switch]$NoSpaceAfterEmoji,
  [string]$BackupKey = 'crm_marketing_promocion',
  [string]$LauncherFileName = 'CRM_Backup_Marketing.vbs',
  [int]$RunHour = 14,
  [int]$RunMinute = 0
)

$ErrorActionPreference = 'Stop'

function Convert-TextToBase64Utf8 {
  param([string]$Text)
  if ($null -eq $Text) {
    $Text = ''
  }
  return [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Text))
}

function Convert-TextToCodepointSequence {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) {
    return ''
  }

  $parts = New-Object System.Collections.Generic.List[string]
  for ($i = 0; $i -lt $Text.Length;) {
    $cp = [char]::ConvertToUtf32($Text, $i)
    [void]$parts.Add(('{0:X}' -f $cp))
    if ($cp -gt 0xFFFF) {
      $i += 2
    } else {
      $i += 1
    }
  }

  return [string]::Join(' ', $parts)
}

$schedulerPath = Join-Path $PSScriptRoot 'crm_backup_scheduler.ps1'
if (-not (Test-Path $schedulerPath)) {
  throw "No existe $schedulerPath"
}

$startupDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
if (-not (Test-Path $startupDir)) {
  throw "No existe carpeta de inicio: $startupDir"
}

$launcherBase = [System.IO.Path]::GetFileNameWithoutExtension($LauncherFileName)
if ([string]::IsNullOrWhiteSpace($launcherBase)) {
  $launcherBase = 'CRM_Backup_Marketing'
}

$launcherPath = Join-Path $startupDir ($launcherBase + '.vbs')
$legacyCmdPath = Join-Path $startupDir ($launcherBase + '.cmd')
$psExe = 'C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe'
$sourceDisplayNameBase64 = Convert-TextToBase64Utf8 -Text $SourceDisplayName
$effectiveEmojiCodepoint = [string]$BackupEmojiCodepoint
if ([string]::IsNullOrWhiteSpace($effectiveEmojiCodepoint) -and -not [string]::IsNullOrWhiteSpace($BackupEmoji)) {
  $effectiveEmojiCodepoint = Convert-TextToCodepointSequence -Text $BackupEmoji
}

$sourceDisplayNameArg = ''
if (-not [string]::IsNullOrEmpty($sourceDisplayNameBase64)) {
  $sourceDisplayNameArg = " -SourceDisplayNameBase64 """"$sourceDisplayNameBase64"""""
}
$emojiCodepointArg = ''
if (-not [string]::IsNullOrEmpty($effectiveEmojiCodepoint)) {
  $emojiCodepointArg = " -BackupEmojiCodepoint """"$effectiveEmojiCodepoint"""""
}
$emojiSeparatorArg = ''
if (-not [string]::IsNullOrEmpty($BackupEmojiSeparator)) {
  $emojiSeparatorArg = " -BackupEmojiSeparator """"$BackupEmojiSeparator"""""
}
$noSpaceArg = ''
if ($NoSpaceAfterEmoji) {
  $noSpaceArg = ' -NoSpaceAfterEmoji'
}

$content = @"
Set shell = CreateObject("WScript.Shell")
cmd = """$psExe"" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""$schedulerPath"" -Mode daemon -SourceFileId ""$SourceFileId"" -TargetFolderId ""$TargetFolderId""$sourceDisplayNameArg$emojiCodepointArg$emojiSeparatorArg$noSpaceArg -BackupKey ""$BackupKey"" -RunHour $RunHour -RunMinute $RunMinute -LoopSleepSeconds 60"
shell.Run cmd, 0, False
"@

$content | Set-Content -Encoding Unicode $launcherPath

if (Test-Path $legacyCmdPath) {
  Remove-Item -Force $legacyCmdPath
}

${args} = @(
  '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $schedulerPath,
  '-Mode', 'daemon',
  '-SourceFileId', $SourceFileId,
  '-TargetFolderId', $TargetFolderId,
  '-SourceDisplayNameBase64', $sourceDisplayNameBase64
)
if (-not [string]::IsNullOrEmpty($effectiveEmojiCodepoint)) {
  $args += @('-BackupEmojiCodepoint', $effectiveEmojiCodepoint)
}
if (-not [string]::IsNullOrEmpty($BackupEmojiSeparator)) {
  $args += @('-BackupEmojiSeparator', $BackupEmojiSeparator)
}
if ($NoSpaceAfterEmoji) {
  $args += @('-NoSpaceAfterEmoji')
}
$args += @(
  '-BackupKey', $BackupKey,
  '-RunHour', $RunHour,
  '-RunMinute', $RunMinute,
  '-LoopSleepSeconds', '60'
)

Start-Process -FilePath $psExe -ArgumentList $args -WindowStyle Hidden

Write-Output "OK|StartupLauncher=$launcherPath|BackupKey=$BackupKey|RunHour=$RunHour|RunMinute=$RunMinute|StartedNow=true"

# tools/companion/install-startup.ps1 (C-9, WKE-559)
#
# Registers a Task Scheduler task, for the CURRENT USER, that runs
# start-companion.ps1 at logon: the fork's dev server if nothing answers it,
# then `node companion.js --watch`. This is the answer to the question
# docs/ARCHITECTURE.md 11 has carried since 2026-09-08 - neither the dev server
# nor the watcher survives a reboot, and nothing restarted them, so the loop
# quietly stopped working and the only tell was an ageing age on the status
# strip.
#
#   .\install-startup.ps1                  register it
#   .\install-startup.ps1 -Config c.json   ... with a different companion config
#   .\install-startup.ps1 -TaskName '...'  ... under a different task name
#   .\uninstall-startup.ps1                remove it
#
# Idempotent: running it twice replaces the task with the same definition and
# says which of the two happened. It starts nothing itself - a logon (or
# `Start-ScheduledTask -TaskName 'Lootpath companion'`) does, so registering it
# while the owner's own watcher is running is safe.
#
# Windows only, current user only, no password stored: the task runs
# interactively as whoever registered it, which is what "at logon" means and
# what the fork's dev server needs (it wants that user's browser profile).
[CmdletBinding()]
param(
    [string]$TaskName = 'Lootpath companion',
    [string]$Config,
    [switch]$NoFork
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$script = Join-Path $here 'start-companion.ps1'
if (-not (Test-Path -LiteralPath $script)) {
    throw "start-companion.ps1 is not next to this script (looked in $here)"
}

# -WindowStyle Hidden is what keeps the console off the owner's screen; the
# task's own -Hidden setting only hides the task in the Task Scheduler list.
# A console may still flash for an instant at logon - that is Windows, and the
# reboot test is the owner's (WKE-559).
$argumentList = @(
    '-NoProfile'
    '-ExecutionPolicy', 'Bypass'
    '-WindowStyle', 'Hidden'
    '-File', ('"{0}"' -f $script)
)
if ($Config) { $argumentList += @('-Config', ('"{0}"' -f $Config)) }
if ($NoFork) { $argumentList += '-NoFork' }

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ($argumentList -join ' ') -WorkingDirectory $here
$trigger = New-ScheduledTaskTrigger -AtLogOn -User ("{0}\{1}" -f $env:USERDOMAIN, $env:USERNAME)
$principal = New-ScheduledTaskPrincipal -UserId ("{0}\{1}" -f $env:USERDOMAIN, $env:USERNAME) -LogonType Interactive -RunLevel Limited
# MultipleInstances IgnoreNew is the "never two watchers" rule in Windows'
# words; ExecutionTimeLimit zero because a watcher is meant to run all day, and
# the battery settings because a laptop that unplugs should not lose the loop.
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1)

$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null

if ($existing) {
    Write-Host "replaced the scheduled task '$TaskName' (it was already registered)"
} else {
    Write-Host "registered the scheduled task '$TaskName'"
}
Write-Host "it runs at logon, as $env:USERNAME, hidden, from $here"
Write-Host "start it now without logging out:  Start-ScheduledTask -TaskName '$TaskName'"
Write-Host "see what it did last:              Get-ScheduledTaskInfo -TaskName '$TaskName'"
Write-Host "remove it:                         .\uninstall-startup.ps1 -TaskName '$TaskName'"

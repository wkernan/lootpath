# tools/companion/uninstall-startup.ps1 (C-9, WKE-559)
#
# Removes the logon task install-startup.ps1 registered. Idempotent: a task that
# is not there is said out loud and is not an error, so this is safe to run
# twice or to run first.
#
# It does not stop a watcher that is already running. `node companion.js
# --watch` in a window the owner opened is his, and this script never reaches
# into it; Ctrl+C in that window, or `Stop-ScheduledTask`, ends the task's own.
[CmdletBinding()]
param(
    [string]$TaskName = 'Lootpath companion',
    [switch]$Stop
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if (-not $existing) {
    Write-Host "there is no scheduled task '$TaskName'; nothing to remove"
    exit 0
}

if ($Stop -and $existing.State -eq 'Running') {
    Stop-ScheduledTask -TaskName $TaskName
    Write-Host "stopped the running task '$TaskName'"
}

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
Write-Host "removed the scheduled task '$TaskName'"
if (-not $Stop) {
    Write-Host "a watcher it already started keeps running until it is stopped (Ctrl+C in its window, or re-run with -Stop next time)"
}

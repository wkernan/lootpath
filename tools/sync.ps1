# Copy-on-save sync between this repo and the game client.
#
# A copy, never a symlink: a symlink would put the live client one
# `git checkout` away from an addon that does not match the branch it came
# from. The copy is cheap enough that the safety is free. Adapted from the
# Healper spike's sync.ps1 (owner-authored).
#
#   .\tools\sync.ps1            push Lootpath/ into the game, once
#   .\tools\sync.ps1 -Watch     push on every save
#   .\tools\sync.ps1 -Pull      copy SavedVariables back into spec/fixtures/captures/
#
# SavedVariables flush only on /reload or logout: run /reload before -Pull.
[CmdletBinding()]
param(
    [string]$WowPath = 'C:\World of Warcraft\_retail_',
    [switch]$Watch,
    [switch]$Pull
)

$ErrorActionPreference = 'Stop'

$repoAddon = Join-Path $PSScriptRoot '..\Lootpath'
$gameAddons = Join-Path $WowPath 'Interface\AddOns'
$gameAddon = Join-Path $gameAddons 'Lootpath'
$captureDir = Join-Path $PSScriptRoot '..\spec\fixtures\captures'

if (-not (Test-Path $gameAddons)) {
    throw "AddOns directory not found: $gameAddons. Pass -WowPath if the install moved."
}

function Push-Addon {
    foreach ($lib in 'LibStub\LibStub.lua', 'CallbackHandler-1.0\CallbackHandler-1.0.lua', 'AceDB-3.0\AceDB-3.0.lua') {
        if (-not (Test-Path (Join-Path $repoAddon "Libs\$lib"))) {
            Write-Warning "Libs\$lib is missing; the addon will not load. Run .\tools\fetch-libs.ps1 first."
        }
    }
    New-Item -ItemType Directory -Force -Path $gameAddon | Out-Null
    Copy-Item -Path (Join-Path $repoAddon '*') -Destination $gameAddon -Recurse -Force
    Write-Host ("[{0}] pushed to {1}" -f (Get-Date -Format 'HH:mm:ss'), $gameAddon)
}

function Pull-Captures {
    # Account folder names are discovered, not hardcoded, so the script carries
    # no account identifier into a public repo.
    $files = Get-ChildItem -Path (Join-Path $WowPath 'WTF\Account\*\SavedVariables\Lootpath.lua') -ErrorAction SilentlyContinue
    if (-not $files) {
        Write-Warning "No Lootpath.lua SavedVariables found under $WowPath\WTF\Account. Run a capture in game, then /reload before pulling."
        return
    }
    New-Item -ItemType Directory -Force -Path $captureDir | Out-Null
    $i = 0
    foreach ($f in $files) {
        $stamp = $f.LastWriteTime.ToString('yyyyMMdd-HHmmss')
        $suffix = if ($files.Count -gt 1) { "-$i" } else { '' }
        $target = Join-Path $captureDir "Lootpath-$stamp$suffix.lua"
        Copy-Item -Path $f.FullName -Destination $target -Force
        $sizeKb = [Math]::Round((Get-Item $target).Length / 1KB, 1)
        Write-Host ("pulled {0} KB -> {1}" -f $sizeKb, (Resolve-Path $target))
        $i++
    }
}

if ($Pull) {
    Pull-Captures
    return
}

Push-Addon

if (-not $Watch) { return }

Write-Host "watching $repoAddon for changes; Ctrl+C to stop."
$watcher = New-Object System.IO.FileSystemWatcher (Resolve-Path $repoAddon), '*.*'
$watcher.IncludeSubdirectories = $true
$watcher.EnableRaisingEvents = $true
try {
    while ($true) {
        # WaitForChanged blocks without burning CPU. The 2s coalescing window
        # keeps an editor's write-temp-then-rename from firing three pushes.
        $change = $watcher.WaitForChanged([System.IO.WatcherChangeTypes]::All, 1000)
        if (-not $change.TimedOut) {
            Start-Sleep -Milliseconds 200
            Push-Addon
            Start-Sleep -Seconds 2
        }
    }
}
finally {
    $watcher.Dispose()
}

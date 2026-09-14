# Copy-on-save sync between this repo and the game client.
#
# A copy, never a symlink: a symlink would put the live client one
# `git checkout` away from an addon that does not match the branch it came
# from. The copy is cheap enough that the safety is free. Adapted from the
# Healper spike's sync.ps1 (owner-authored).
#
#   .\tools\sync.ps1               push Lootpath/ into the game, once
#   .\tools\sync.ps1 -Watch        push on every save
#   .\tools\sync.ps1 -Pull         copy SavedVariables back into spec/fixtures/captures/
#   .\tools\sync.ps1 -IncludeData  push Lootpath\Data too, overwriting the game's
#
# SavedVariables flush only on /reload or logout: run /reload before -Pull.
#
# Lootpath\Data\ holds the files in the addon whose GAME copies are the real
# ones: QEVerdict.lua, the owner's QE Live exports (C-2, WKE-534), and since C-9
# (WKE-559) CompanionStatus.lua and companion.log, what the companion last did.
# The committed copies are placeholders that set nothing. A push therefore leaves
# an existing game copy of Data\ alone, and writes the placeholders only when the
# game has NEITHER of the two chunks - which it must have, because the .toc names
# both. -IncludeData overwrites them anyway, for when the companion's own files
# are the thing that is broken.
#
# Either file is enough to keep the folder: a run that died before it ever wrote
# a verdict still wrote a status saying so, and a push that replaced that with
# the placeholder would erase the one thing that says what went wrong.
[CmdletBinding()]
param(
    [string]$WowPath = 'C:\World of Warcraft\_retail_',
    [switch]$Watch,
    [switch]$Pull,
    [switch]$IncludeData
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
    # The same copy as before, one top-level child at a time so Data\ can be
    # left out: `-Path <dir> -Destination <the PARENT dir>` is exactly what the
    # `Lootpath\*` wildcard expanded to, and it merges. Naming the destination
    # directory itself (`-Destination $gameAddon\Libs`) does NOT - it nests
    # Libs\Libs on the second push, measured 2026-09-07 against a scratch tree.
    foreach ($child in Get-ChildItem -Path $repoAddon -Force) {
        if ($child.Name -eq 'Data') { continue }
        Copy-Item -Path $child.FullName -Destination $gameAddon -Recurse -Force
    }
    if ($IncludeData) {
        Copy-Item -Path (Join-Path $repoAddon 'Data') -Destination $gameAddon -Recurse -Force
        Write-Host ("[{0}] pushed to {1} (Data included)" -f (Get-Date -Format 'HH:mm:ss'), $gameAddon)
        return
    }
    # A Data\ file the game already has is the companion's and is kept. A Data\
    # file the game LACKS is written from the repo's placeholder, because the
    # .toc lists it and the client raises "Error loading ..." at login for a
    # listed file that is missing - measured 2026-09-14 11:26 when C-9 added
    # Data\CompanionStatus.lua to the .toc and the first sync after it kept the
    # game's Data\ (QEVerdict.lua was there) without adding the new file.
    $gameData = Join-Path $gameAddon 'Data'
    New-Item -ItemType Directory -Force -Path $gameData | Out-Null
    $added = @()
    foreach ($file in Get-ChildItem -Path (Join-Path $repoAddon 'Data') -File) {
        $target = Join-Path $gameData $file.Name
        if (-not (Test-Path $target)) {
            Copy-Item -Path $file.FullName -Destination $target
            $added += $file.Name
        }
    }
    if ($added.Count -gt 0) {
        Write-Host ("[{0}] pushed to {1}; kept the companion's Data\ and added the missing placeholder(s) {2}" -f (Get-Date -Format 'HH:mm:ss'), $gameAddon, ($added -join ', '))
        return
    }
    Write-Host ("[{0}] pushed to {1}; kept the companion's Data\ (-IncludeData overwrites it)" -f (Get-Date -Format 'HH:mm:ss'), $gameAddon)
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

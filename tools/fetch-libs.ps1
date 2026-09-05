# Fetch the embedded libraries into Lootpath/Libs/ for local development.
#
# CI never runs this: the packager checks the same libraries out from the
# wowace SVN trunks named in .pkgmeta. This script exists because a developer
# machine without svn still needs the files present for tools/sync.ps1 to push
# a loadable addon into the game. The GitHub mirror (WoWUIDev/Ace3) tracks the
# same trunk. The fetched directories are gitignored.
[CmdletBinding()]
param(
    [string]$Ref = 'master'
)
$ErrorActionPreference = 'Stop'
$libs = Join-Path $PSScriptRoot '..\Lootpath\Libs'
$base = "https://raw.githubusercontent.com/WoWUIDev/Ace3/$Ref"
$files = @(
    'LibStub/LibStub.lua',
    'CallbackHandler-1.0/CallbackHandler-1.0.lua',
    'CallbackHandler-1.0/CallbackHandler-1.0.xml',
    'AceDB-3.0/AceDB-3.0.lua',
    'AceDB-3.0/AceDB-3.0.xml'
)
foreach ($f in $files) {
    $target = Join-Path $libs $f
    New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
    Invoke-WebRequest -Uri "$base/$f" -OutFile $target -UseBasicParsing
    Write-Host ("fetched {0} ({1} bytes)" -f $f, (Get-Item $target).Length)
}

# Runs every CI gate locally, in the same order CI does, and reports each one.
#
#   .\tools\check.ps1            all gates
#   .\tools\check.ps1 -Only busted
#
# StyLua and lua-language-server run natively (winget installs). luacheck and
# busted run in Docker (tools/docker/Dockerfile) because Lua 5.1 + LuaRocks on
# Windows needs an elevated install this machine does not have; the image is
# Alpine Lua 5.1, the same major/minor CI uses.
[CmdletBinding()]
param(
    [ValidateSet('all', 'luacheck', 'stylua', 'luals', 'busted')]
    [string]$Only = 'all'
)
$ErrorActionPreference = 'Continue'
$repo = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repo
$results = [ordered]@{}

function Invoke-Gate([string]$name, [scriptblock]$body) {
    if ($Only -ne 'all' -and $Only -ne $name) { return }
    Write-Host "`n=== $name ===" -ForegroundColor Cyan
    $global:LASTEXITCODE = 0
    & $body
    $ok = ($LASTEXITCODE -eq 0)
    $results[$name] = $ok
    Write-Host ("--- {0}: {1}" -f $name, $(if ($ok) { 'PASS' } else { 'FAIL' })) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
}

function Ensure-Image {
    docker image inspect lootpath-lua *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'building lootpath-lua image (once)...'
        docker build -t lootpath-lua tools/docker
    }
}

Invoke-Gate 'luacheck' {
    Ensure-Image
    docker run --rm -v "${repo}:/work" lootpath-lua luacheck . --no-color
}

Invoke-Gate 'stylua' {
    stylua --check .
}

Invoke-Gate 'luals' {
    if (-not (Test-Path '.luals/vscode-wow-api/Annotations')) {
        Write-Host 'annotations missing; run .\tools\fetch-annotations.ps1' -ForegroundColor Red
        $global:LASTEXITCODE = 1
        return
    }
    $out = Join-Path ([System.IO.Path]::GetTempPath()) ("luals-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Force -Path $out | Out-Null
    $report = Join-Path $out 'check.json'
    lua-language-server --check="$repo" --configpath="$repo\.luarc.json" --checklevel=Warning `
        --check_format=json --check_out_path="$report" --logpath="$out\log" | Out-Host
    if (-not (Test-Path $report)) {
        Write-Host 'luals: no check.json written' -ForegroundColor Red
        $global:LASTEXITCODE = 1
        return
    }
    # LuaLS writes `[]` when clean and `{ "file:///...": [diagnostic...] }` otherwise.
    $json = Get-Content $report -Raw | ConvertFrom-Json
    $count = 0
    if ($json -isnot [System.Array]) {
        foreach ($prop in $json.PSObject.Properties) {
            foreach ($d in $prop.Value) {
                $count++
                Write-Host ("{0}:{1}: {2}: {3}" -f $prop.Name, ($d.range.start.line + 1), $d.code, $d.message)
            }
        }
    }
    if ($count -gt 0) { $global:LASTEXITCODE = 1 } else { Write-Host 'luals: clean'; $global:LASTEXITCODE = 0 }
}

Invoke-Gate 'busted' {
    Ensure-Image
    docker run --rm -v "${repo}:/work" lootpath-lua busted
}

Write-Host "`n=== summary ===" -ForegroundColor Cyan
$failed = 0
foreach ($k in $results.Keys) {
    $v = $results[$k]
    if (-not $v) { $failed++ }
    Write-Host ("{0,-10} {1}" -f $k, $(if ($v) { 'PASS' } else { 'FAIL' }))
}
exit $failed

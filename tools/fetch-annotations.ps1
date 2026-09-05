# Fetch Ketho's LuaLS annotations (MIT) into .luals/ for `lua-language-server --check`.
# .luarc.json points workspace.library at this checkout. Gitignored; CI does the
# same clone in .github/workflows/ci.yml, so keep the two in step.
[CmdletBinding()]
param(
    [string]$Ref = 'master'
)
$ErrorActionPreference = 'Stop'
$dest = Join-Path $PSScriptRoot '..\.luals\vscode-wow-api'
if (Test-Path $dest) {
    git -C $dest fetch --depth 1 origin $Ref
    git -C $dest checkout --quiet FETCH_HEAD
    git -C $dest submodule update --init --depth 1
} else {
    git clone --depth 1 --branch $Ref --recurse-submodules --shallow-submodules `
        https://github.com/Ketho/vscode-wow-api.git $dest
}
Write-Host ("annotations at {0}: {1}" -f $dest, (git -C $dest rev-parse --short HEAD))

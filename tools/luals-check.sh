#!/usr/bin/env bash
# Runs lua-language-server --check over the repo (only Lootpath/ is not ignored
# by .luarc.json) against Ketho's annotations and fails on any diagnostic at
# Warning or above. LuaLS itself exits 0 whether or not it found problems, so
# the JSON report is what decides. Used by CI; tools/check.ps1 mirrors it.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d .luals/vscode-wow-api/Annotations ]; then
    echo "luals: annotations missing; run tools/fetch-annotations.ps1 (or the CI clone step)" >&2
    exit 1
fi

out="$(mktemp -d)"
lua-language-server \
    --check="$PWD" \
    --configpath="$PWD/.luarc.json" \
    --checklevel=Warning \
    --check_format=json \
    --check_out_path="$out/check.json" \
    --logpath="$out/log" >"$out/stdout" 2>&1 || true
cat "$out/stdout"

if [ ! -f "$out/check.json" ]; then
    echo "luals: no check.json was written; treating as failure" >&2
    exit 1
fi

count=$(jq '[.[] | length] | add // 0' "$out/check.json")
if [ "$count" != "0" ]; then
    echo "luals: $count diagnostic(s):" >&2
    jq -r 'to_entries[] | .key as $f | .value[] | "\($f):\(.range.start.line + 1): \(.code): \(.message)"' "$out/check.json" >&2
    exit 1
fi
echo "luals: clean"

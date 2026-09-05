# Tests

busted over the pure modules, headless, with a hand-written WoW API stub.

```
spec/stubs/wow.lua      the fake client surface (install/uninstall around each test)
spec/helpers/addon.lua  loads Lootpath/ the way the client does: each .toc file, in order,
                        with (addonName, namespace) as its varargs
spec/fixtures/captures  raw SavedVariables transcripts pulled from the owner's client
spec/fixtures/qe        real QE Live Top Gear exports
spec/*_spec.lua         the specs
```

Run locally with `.\tools\check.ps1 -Only busted` (Docker) or, with Lua 5.1 and
busted installed, `busted` from the repo root.

## What the stub is, and is not

The stub's shapes come from Blizzard's exported API docs (Ketho's annotations)
and its build tuple from a real `GetBuildInfo()` capture. Nothing in it comes
from the wiki. It proves that the addon's own logic works over those shapes; it
proves nothing about the client. A test that needs a real return shape reads a
committed fixture under `spec/fixtures/`, and the fixture wins over the stub
whenever they disagree.

## wowless

[wowless](https://github.com/wowless/wowless) (MIT, active) was evaluated on
2026-09-05 and set aside for now. Its API list carries every Encounter Journal
function, but the loot functions return nothing (`mayreturnnothing: true`), so
it cannot stand in for the loot walk that Lootpath depends on. The door stays
open: if it grows journal data, it would replace parts of this stub.

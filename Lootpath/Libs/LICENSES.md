# Embedded libraries and their licences

Every dependency is licence-checked before it is vendored or fetched. Nothing
enters `Libs/` without a line here. Checked 2026-09-05.

| Library | Source | Version / ref | Licence | How it arrives |
|---|---|---|---|---|
| LibStub | https://repos.wowace.com/wow/libstub/trunk (mirror: github.com/WoWUIDev/Ace3) | trunk | Public domain (per the file header) | packager external (`.pkgmeta`); locally `tools/fetch-libs.ps1` |
| CallbackHandler-1.0 | https://repos.wowace.com/wow/callbackhandler/trunk/CallbackHandler-1.0 | trunk | Ace3 BSD-style (below) | packager external; locally `tools/fetch-libs.ps1` |
| AceDB-3.0 | https://repos.wowace.com/wow/ace3/trunk/AceDB-3.0 | trunk | Ace3 BSD-style (below) | packager external; locally `tools/fetch-libs.ps1` |
| json.lua | https://github.com/rxi/json.lua | 0.1.2 (repo pushed 2023-11-28) | MIT (header intact in `Libs/json.lua`) | vendored; the only change is a six-line footer that also exposes the module on the addon namespace, because the WoW loader discards a chunk's return value |

## Data: numbers made by a tool we run (E-7, 2026-10-15)

The row per dataset that `docs/OWN-ENGINE.md` §2c asks for: what made the
numbers, under what licence, the clause relied on, and whether they ship. The
tool itself is never vendored, never committed and never shipped; only its
output is used.

| Dataset | Source | Build and date | Tool and licence | Clause relied on | Written permission | Ships? |
|---|---|---|---|---|---|---|
| Stat scale factors for DPS and tank specs (Balance 102, Feral 103, Guardian 104 first; `tools/simc/`) | SimulationCraft's own sample profiles, read as sim input by path (`profiles/MID2/MID2_Druid_Feral.simc`, `profiles/MID1/MID1_Druid_Balance.simc`, `profiles/MID1/MID1_Druid_Guardian.simc`) | SimC `1210-01`, git `2358079` (game data 12.1.5.70391 Live, hotfix 2026-10-14); nightly archive `simc-1210.01.2358079-win64.7z`, sha256 `b0ec78d5cf533f34d599aba9493183d589e6cb411bfe6d2bbfb0f9fa811fb36f`; run 2026-10-15 | SimulationCraft, **GPL-3.0**; a tool, NOT shipped, output only | GPL-3.0 §2: "The output from running a covered work is covered by this License only if the output, given its content, constitutes a covered work." No `.inc` file, class module, profile or action list is copied; the committed fixtures are SimC's JSON reports and the scale-factor lines of its text reports (`spec/fixtures/simc/reports/README.md`) | none needed | **No.** Developer data only; whether SimC-derived weights ever ship is decided with the weights file (E-4/E-6) |
| Restoration spell facts for the combat-log weights (SP coefficients; the Can't Crit, Periodic Can Crit, Spell Haste Affects Periodic and Ignore Modifiers flags; cast time, GCD, cooldown, charges; Harmony's label 4337 list and coefficient; buff amounts; `tools/combatlog/lib/spells.js`, E-5) | the client's spell data as SimulationCraft's `spell_query` prints it (`spell_query=spell.id=<id>`, `spell_query=spell.label=4337`), committed verbatim as `spec/fixtures/combatlog/simc-spells-70391.txt` | SimC `1210-01`, git `2358079`, game data 12.1.5.70391 (the build above); run 2026-10-17; the file's sha256 `51265c8fcf854e1539c870d3f3eb408aed3ce165668db91e5e6b32449ac838a6` | SimulationCraft, **GPL-3.0**; a tool, NOT shipped, output only | GPL-3.0 §2 as above; Blizzard's numbers, read as facts. No SimC source, `.inc` file or class module was opened | none needed | **No.** Developer data |
| Restoration stat weights from combat logs (`tools/combatlog/`, E-5, WKE-711) | the owner's own `WoWCombatLog.txt`, written by the game with `/combatlog` and Advanced Combat Logging, every other player stripped (`tools/combatlog/anonymise.js`) before it is committed | first log: the Altar of Fangs +12 of 2026-10-17, `spec/fixtures/combatlog/WoWCombatLog-20261017-AltarOfFangs-12.txt.gz`, sha256 `f56583dd549a25b7893fd24e45678edbda837b6c0c376db1497f767d532566dd` | written by the game client; read by our own tool (MIT, this repo) | the owner's own file: it never passes through Warcraft Logs, so RPGLogs' API terms do not reach it (`docs/OWN-ENGINE.md` §2c, an inference, not legal advice) | none needed (the owner's own log; volunteers' logs need their consent and the same stripping) | **No.** Developer data until a dated decision promotes it; the method's clean-room record is below |

## The art, and what made it (UX-4b, 2026-09-16)

Nothing here is loaded by the addon at run time and nothing here is under
`Libs/`, but both are recorded before they arrive for the same reason the table
above exists: a rendered glyph carries its font's licence, so the line comes
first and the file second.

| Thing | Source | Version / ref | Licence | How it arrives |
|---|---|---|---|---|
| Alegreya SC Bold | https://github.com/google/fonts `ofl/alegreyasc/AlegreyaSC-Bold.ttf` (upstream: huertatipografica/Alegreya) | fetched 2026-09-16, 378,796 bytes | **SIL Open Font License 1.1** (`tools/media/fonts/OFL.txt`, "Copyright 2011 The Alegreya Project Authors") | vendored dev-time only, at `tools/media/fonts/`; rendered into `Lootpath/Media/*.tga` and **never shipped inside the addon** |
| @resvg/resvg-js | https://github.com/yisibl/resvg-js | 2.6.2 (with its `@resvg/resvg-js-win32-x64-msvc` 2.6.2 binary) | MPL-2.0 | dev-time only, `npm install` under `tools/media/`, never committed and never packaged |

The OFL permits embedding a font in a document and permits the sale and
redistribution of what is made with it; what it forbids is selling the font by
itself and shipping a modified copy under the reserved name. A rendered texture
is neither. The face itself stays out of the shipped package, so the addon zip
carries no font at all. `tools/media/README.md` says how to re-render.

## Clean-room records

### Healer stat weights from combat logs (E-5, WKE-711, 2026-10-18)

- **The method's only source** is `docs/OWN-ENGINE.md` §2b: our own plain-language
  description, written on 2026-09-30 by the research session that read
  WoWAnalyzer's documented approach (WoWAnalyzer is **AGPL-3.0**).
- **The spec** is `docs/COMBAT-LOG-WEIGHTS.md`, plain language with no code,
  committed as the first commit of E-5's branch (`E-5 (1)`) before any code of
  `tools/combatlog/`; the code was written from it.
- **No WoWAnalyzer code was open** while the spec or the code was written: the
  E-5 agent opened neither WoWAnalyzer's repository nor any copy of it.
- **The MIT Healer Stat Weights addon** (`notarealwzrd`, memo §2a) was not read
  and nothing of it was adapted, so nothing is owed to it. A later change that
  adapts it records it here first.
- **Spell numbers** come from the client's data through SimC's `spell_query`
  (the Data table above), never from QE Live.

## Ace3 licence, embedding clause

From `LICENSE.txt` in WoWUIDev/Ace3 (read 2026-09-05), Copyright (c) 2007,
Ace3 Development Team, all rights reserved. Redistribution and use in source
and binary forms, with or without modification, are permitted provided that
the conditions are met, including:

> Redistributions of source code must retain the above copyright notice, this
> list of conditions and the following disclaimer.
>
> Redistributions in binary form must reproduce the above copyright notice,
> this list of conditions and the following disclaimer in the documentation
> and/or other materials provided with the distribution.
>
> **Redistribution of a stand alone version is strictly prohibited without
> prior written authorization from the Lead of the Ace3 Development Team.**
>
> Neither the name of the Ace3 Development Team nor the names of its
> contributors may be used to endorse or promote products derived from this
> software without specific prior written permission.

Embedding the libraries inside an addon is the permitted form; shipping them
on their own is the prohibited one. Lootpath embeds. The full text ships with
the fetched library folders.

## Not embedded, deliberately

- **Ketho/vscode-wow-api** annotations (MIT): dev-time only, under `.luals/`,
  never packaged.
- **SimulationCraft addon** (Unlicense): the exporter the user installs;
  Lootpath depends on QE Live's JSON, not on this addon's code.
- **QE Live** (Voulk/QuestionablyEpic): no licence file, all rights reserved.
  Read for the schema; nothing copied.

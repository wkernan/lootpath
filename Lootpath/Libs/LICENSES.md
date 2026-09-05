# Embedded libraries and their licences

Every dependency is licence-checked before it is vendored or fetched. Nothing
enters `Libs/` without a line here. Checked 2026-09-05.

| Library | Source | Version / ref | Licence | How it arrives |
|---|---|---|---|---|
| LibStub | https://repos.wowace.com/wow/libstub/trunk (mirror: github.com/WoWUIDev/Ace3) | trunk | Public domain (per the file header) | packager external (`.pkgmeta`); locally `tools/fetch-libs.ps1` |
| CallbackHandler-1.0 | https://repos.wowace.com/wow/callbackhandler/trunk/CallbackHandler-1.0 | trunk | Ace3 BSD-style (below) | packager external; locally `tools/fetch-libs.ps1` |
| AceDB-3.0 | https://repos.wowace.com/wow/ace3/trunk/AceDB-3.0 | trunk | Ace3 BSD-style (below) | packager external; locally `tools/fetch-libs.ps1` |
| json.lua | https://github.com/rxi/json.lua | 0.1.2 (repo pushed 2023-11-28) | MIT (header intact in `Libs/json.lua`) | vendored; the only change is a six-line footer that also exposes the module on the addon namespace, because the WoW loader discards a chunk's return value |

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

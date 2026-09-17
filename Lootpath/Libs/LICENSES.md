# Embedded libraries and their licences

Every dependency is licence-checked before it is vendored or fetched. Nothing
enters `Libs/` without a line here. Checked 2026-09-05.

| Library | Source | Version / ref | Licence | How it arrives |
|---|---|---|---|---|
| LibStub | https://repos.wowace.com/wow/libstub/trunk (mirror: github.com/WoWUIDev/Ace3) | trunk | Public domain (per the file header) | packager external (`.pkgmeta`); locally `tools/fetch-libs.ps1` |
| CallbackHandler-1.0 | https://repos.wowace.com/wow/callbackhandler/trunk/CallbackHandler-1.0 | trunk | Ace3 BSD-style (below) | packager external; locally `tools/fetch-libs.ps1` |
| AceDB-3.0 | https://repos.wowace.com/wow/ace3/trunk/AceDB-3.0 | trunk | Ace3 BSD-style (below) | packager external; locally `tools/fetch-libs.ps1` |
| json.lua | https://github.com/rxi/json.lua | 0.1.2 (repo pushed 2023-11-28) | MIT (header intact in `Libs/json.lua`) | vendored; the only change is a six-line footer that also exposes the module on the addon namespace, because the WoW loader discards a chunk's return value |

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

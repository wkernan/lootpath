# Lootpath

Lootpath puts [QE Live](https://questionablyepic.com/live/)'s gear answers
inside World of Warcraft, next to the loot they are about. One frame shows what
to equip now, where each slot's upgrade drops, and which Great Vault option to
take. **Lootpath never computes a healer value**: every healing number on
screen is QE Live's, transported unchanged from its Top Gear JSON export.

Status: the Equip Now panel works (M2-2). The Upgrade Map and Vault panels are
still to come. See `CHANGELOG.md`.

## The round trip

1. In game, with the [SimulationCraft addon](https://www.curseforge.com/wow/addons/simulationcraft)
   installed: open the Great Vault window once, then `/simc` and copy the string.
2. At questionablyepic.com/live: import it, run **Top Gear**, and use
   **Download JSON** on the report. (That control is not on the live site yet -
   see `docs/ARCHITECTURE.md` section 4.)
3. In game: `/lootpath`, paste the JSON into the box and press **Import**. The
   Equip Now panel then lists every slot QE Live's set names, with an **Equip**
   button on each item you own but are not wearing.

QE Live has two content types, **Dungeon** (its name for Mythic+) and **Raid**.
Lootpath keeps one import of each; `/lootpath options` chooses which one the
panels read. Nothing equips in combat.

Values shown are QE Live's, for items it has ranked. Other drops are listed by
item level only.

## Requirements

- World of Warcraft Retail, Midnight 12.1 (Interface 120100).
- The SimulationCraft addon, which is the exporter QE Live expects. Lootpath
  builds no exporter of its own.

## Development

Everything is documented in `docs/ARCHITECTURE.md`; the working rules are in
`CLAUDE.md`.

```powershell
.\tools\fetch-libs.ps1          # Ace3 libraries into Lootpath/Libs (gitignored)
.\tools\fetch-annotations.ps1   # Ketho's WoW API annotations into .luals (gitignored)
.\tools\check.ps1               # every CI gate, locally
.\tools\sync.ps1                # copy the addon into the game; -Watch; -Pull
```

In game: `/lootpath` opens the frame, `/lootpath options` the settings page,
`/lootpath help` lists every command. Captures:
`/lootpath capture env|inventory|vault|journal`, then `/reload` and
`.\tools\sync.ps1 -Pull`. `journal` runs asynchronously (it waits on the
Encounter Journal's loot events) and reports when it finishes; it takes an
optional Mythic+ preview level, e.g. `/lootpath capture journal 14`.

## Licence

MIT. Embedded libraries and their licences are listed in
`Lootpath/Libs/LICENSES.md`.

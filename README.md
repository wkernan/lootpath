# Lootpath

Lootpath puts [QE Live](https://questionablyepic.com/live/)'s gear answers
inside World of Warcraft, next to the loot they are about. One frame shows what
to equip now, where each slot's upgrade drops, and which Great Vault option to
take. **Lootpath never computes a healer value**: every healing number on
screen is QE Live's, transported unchanged from its Top Gear JSON export.

Status: skeleton (M0-1). No panels yet. See `CHANGELOG.md`.

## The round trip

1. In game, with the [SimulationCraft addon](https://www.curseforge.com/wow/addons/simulationcraft)
   installed: open the Great Vault window once, then `/simc` and copy the string.
2. At questionablyepic.com/live: import it, run **Top Gear**, and use
   **Download JSON** on the report.
3. In game: `/lootpath`, paste the JSON. (The paste frame arrives in M2-2.)

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

In game: `/lootpath help`. Captures: `/lootpath capture env|inventory|vault`,
then `/reload` and `.\tools\sync.ps1 -Pull`.

## Licence

MIT. Embedded libraries and their licences are listed in
`Lootpath/Libs/LICENSES.md`.

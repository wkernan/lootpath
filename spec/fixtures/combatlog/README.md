# Combat-log fixtures (E-5, WKE-711)

The game's own `WoWCombatLog.txt`, written by `/combatlog` with Advanced Combat
Logging on, is the input to the combat-log weights tool (`tools/combatlog/`,
route C - `docs/ARCHITECTURE.md` §7, 2026-10-15 early morning). Each fixture
here is one segment of the owner's log, every player but the owner replaced
(`tools/combatlog/anonymise.py`), gzipped, with its sha256s below. The raw logs
never enter the repo; the owner keeps them.

## WoWCombatLog-20261017-AltarOfFangs-12.txt.gz

- **What it is:** the owner's completed Altar of Fangs +12 key on 2026-10-17,
  healed in Restoration (spec 105 in every `COMBATANT_INFO` of his), from
  `CHALLENGE_MODE_START` at 21:56:14.468 CDT to `CHALLENGE_MODE_END` at
  22:16:10.604 (`1,12,1218077` - timed, level 12, 1,218,077 ms). Cut from
  `WoWCombatLog-101726_202201.txt` (74,162,396 bytes; header
  `COMBAT_LOG_VERSION,22,ADVANCED_LOG_ENABLED,1,BUILD_VERSION,12.1.5,PROJECT_ID,1`).
  That file also held two earlier, abandoned Altar of Fangs keys (+14, +11),
  left out.
- **Stripping:** four other players (by `tools/combatlog/anonymise.py`, which E-5
  replaced with the Node `tools/combatlog/anonymise.js`: run over this file it
  changes nothing - the same sha256 out as in - and its tests hold that). Each GUID became `Player-0-0000000N` and
  each `Name-Realm-US` became `PlayerN-Realm`, consistently, including GUIDs in
  the advanced fields (pets carry their owner's). Nothing else changed:
  190,265 lines in and out. The script re-scanned its output and found no
  original name or GUID; the coordinator grepped the four names, three realms
  and four GUID tails - 0 each. The owner (`Player-69-0CC01A11`,
  `Hotornot-Arthas-US`) is kept.
- **Counts** (Python over the stripped text): `SPELL_HEAL` 16,815,
  `SPELL_PERIODIC_HEAL` 10,498, `SPELL_ABSORBED` 2,548, `SPELL_AURA_APPLIED`
  13,897, `SPELL_AURA_REFRESH` 19,542, `SPELL_AURA_REMOVED` 12,954,
  `SPELL_CAST_SUCCESS` 9,488, `COMBATANT_INFO` 20, `ENCOUNTER_START`/`END` 3 each
  (Rav'i, The Writhing Coil, Zul'jan), `UNIT_DIED` 168. The owner's heal events:
  19,257, of which 10,838 carry overheal > 0 and 2,892 the crit flag.
- **Field shape, read from the file** (corrected by E-5's parser,
  `tools/combatlog/test/parse.test.js`): a `SPELL_HEAL` line has 36 comma
  fields - the 9 base, 3 spell, **19** advanced (unit GUID, owner GUID, hp, max
  hp, attack power, spell power, armor, then three fields, then power type,
  power, max power, power cost, x, y, map, facing, level) and `amount,
  baseAmount, overheal, absorbed, critical` (`nil` or `1`); amount includes the
  overheal. The advanced block of a heal describes its target, of a cast its
  caster. `COMBATANT_INFO` carries, after the GUID and a faction field,
  strength, agility, stamina, intellect, **four** fields, crit x3, speed,
  lifesteal, haste x3, avoidance, mastery, versatility x3, armor, spec, then the
  talent list, a group, the gear and the auras (caster, spell, count). The
  earlier wording here named 17 advanced fields and three before crit; the
  file carries 19 and four.
- **sha256:** stripped plain text `ea8e8098614620b277d741e65e6fbbbfb0723e39f132730abd7707065419f870`
  (57,111,645 bytes); the gzip as committed
  `f56583dd549a25b7893fd24e45678edbda837b6c0c376db1497f767d532566dd`
  (4,328,430 bytes; `gzip -9`, mtime 0). The unstripped segment:
  `e5bd02c07d2393759eb5be8e7b4f2738d4a5fc217c78a8c044f9596d1da92cea`
  (59,223,581 bytes), kept by the owner only.

Also recorded that evening, not committed: `WoWCombatLog-101726_181457.txt`
(92,450,055 bytes), a Temple of Sethraliss +12 whose `CHALLENGE_MODE_START` fell
before logging began (four `ENCOUNTER_START`/`END` pairs, `CHALLENGE_MODE_END`
`1,12,1620397`). The owner also uploaded the evening to Warcraft Logs
(`reports/1Pt2mNAhTjnfcX7H`); Lootpath reads nothing from there.

## simc-spells-70391.txt (E-5's spell table source)

The client's spell data for every spell `docs/COMBAT-LOG-WEIGHTS.md` §5's table
rests on, as SimulationCraft prints it: one `simc.exe spell_query=spell.id=<id>`
per spell and one `spell_query=spell.label=4337`, each output verbatim after its
first line (the build line, quoted once at the top). SimC `1210-01`, git
`2358079`, game data 12.1.5.70391 (`C:\tmp\simc`, E-7's build; GPL-3.0, a tool,
output only - `Lootpath/Libs/LICENSES.md`). Run 2026-10-17. sha256
`51265c8fcf854e1539c870d3f3eb408aed3ce165668db91e5e6b32449ac838a6` (67,028 bytes, LF line endings).

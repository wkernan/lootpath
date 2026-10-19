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

## WoWCombatLog-20261018-VoidscarArena-12.txt.gz

- **What it is:** the owner's completed Voidscar Arena +12 later the same night, healed in
  Restoration (spec 105 in all four of the owner's `COMBATANT_INFO`), from `CHALLENGE_MODE_START`
  at 00:35:49.820 CDT on 2026-10-18 to `CHALLENGE_MODE_END` at 00:59:43.240 (`1,12,1470280` -
  timed, level 12, 1,470,280 ms). Cut from the same `WoWCombatLog-101726_202201.txt`, which the
  game kept appending to after the Altar key (138,392,877 bytes by 01:05); lines 237,328-435,386
  of it. Encounters Taz'Rah, Atroxus, Charonus.
- **Stripping:** `node tools/combatlog/anonymise.js` (the merged tool), four other players ->
  `Player-0-0000000N` / `PlayerN-Realm`, 198,059 lines in and out; the coordinator re-checked:
  no original name, bare name or GUID left. The owner kept.
- **Counts** (Python over the stripped text): `SPELL_HEAL` 19,493, `SPELL_PERIODIC_HEAL` 12,956,
  `SPELL_ABSORBED` 1,467, `SPELL_AURA_APPLIED` 11,244, `SPELL_AURA_REFRESH` 17,528,
  `SPELL_AURA_REMOVED` 9,969, `SPELL_CAST_SUCCESS` 10,196, `COMBATANT_INFO` 20,
  `ENCOUNTER_START`/`END` 3 each, `UNIT_DIED` 142. The owner's heal events: 23,105, of which
  13,161 carry overheal > 0 and 3,344 the crit flag.
- **sha256:** stripped plain text `bf4a55f4a7e087d5aa2c76c9fc9bb7415e94090e73d2685eedeb0b2f4315426e`
  (61,115,928 bytes); the gzip as committed
  `6f699427982a5b8211c342669eefbc668222207a9371919020cb133aad9746a3` (4,558,159 bytes). The
  unstripped segment: `5645c7e9c4ca3eae366530a8029e25df452d527c9d786f7178e1814a9227d81f`
  (63,619,523 bytes), kept by the owner only.

## WoWCombatLog-20261018-RubyLifePools-12.txt.gz

- **What it is:** the owner's Ruby Life Pools +12 on 2026-10-18, healed in Restoration (spec 105 in every
  `COMBATANT_INFO` of his), 14:41:11.438-15:02:02.704 CDT; `CHALLENGE_MODE_END` `1,12,1272737`. Cut from `WoWCombatLog-101826_143901.txt` (311,487,695 bytes; header `COMBAT_LOG_VERSION,22,ADVANCED_LOG_ENABLED,1,BUILD_VERSION,12.1.5`),
  lines 125-185,835 (185,711 lines).
- **Stripping:** `node tools/combatlog/anonymise.js`; four other players -> `PlayerN-Realm`; re-checked: no
  original name, bare name or GUID left. The owner kept.
- **Counts** (Python over the stripped text): `SPELL_HEAL` 20,727, `SPELL_PERIODIC_HEAL` 10,653, `SPELL_ABSORBED` 10,183, `COMBATANT_INFO` 20, encounters 3, `UNIT_DIED` 184; the owner's heal events 21,699 (12,453 with overheal, 3,554 crits).
- **sha256:** gzip as committed `5adbaf81ac9003267179a5dca9e13e275d04c432aa80cc4b55811f08711f4f24` (4,195,654 bytes); stripped plain `82b08793f342c006224929c78e506476ab3c9b8a973c7c0f01e8a66186d9d17b`
  (55,992,545 bytes); the unstripped segment `3f09ce59f09486133bde7dfdd1c6db9790407757f07a34b98ed60c80d42330f5` (58,040,288 bytes), kept by the owner only.

## WoWCombatLog-20261018-MurderRow-12.txt.gz

- **What it is:** the owner's Murder Row +12 on 2026-10-18, healed in Restoration (spec 105 in every
  `COMBATANT_INFO` of his), 16:07:24.401-16:33:49.829 CDT; `CHALLENGE_MODE_END` `1,12,1681926`. Cut from `WoWCombatLog-101826_143901.txt` (311,487,695 bytes; header `COMBAT_LOG_VERSION,22,ADVANCED_LOG_ENABLED,1,BUILD_VERSION,12.1.5`),
  lines 187,012-442,922 (255,911 lines).
- **Stripping:** `node tools/combatlog/anonymise.js`; four other players -> `PlayerN-Realm`; re-checked: no
  original name, bare name or GUID left. The owner kept.
- **Counts** (Python over the stripped text): `SPELL_HEAL` 20,912, `SPELL_PERIODIC_HEAL` 13,634, `SPELL_ABSORBED` 7,468, `COMBATANT_INFO` 25, encounters 4, `UNIT_DIED` 170; the owner's heal events 25,381 (12,913 with overheal, 4,288 crits).
- **sha256:** gzip as committed `7ed3ee5546da6beeba8b3a268979682d2fd1e6260a99fce4dfba8dae2345be0b` (5,823,824 bytes); stripped plain `0a7c7d58068d19e9328e8ea8563b4489d1c9628aaf4f9577bee8eb48831f988b`
  (78,377,328 bytes); the unstripped segment `9a8d51890c45cb1c24b9001c223c0a45005dc4b08b31ef2d89f4a8b5635cc246` (81,087,910 bytes), kept by the owner only.

## WoWCombatLog-20261018-BlindingVale-12.txt.gz

- **What it is:** the owner's The Blinding Vale +12 on 2026-10-18, healed in Restoration (spec 105 in every
  `COMBATANT_INFO` of his), 17:31:56.638-17:57:07.209 CDT; `CHALLENGE_MODE_END` `1,12,1652435`. Cut from `WoWCombatLog-101826_143901.txt` (311,487,695 bytes; header `COMBAT_LOG_VERSION,22,ADVANCED_LOG_ENABLED,1,BUILD_VERSION,12.1.5`),
  lines 444,678-689,296 (244,619 lines).
- **Stripping:** `node tools/combatlog/anonymise.js`; four other players -> `PlayerN-Realm`; re-checked: no
  original name, bare name or GUID left. The owner kept.
- **Counts** (Python over the stripped text): `SPELL_HEAL` 20,920, `SPELL_PERIODIC_HEAL` 12,886, `SPELL_ABSORBED` 3,628, `COMBATANT_INFO` 25, encounters 4, `UNIT_DIED` 609; the owner's heal events 25,208 (13,772 with overheal, 3,897 crits).
- **sha256:** gzip as committed `990de928fad429db86e5595ca105069292a126aaba4d983a06f1411775f3559f` (5,705,175 bytes); stripped plain `75bf6b1dbaf2e14b8ed6c8b4d058558838de63e7c87f350103f8172e407b14ee`
  (74,731,507 bytes); the unstripped segment `1d22aebaa0b51ec012af12edc24eed6a43dc56b5767eb20b00e6e6f5091327b2` (77,275,597 bytes), kept by the owner only.

## WoWCombatLog-20261018-KingsRest-12.txt.gz

- **What it is:** the owner's Kings' Rest +12, NOT completed (no `CHALLENGE_MODE_END`; the Council of Tribes and King Dazar each wiped, King Dazar twice) on 2026-10-18, healed in Restoration (spec 105 in every
  `COMBATANT_INFO` of his), 18:31:22.625-19:09:16.117 (cut at the last `ENCOUNTER_END`, before the walk out into Silvermoon City brought 13 passers-by into the log) CDT; `CHALLENGE_MODE_END` none. Cut from `WoWCombatLog-101826_143901.txt` (311,487,695 bytes; header `COMBAT_LOG_VERSION,22,ADVANCED_LOG_ENABLED,1,BUILD_VERSION,12.1.5`),
  lines 691,052-988,602 (297,551 lines).
- **Stripping:** `node tools/combatlog/anonymise.js`; four other players -> `PlayerN-Realm`; re-checked: no
  original name, bare name or GUID left. The owner kept.
- **Counts** (Python over the stripped text): `SPELL_HEAL` 41,334, `SPELL_PERIODIC_HEAL` 17,644, `SPELL_ABSORBED` 6,603, `COMBATANT_INFO` 35, encounters 6 (two wipes on King Dazar, one on the Council), `UNIT_DIED` 135; the owner's heal events 35,325 (20,876 with overheal, 5,449 crits).
- **sha256:** gzip as committed `15ad3a2670c810dcaab37883eadde84591a2550695629481974e7492e5ee3f6f` (6,886,630 bytes); stripped plain `8f1b0684bbfb2d1e7eda35d78923e0c55b5b94d355b0f991baf460606b3e165b`
  (89,343,950 bytes); the unstripped segment `55545c29011b89d85dde0848c59d9f132b482fef254f1d890c765ee732c93f92` (92,956,474 bytes), kept by the owner only.

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

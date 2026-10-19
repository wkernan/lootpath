# Healer stat weights from the game's own combat log: the clean-room spec (E-5, WKE-711)

**What this is.** The plain-language method by which `tools/combatlog/` turns a
`WoWCombatLog.txt` the game wrote into stat weights for one healing spec,
Restoration Druid (spec 105) first. It was written before any of the tool's code,
in the first commit of E-5, and the code was written from it. It holds no code.
The owner's route C (ARCHITECTURE.md §7, 2026-10-15 early morning): the weights
that may one day ship to players come from combat logs, never from fitting to QE
Live's output.

**What it is not.** Not a player surface. The tool's output is developer data
for the developer engine (CLAUDE.md's scoped exception) until a dated decision
promotes it. Lootpath never shows a player a healing number it computed.

## 0. The clean-room record

- **The method's source** is `docs/OWN-ENGINE.md` §2b: the per-event method in
  our own words, written on 2026-09-30 by the research session that read
  WoWAnalyzer's documented approach (AGPL-3.0). That memo is the only
  description of the method this spec was written from.
- **No WoWAnalyzer code was open** while this spec or any of the tool's code was
  written. The E-5 agent did not open WoWAnalyzer's repository or any copy of it.
- **The MIT Healer Stat Weights addon** (`notarealwzrd`, memo §2a) may be studied
  and adapted. **It was not used:** nothing of it was read for E-5, so nothing is
  owed to it. If a later change adapts it, `Lootpath/Libs/LICENSES.md` records it
  first.
- **Spell facts** (coefficients, which spells crit, which ticks haste speeds,
  which heal-over-time effects Harmony counts, the mastery coefficient) come from
  the client's own data through SimulationCraft's `spell_query`, as numbers.
  SimC `1210-01`, git `2358079`, game data `12.1.5.70391` (the build E-7 fetched,
  kept at `C:\tmp\simc`, never in the repo; GPL-3.0, a tool, output only). Every
  query the table in §5 rests on is committed verbatim as
  `spec/fixtures/combatlog/simc-spells-70391.txt`: one
  `simc.exe spell_query=spell.id=<id>` per spell and one
  `spell_query=spell.label=4337`. No SimC source file, `.inc` file or class
  module was opened.
- **Nothing from QE Live** is used: not its spell data, not its weights.
- **Warcraft Logs** is not read (memo §2c).

## 1. The input, as read from the committed file

The committed fixture is `spec/fixtures/combatlog/WoWCombatLog-20261017-AltarOfFangs-12.txt.gz`
(the owner's completed Altar of Fangs +12, 2026-10-17; its README has the
counts and sha256s). Everything in this section was read from that file, not
from any wiki.

- The first line of a raw log is a header naming `COMBAT_LOG_VERSION` 22,
  `ADVANCED_LOG_ENABLED` 1 and `BUILD_VERSION` 12.1.5 (the README quotes it; the
  committed segment starts at the key, so it has no header).
- Every line is a timestamp (`month/day/year hour:minute:second.millis` and a
  UTC offset such as `-5`), two spaces, then comma-separated fields. A field may
  be a quoted string (which may hold commas), or a bracketed or parenthesised
  list (which holds commas too); a field ends at a comma outside quotes and
  outside any bracket.
- **Heal events** (`SPELL_HEAL`, `SPELL_PERIODIC_HEAL`): 36 fields. Counting
  the event name as field 1: fields 2-9 are the source GUID, source name,
  source flags, source raid flags, target GUID, target name, target flags,
  target raid flags; 10-12 are spell ID, spell name, school; 13-31 are the
  advanced block (19 fields - the README's list of 17 names misses two, see
  below); 32-36 are amount, base amount, overheal, absorbed, critical. The
  critical field is `1` or `nil`. **Amount includes the overheal:** a heal on a
  target at full health reads amount, base amount and overheal all equal (the
  first heals of the key, on targets at full health, show it).
- **The advanced block** for a heal describes the TARGET (its GUID is field 13);
  for a cast (`SPELL_CAST_SUCCESS`, 31 fields) it describes the CASTER. Its
  fields 15-18 are current health, maximum health, attack power and spell power;
  field 19 is armour (it equals the armour in that unit's `COMBATANT_INFO`).
  After armour come three fields before the power type, power, maximum power and
  power cost, then x, y, map, facing and item level. Of the advanced block the
  method reads only the unit GUID and its spell power. **The druid's spell power
  equals her Intellect** in this file: 3,076 in her `COMBATANT_INFO` and 3,076 in
  her first casts' advanced block, rising to 3,093, 3,111 and 3,127 while an
  Intellect proc is up.
- **Aura events** (`SPELL_AURA_APPLIED`, `_REFRESH`, `_REMOVED`, and the
  `_DOSE` forms): the 12 base and spell fields, then `BUFF` or `DEBUFF`.
- **`COMBATANT_INFO`**: the player GUID, a faction field, then strength,
  agility, stamina, intellect, then four fields before the three crit ratings
  (the README names three - dodge, parry, block - but the file carries four),
  then speed, leech, the three haste ratings, avoidance, mastery, the three
  versatility ratings, armour and the spec ID, then the talent list, gear and
  auras in brackets. Every player's three crit, three haste and three
  versatility ratings are equal in every line of the fixture. One line per
  player at `CHALLENGE_MODE_START` and at each `ENCOUNTER_START`. Its ratings
  are the gear's and permanent effects', not temporary buffs': the druid's four
  lines are identical although her procs came and went.
- **`CHALLENGE_MODE_START`**: zone name, instance ID, a map ID, **the key
  level**, the affixes. **`CHALLENGE_MODE_END`**: instance ID, success flag, key
  level, duration in milliseconds. **`ENCOUNTER_START`**: encounter ID, name,
  difficulty, group size, instance ID; **`ENCOUNTER_END`** adds the kill flag and
  the fight's length.

## 2. Whose healing, and how much of it counted

- **The player** is named by GUID. When none is named, the player is the one
  GUID whose `COMBATANT_INFO` carries a healing spec the tool knows (105); the
  tool refuses a file with none or with two.
- **Heal events** are `SPELL_HEAL` and `SPELL_PERIODIC_HEAL` whose SOURCE is the
  player. Heals whose source is a guardian or pet of hers (the source flags say
  "mine" and "guardian" or "pet": the fixture's Treants casting Nourish, flags
  `0x2111`) are counted and reported, not valued, in this version: what scales
  a guardian's heal is not in the table.
- **Raw** R = amount; **overheal** O = the overheal field; **effective**
  E = R - O. The absorbed field (healing eaten by a heal absorb) stays inside E:
  it removed something the target needed removed.
- **Absorb events** the player causes (`SPELL_ABSORBED` naming her as the
  absorbing aura's caster - in the fixture only Matted Fur, on herself) are
  counted and reported, never valued.

## 3. The stat tracker: the player's stats at each moment

- **Intellect** is read from the advanced block wherever the player is its unit
  (her own casts, her heals on herself): the latest reading before an event is
  her Intellect at that event. Before the first reading, her `COMBATANT_INFO`
  intellect. This sees every Intellect proc without a table of them.
- **Ratings** come from her latest `COMBATANT_INFO` (crit, haste, mastery and
  versatility read from the spell column of each triple, leech from its own
  field), plus the rating buffs whose amount the client data gives. A buff whose
  amount the client data does not give (a trinket or rune proc scaled by item
  level) is **not added**; the tool lists every such buff the player had and the
  share of her effective healing done while it was up, so the size of what the
  tracker missed is read, not guessed.
- **Percent buffs** the client data gives with an amount: Mark of the Wild,
  +3% versatility (spell 1126). Versatility percent from buffs adds to the
  percent from rating.
- **Haste percent buffs** (Lycara's Teachings in caster form, Void-touched
  Drums, Bloodlust and the like) multiply haste. They do not move a haste weight
  at all (§6), so the tracker records them and values nothing from them.

## 4. Rating to percent

- Through the brackets `Lootpath/Data/EngineWeights.lua` carries in its `dr`
  table: rating per percent and, per bracket, the penalty on the rating inside
  it. The tool reads them from that file, so the addon and the tool convert the
  same way.
- **Mastery points** for Harmony are 8 plus the mastery rating's percent. The 8
  is read from the owner's committed transcript of 2026-10-01
  (`spec/fixtures/captures/Lootpath-20261001-092631.lua`): mastery rating 985
  converted to 21.413 points, and `GetMasteryEffect` answered 38.5605 with a
  coefficient of 1.311 - 38.5605 / 1.311 - 21.413 = 8.000.
- **Harmony per heal-over-time effect** is mastery points times 1.311 percent
  (Mastery: Harmony, spell 77495, "SP Coefficient: 1.311").
- **The slope** of percent against rating at the current rating is (1 - the
  penalty of the bracket the rating sits in) / rating per percent. It turns a
  weight per percent into a weight per rating point.

## 5. Which stat scales which Restoration spell

Every row is read from `spec/fixtures/combatlog/simc-spells-70391.txt`. The
rules the columns follow:

- **Int**: the spell has a spell-power coefficient, or it heals for a share of
  another of the druid's heals that has one ("share" below).
- **Crit**: the spell does not carry "Can't Crit (93)"; for a periodic tick,
  the spell carries "Periodic Can Crit (265)".
- **Haste, tick**: the event is a tick of a spell carrying "Spell Haste Affects
  Periodic (173)" - or, for Efflorescence's heal, the pulse that drives it
  (81262) carries it.
- **Haste, cast**: faster casting means proportionally more of the heal - the
  spell (or the spell it is a share or a child of) has a cast time or a global
  cooldown and no cooldown, charge or limit of its own. A cooldown, a charge
  or a "Limit" means more haste does not mean more casts.
- **Mastery**: Harmony raises the druid's healing unless the spell carries
  "Ignore Caster Modifiers (125)", "Ignore Healing Modifiers (219)" or "Ignore
  Caster Healing Modifiers (312)". A share heal is not raised a second time.
- **Vers**: as mastery: unless one of those three attributes - except that a
  share inherits the versatility of the heal it is a share of.
- **Harmony counts** the druid's heal-over-time effects that carry label 4337 in
  the client data: Rejuvenation 774, Regrowth 8936, Lifebloom 33763, Wild Growth
  48438, Cenarion Ward 102352, Rejuvenation (Germination) 155777, Tranquility
  157982 (`spell_query=spell.label=4337`, exactly those seven). That the label
  is Harmony's list is our reading (no field names it); §8's probe checks it
  against the fixture's own tick sizes.
- **A spell not in the table** counts for crit and versatility only (memo §2b).

| Spell | ID | Kind | Coefficient (SimC) | Int | Crit | Haste tick | Haste cast | Mastery | Vers |
|---|---|---|---|---|---|---|---|---|---|
| Rejuvenation | 774 | coefficient | periodic 0.924 | yes | yes (265) | yes (173) | yes (GCD) | yes | yes |
| Rejuvenation (Germination) | 155777 | coefficient | periodic 0.924 | yes | yes (265) | yes (173) | yes (from a Rejuvenation cast) | yes | yes |
| Regrowth | 8936 | coefficient | direct 5.36, periodic 0.224968 | yes | yes; ticks (265) | ticks only (173) | yes (1.5 s cast) | yes | yes |
| Lifebloom | 33763 | coefficient | periodic 0.2684 | yes | yes (265) | yes (173) | yes (GCD) | yes | yes |
| Lifebloom (bloom) | 33778 | coefficient | direct 2.18868 | yes | yes | no | yes (child of 33763) | yes | yes |
| Wild Growth | 48438 | coefficient | periodic 0.481 | yes | yes (265) | yes (173) | no (10 s cooldown) | yes | yes |
| Cenarion Ward | 102352 | coefficient | periodic 1.3272 | yes | yes (265) | yes (173) | no (talent proc in this build) | yes | yes |
| Efflorescence | 81269 | coefficient | direct 0.5856 | yes | yes | yes (pulse 81262 has 173) | no (cast 1232285 has Limit 1) | yes | yes |
| Verdancy | 392329 | coefficient | direct 1.33 | yes | yes | no | yes (child of the bloom) | yes | yes |
| Swiftmend | 18562 | coefficient | direct 10.37 | yes | yes | no | no (1 charge, 15 s) | yes | yes |
| Bursting Growth | 440121 | coefficient | direct 0.4209 | yes | yes | no | no (proc) | yes | yes |
| Symbiotic Blooms | 439530 | coefficient | periodic 0.732 | yes | yes (265) | no (no 173) | no (proc) | yes | yes |
| Flower Walk | 439902 | coefficient | direct 0.2 | yes | yes | no | no (Barkskin) | yes | yes |
| Everbloom | 1244341 | share of the bloom | - | yes | no (93) | no | yes (child of the bloom) | no (312) | inherits |
| Thriving Vegetation | 447132 | share of Rejuvenation | - | yes | yes | no | yes (from a Rejuvenation cast) | no (312) | inherits |
| Nature's Bounty | 1264376 | share of Regrowth | - | yes | no (93) | no | yes (from a Regrowth cast) | no (219) | inherits |
| Regenerative Heartwood | 392117 | share of Rejuvenation | - | yes | no (93) | no | yes (from a Rejuvenation cast) | no (125, 219) | inherits |
| Symbiotic Relationship | 474760 | share of any heal | - | yes | no (93) | no | no (mixed parents) | no (125, 219) | inherits |
| Frenzied Regeneration | 22842 | fixed (% of health) | - | no | no (93) | no | no | yes | yes |
| Aessina's Renewal | 474683 | fixed (% of health) | - | no | no (93) | no | no | no (125, 219) | no |
| Lethal Preservation | 455470, 455474 | fixed (% of health) | - | no | no (93) | no | no | no (219) | no |
| Rune of Unleashed Fire | 1263002 | fixed (item rune) | - | no | no (93) | no | no | yes | yes |
| Rune of Lingering | 1287665 | fixed (item rune) | - | no | no (no 265) | no (no 173) | no | yes | yes |
| Rune of Self-Mending | 1287908 | fixed (item rune) | - | no | yes | no | no | yes | yes |
| Leech | 143924 | leech | - | leech only | - | - | - | - | - |

Tranquility (157982) is in Harmony's list and not in the table above: the druid
cast none in the fixture. A spell enters the table when a log needs it, from
the same query, in the same commit as the log.

## 6. What one heal event is worth to each stat

Notation: E effective, O overheal, R raw, for one event; Int her Intellect at
that moment; v her versatility as a fraction (percent / 100); h her haste from
rating as a fraction; P her mastery points; n the number of Harmony's effects
of hers on the target at that moment; T(n) the stack table below; κ the crit
multiplier. Each stat's gain is "how much more effective healing this event
would have done with one more percent of the stat" (one more point, for
Intellect).

- **The overheal rule.** An event with any overheal (O > 0) is worth nothing to
  any stat except leech: a heal that partly overheals does the same effective
  healing whatever its raw size, so a stronger heal would have added nothing.
  Every rule below applies to events with O = 0 only.
- **Intellect**, for a spell whose Int column is yes: E / Int per point.
- **Versatility**, where the Vers column says yes or inherits: E / (1 + v) per
  fraction, so E / (1 + v) / 100 per percent.
- **Crit**, where the Crit column says yes, in expected-value form: the heal
  without its crit is R / κ when the event crit and R when it did not; one more
  percent of crit chance adds that times (κ - 1) / 100. κ is 2 in this build;
  §8's probe reads it from the fixture.
- **Haste, tick form**, for an event the Haste-tick column marks: E / (1 + h)
  / 100 per percent. A hasted heal-over-time ticks proportionally faster, so its
  healing grows with 1 + h.
- **Haste, cast form**, for an event either haste column marks: the same
  formula. It assumes every bit of haste becomes proportionally more casting,
  with mana never short: an upper bound.
- **Haste percent buffs cancel.** Haste from rating and haste from a percent
  buff multiply, so the healing is proportional to (1 + h)(1 + b); one more
  percent of rating adds E / (1 + h) / 100 whatever b is. That is why h above is
  the rating's haste alone and the tracker values no haste buff.
- **The shipped haste weight is the tick form**; the cast form is written
  beside it in the entry's provenance. The distance between the two is the
  "haste split" memo §2b says the per-event method cannot decide alone.
- **Mastery (Harmony)**, where the Mastery column says yes and n > 0: the
  healing is proportional to 1 + P·c·T(n) with c = 1.311 / 100. One more mastery
  point adds E × c × T(n) / (1 + P·c·T(n)).
- **The stack table** (memo §2b, the diminishing stacks since 11.1):
  T(0) = 0, T(1) = 1, T(2) = 1.7, T(3) = 2.3, T(4) = 2.8, T(5) = 3.2,
  T(6) = 3.5, T(7) = 3.7, T(8) = 3.8, T(9) = 3.85, T(10) = 3.875, and 3.875
  beyond.
- **n** is rebuilt from the druid's own aura events on each target: an
  applied effect of the list adds one (per spell ID: a Rejuvenation and a
  Germination are two), a removed one subtracts, a refresh changes nothing. An
  effect already up when the log starts is unknown until its first event; the
  tool counts the events where a removal arrived for an effect it never saw
  applied.
- **Leech**: leech healing is proportional to the leech percent, so one more
  percent adds (the effective healing of her Leech events) / (her leech
  percent). Overheal counts here, inside E. A player with no leech rating gets
  no leech weight: the method does not predict one.
- **Share heals** take Intellect and versatility as their parent does, and no
  mastery. **Fixed heals** take only the columns the table gives them.

## 7. Fights, bands and the estimate

- **A segment** is one stretch of the key: each `ENCOUNTER_START` to its
  `ENCOUNTER_END` is a boss segment; the stretches between them (from
  `CHALLENGE_MODE_START`, and to `CHALLENGE_MODE_END`) are trash segments. A
  raid log's segments are its encounters. A segment in which none of the
  player's heals moved with Intellect (no heal without overheal) is dropped and
  counted - the fixture's last stretch, the 267 ms between the last boss's end
  and the key's, held two overhealed heals.
- **The band** of a key is its level from `CHALLENGE_MODE_START`, written as
  the weights file's Dungeon band (the key level as text, e.g. "12"); a raid
  encounter's band is the Raid band "all".
- **Per segment**, each stat's weight per rating point, relative to
  Intellect's: (the stat's gain per percent × the slope at her rating) /
  (Intellect's gain per point). Intellect is 1 by definition.
- **The band's estimate** of each stat is the trimmed mean of its segment
  weights: the segments sorted, the lowest and highest fifth (rounded down)
  dropped, the rest averaged.
- **The interval** is a bootstrap: segments drawn with replacement, as many as
  there are, the trimmed mean taken, 2,000 times from a fixed seed; the 2.5th
  and 97.5th percentiles. Two runs over the same log print the same numbers.
- **One key is one sample.** Segments of one key share one character, one
  gear set and one group; the interval they give is narrower than the spread
  between keys would be. The entry says how many logs, segments and events it
  rests on, and nothing claims more than that.

## 8. Two checks the fixture can answer

- **The crit multiplier.** For each critical tick of a heal-over-time effect,
  the ratio of its raw amount to the mean of the nearest uncritical ticks of the
  same effect on the same target, before and after it, when Harmony's count was
  the same at all three: the median of those ratios is κ as the file sees it.
- **Harmony's count and table.** For consecutive uncritical ticks of the same
  heal-over-time effect on the same target, with no Intellect reading between
  them that changed, the ratio of the later tick to the earlier, grouped by the
  change of n between them; the median of each group against
  (1 + P·c·T(later n)) / (1 + P·c·T(earlier n)). A count that is wrong, or a
  table that is wrong, shows as groups that miss.

## 9. The honesty rule and the output

- **Ranks.** Each stat's interval (per rating point, relative to Intellect,
  Intellect fixed at 1) is compared with those of the stats ranked next to it
  above and below by point estimate. A stat whose interval overlaps a
  neighbour's is written **unshipped**, with the reason naming the neighbour and
  both intervals. Leech with no rating is unshipped with that reason. An
  unshipped weight's number stays in the file for the developer engine and the
  comparison; it is a number the evidence cannot rank, and no promotion may
  ship it.
- **The entry** is E-4's schema version 2 Restoration entry (`role` HEALER,
  `primaryStat` int, the six stats, `method = "combat-log"`, `derivedAt`), with
  one Dungeon band per key level: weights per percent of each rating and per
  point of Intellect, scaled so that the value at the player's own stats is 100
  (`baseValue` makes up the rest: the healing no stat on the list moved);
  `unit = "per percent"`; each weight's interval; the per-rating-point weights
  relative to Intellect with their intervals; the haste cast form; the
  unshipped stats and their reasons; and the provenance - the logs (file name,
  sha256, zone, level, timed or not), the segments, the counted events, the
  overheal share, the stats she had, the untracked buffs and their share. No
  tier bonus is measured: the neutral set -1, as E-7's entries.
- **The file** says DEV ONLY in its header, is written outside the addon
  (`tools/combatlog/out/`, gitignored), and is never copied into the game by
  any tool.

## 10. Name stripping

- Before a log is committed, every player but the one named is replaced:
  each other player's GUID becomes `Player-0-` and an eight-digit number (in
  the order of the sorted original GUIDs), each of their names in quotes
  becomes `Player<number>-Realm` (or `Player<number>` for a bare name), every
  bare occurrence of a name of four or more letters inside another string too,
  and GUIDs that appear only bare (a pet's owner in the advanced block) get a
  number of their own. Nothing else changes: same lines, same timestamps,
  amounts, creatures and positions.
- The pass refuses to write its output if any original GUID or name of four or
  more letters is still in it.
- Run over a file it already stripped, it changes nothing.

## 11. Limits, said plainly

- The values describe the fights logged, by one player, with her gear, talents
  and group.
- The tracker misses rating procs whose size the client data does not give; the
  entry says how much healing happened while each was up.
- The cast-time haste form ignores mana; the tick form ignores that faster
  casting is also worth something. Neither is the whole truth.
- The overheal rule values nothing in an event that overhealed by one point.
- Harmony's list is our reading of a label. §8's probe is the evidence.
- Healing done by a share heal is credited to Intellect and versatility as if
  its parent's rules held; its parent's crit and mastery are not followed.
- Trinkets are never valued: procs reach the weights only through the tracker
  (memo §2b).

## 12. Adding a healer spec

E-5b (WKE-713) split this file's method from Restoration's own data: the code
in `tools/combatlog/lib/attribute.js` and `lib/entry.js` names no spell, buff
or spec. Everything above is Restoration's data, read through her module;
adding another healer spec is a new module beside hers, found through
`tools/combatlog/lib/specs/index.js`'s registry (`get(specID)`, `ids()`), not
a change to either file.

**The module's exported names.** One file,
`tools/combatlog/lib/specs/<specID>-<spec-slug>.js` (Restoration's is
`105-restoration-druid.js`), exporting exactly:

- `identity`: `{ specID, name, role, primaryStat, stats }` - the client's
  spec ID (`GetSpecializationInfo`), a word for generated text (the written
  weights file's header reads `<name> stat weights`), `role` ("HEALER"),
  `primaryStat` and the ranked `stats` list E-4's schema expects.
- `spellRow(id)`, `ROWS`, `UNKNOWN` - §5's table, as data, and the row a
  spell not in it counts as.
- `constants`: `critMultiplier`, plus whatever the spec's own mastery
  formula needs (Restoration's are `harmonyCoefficient` and `masteryBase`).
- `buffs`: `{ percent, unsized, hastePercent, amount, tracked(id) }` - §3's
  and §6's buff tables, and the one predicate that says whether an aura is
  any of them.
- `mastery`: `{ createTracker(player), gain(E, pct, tracker, dst, C) }`. The
  tracker `walk()` creates once per log exposes `onCombatantInfo(ci)`,
  `onAura(a, kind)`, `onUnitDied(guid)` and `diag()` (the three resync counts
  `lib/entry.js` writes per log under the key `harmony`, whatever the spec -
  a spec whose mastery needs no cross-event tracking still returns an empty
  `diag()`). `gain` is this heal's mastery gain, read against whatever
  per-target or per-player state the tracker followed; 0 when the spec's
  mastery predicts none for this event.

A spec whose mastery is not "a count of stacking auras on the target", the
way Harmony's is, still fits this shape - the tracker and `gain` are free to
use it differently - but if its per-event formula differs in kind from
Restoration's, `lib/attribute.js`'s call site
(`spec.mastery.gain(E, pct, tracker, dst, C)`) still has to be the only
place that formula is read from; no spec-specific code belongs there.

**Where its spell rows come from.** Every row in a real spec's `ROWS` is read
from SimulationCraft's `spell_query` output, never guessed or copied from a
wiki (§0's clean-room rule): `spell_query=spell.id=<id>` for each spell,
committed verbatim under `spec/fixtures/combatlog/` (Restoration's is
`simc-spells-70391.txt`), the same way §1 and §5 describe for her.

**Its first log.** Committed stripped, the way §10 describes for
Restoration's: every other player's name and GUID replaced
(`tools/combatlog/anonymise.js`), never the raw capture.

A toy spec (`tools/combatlog/test/fixtures/toy-spec.js`, WKE-713) proves this
shape without any of that: two spells and a mastery that multiplies every
heal by a constant, registered only inside `test/specs.test.js` through
`lib/specs/index.js`'s `register()`/`unregister()`. It is never added to the
shipped registry.

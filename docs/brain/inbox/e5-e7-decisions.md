# e5-e7-decisions: the combat-log promotion bar (E-5) and what a tank's weight measures (E-7), decided by the owner

## §0
**As of 2026-10-20, evening CDT, two of the owner's open decisions are made (docs-only PR on `main` bcc6933).**
- **E-5 decided:** Lootpath's own numbers for a HEALING spec show per spec and per content type (Mythic+, regular dungeons, raid; NOT the open world), once that content's own combat logs pass the rank rule on all logs and again with any one log left out. Each spec and content type unlocks independently; a content type without passing logs shows none of Lootpath's own numbers. The companion's QE Live numbers are unaffected.
- **E-7 decided:** a tank's stat weight measures DAMAGE (SimC's DPS scale factors) for every tank spec, said plainly on tank surfaces. Guardian's current survival-in-Raid entry changes to damage. Not yet built.
- **Next for Restoration Mythic+:** the owner logs one low and one high key (for example +6 and +15). The coordinator then runs the same stability test to settle whether one set covers every key level or each level band needs its own.

## §7
**2026-10-20, evening CDT - E-5: the promotion bar for combat-log (healer) weights (the owner, through four questions and two clarifications).**
- **Decided:**
  1. **Scope:** the bar is for healing specs only. Their weights come from combat logs because SimulationCraft models no healing. DPS and tank weights come from SimC runs the project makes itself, so they need no player logs. Their bar is NOT set by this entry.
  2. **Unit:** per spec and per content type: Mythic+, regular dungeons (normal / heroic / Mythic 0), raid. The owner: "I would argue we need to ensure the stats work in mythic+, regular dungeons, raids and just normal combat in the game". Then, offered the open world as a separate choice: "Yes, but drop open world".
  3. **Test:** every stat clears the rank rule (`unshipped` empty) on all of that content's logs, AND on every fit with any one log left out.
  4. **Independence:** each spec and content type unlocks on its own. Restoration Mythic+ does not wait for raid or for another spec. Asked "are we saying we won't approve the usage for a given class until we have all this data?" and "Would this mean we'd need data from every class and every spec within each class before they could use Lootpath?", the answer recorded was no: nobody waits for everybody.
  5. **Until a content type passes it shows none of Lootpath's own numbers.** For raid: "Nothing for raid yet (Recommended)".
  6. **One player suffices for now** ("Not for now (Recommended)"). Revisit before any public release.
  7. **QE Live stays out of the gate:** route C, 2026-10-15. The weekly compare remains a developer yardstick.
- **Key level:** asked "Should key level actually make a difference on how stats are checked and ranked?", the coordinator's answer was: possibly, unmeasured.
  - Effective healing excludes overheal, overheal is 50.2% of raw at +12, and incoming damage rises with level, so magnitudes could move. The close leech/haste pair could reorder.
  - The owner: "Yes, I'll log them": one low and one high key.
  - If the rank and the rank rule hold at both, one weight set covers all key levels. If not, each level band gets its own; schema v2 already bands by level.
- **Evidence behind the bar:** §9 2026-10-20 evening, "E-5's key-stability measurement" (the rank held in all 63 subsets; every 5-key fit cleared the rule). By that measure Restoration +12 Mythic+ passes today. Only the key-level check stands before Restoration Mythic+ unlocks.
- **Not decided:** the DPS/tank (SimC) promotion bar. Whether the weights file grows an open-world section is moot: no open world.

**2026-10-20, evening CDT - E-7: a tank's stat weight measures damage (the owner: "Damage (Recommended)").**
- **Decided:** every tank spec's weights are SimC's DPS scale factors. Tank surfaces say gear is ranked for damage. Guardian's entry, survival in Raid and damage in Dungeon as built on 2026-10-15, becomes damage in both. Survival may come later from tank combat logs (the route-C method) if a tank volunteers. Not built yet.
- **Why: the evidence**, gathered 2026-10-20 by a research agent and read by the coordinator. Pages read directly, unless marked:
  - **Raidbots** sims tanks for DPS only and calls survival metrics "generally unreliable" (support.raidbots.com/article/69, updated 22 Jan 2026).
  - **SimulationCraft's wiki** says it "does not fully support" tanks (SimcForTanks, edited 2021). Its TMI/DTPS metrics ignore external healing (StatsScaling, edited 7 Sep 2025, lists `scale_over` tmi/deaths/dmg_taken).
  - **Our own Guardian run** measured mastery's DTPS factor as noise (-0.083 +/- 0.188). SimC's DungeonSlice deals the tank no damage.
  - **Sim advice in current guides is damage-framed:** Method (all six tanks, 12.1.5, 13-14 Oct 2026) and Maxroll (12.1.5). Icy Veins (snippets only; its pages refused a direct read) says the same.
  - **No source publishes a survival-to-damage exchange rate,** so a blend would be an invented number.
  - **Guides do give separate defensive and damage priorities** for some specs: Prot Paladin and Guardian (Icy Veins, snippets) and Brewmaster (Icy Veins, reviewed 12 Oct 2026: defensive Crit > Vers > Mastery > Haste, damage Crit > Mastery > Vers > Haste). That is why the label on tank surfaces matters.
  - **murlok.io** (top 50 M+ per spec, Midnight S2, read 2026-10-20) shows top tanks Haste/Crit-heavy with Vers lowest on 5 of 6 specs. That is what they equip, not why.
- **Not decided:** the SimC promotion bar for DPS and tank weights.

## §11
- **Closed:** "What a combat-log weight must show before it may ship is the owner's (E-5, 2026-10-18)". See §7, 2026-10-20 evening.
- **Closed:** "Open for the owner (2026-10-15, E-7): what a tank's stat weight measures". Damage; see §7, 2026-10-20 evening.
- **Open:** the promotion bar for SimC-derived DPS and tank weights.
- **Open:** a player for each healing spec other than Restoration Druid. Each is one spec's logs, and none blocks another.

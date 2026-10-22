# Start here

The short way in. `docs/ARCHITECTURE.md` (the brain) is the full record, but at
over 2 MB it is never read whole: use this page to orient, then `grep` the
brain for what your work touches. Refreshed by the coordinating session when it
folds the brain inbox (`docs/brain/inbox/README.md`). Last refreshed
2026-10-21, from `main` 9c8dbcd (the sixth inbox fold).

## What Lootpath is

A World of Warcraft addon that puts QE Live's gear answers in the game, next to
the loot they are about, for healers. Three promises on one frame: **Equip Now**
(what to wear from what you own), the **Upgrade Map** (which boss drops a better
piece, and by how much), and the **Vault** (which Great Vault option to take).
Brain §1 has the full statement.

## Rules that bind every change

These are the ones a newcomer breaks. `CLAUDE.md` has the rest.

- **Lootpath never computes a healer value.** Every healing number a player
  sees is QE Live's export, transported unchanged. The one exception is the
  developer-only engine modules, behind `db.global.developer.engine`, on no
  player surface (§7, 2026-09-30, E-0; `docs/OWN-ENGINE.md`).
- Every client read is secret-guarded (`ns.Safe` / `ns.CopyRaw`). Nothing runs
  in combat, and there's no network and no backend.
- Never write a figure you didn't read from a tool. Every guard is proven
  red. Check the issue's premise against the code before you build.
- **The owner runs every in-game step.** Agents write the capture or the steps
  and book them as human-required.
- Agents open PRs and never merge them. The coordinating session merges when
  every check is green (§7, 2026-10-15 late morning).
- Brain updates go in your inbox file, `docs/brain/inbox/WKE-<n>.md`, never
  into `ARCHITECTURE.md` (§7, 2026-10-18 night).

## Where the lanes stand (per the brain's latest entries)

Tags name lanes. Grep the brain for a tag to get its whole history.

- **R-2x / R-3 (roads, tooltip, Upgrade Map, bag marks):** player-facing. The
  latest is **R-2s / R-3 (WKE-707), merged (PR #363) and synced**: every
  arrived-pick crest sentence reads `Crest to <level>`, and a held vault pick
  shows its own `+x% Upgrade` line unless it is worn at its crested level
  (option B, §7 2026-10-18 night). Verified in game on 2026-10-20: `Crest to 334` / `+0.54% Upgrade`. The
  tooltip's words are defined in `docs/ROADS-UX.md`.
- **E-x (the own engine):** developer-only, never on a player surface.
  - E-4 (WKE-708): the weights file schema v2, one shape per spec.
  - E-5 (WKE-711): Restoration weights from the owner's own combat log.
  - E-5b (WKE-713): each healer spec is one module under `tools/combatlog/lib/specs/`;
    a second spec is data plus its `spell_query` capture. Six keys logged so far.
  - E-5c (WKE-714): a test pins the six keys' Restoration weights, so a change
    that moves them fails CI (`tools/combatlog/test/committed-keys.test.js`).
  - E-5d (WKE-715) and C-tmp (WKE-718): the combat-log and companion tests delete
    the temp folders they create.
  - Week four (2026-10-20): the vector refit's first unseen week; rank exact for
    tier, armour and weapon, jewellery the one class off, no class passes the bar.
    E-5's key stability: the Restoration rank holds in all 63 key subsets (§9).
  - E-6 (WKE-712): the engine scores the current spec.
  - E-7 (WKE-710): SimulationCraft-run weights for DPS and tank specs; a tank's
    weight measures damage by default (the owner, 2026-10-20; WKE-720).
  - E-5's bar (the owner, 2026-10-20): a healing spec's own numbers show per spec
    and content type (Mythic+, dungeons, raid) once that content's logs clear the
    rank rule, also with any one log left out. Restoration +12 passes; one low and
    one high key decide the other key levels.
  - Route C (§7, 2026-10-15 early morning): shipped weights come from
    combat logs, never fitted to QE Live.
- **A-1 (WKE-709):** rate on arrival, behind the developer switch. The
  player-facing step waits on promotion (§11).
- **UX-5x:** item cards and the character-sheet background.
- **Scope:** every class and spec is in scope (§7, 2026-10-15 morning), with
  the tracks in parallel. Healer specs stay the only player-facing ones (H-1).
- **Stokowski:** armed issue by issue on the owner's word since 2026-10-18:
  WKE-707, 713, 714, 715, 718, 719 and 720, all merged; since 714 each cost
  $2.97-6.28, with one automatic review loop on 720 (audits in §9). Issues for it are written with the
  `stokowski-ticket` skill; arming one is still the owner's call.

Check `gh pr list` for what is actually open: a lane's "PR open" above may have
merged since.

## Open decisions that are the owner's

From §11. Grep it for the full text.

- The promotion bar for SimC-derived DPS and tank weights.
- A player for each healing spec other than Restoration Druid.
- Which issue Stokowski builds next (armed one at a time, on the owner's word).

## Finding things in the brain

| Section | What it holds | Size |
| --- | --- | --- |
| §0 | Dated "where we are" entries, newest first | 407 KB |
| §1–§5 | What Lootpath is, owner context, the ecosystem, QE Live, data flow | small |
| §6 | Architecture | 209 KB |
| §7 | Decisions, dated. Do not reopen one without a new entry. | 581 KB |
| §9 | Verification ladder: captures, screenshots, measurements | 375 KB |
| §10 / §11 / §12 | Issue map / risks and open questions / working rules | — / 259 KB / small |

- `grep -n "R-2s\|WKE-707" docs/ARCHITECTURE.md` finds every entry about an
  issue. Read the hits with a line range.
- `grep -n "^## " docs/ARCHITECTURE.md` gives the section line numbers.
- `grep -n "^\*\*2026-10-1" docs/ARCHITECTURE.md` gives the recent dated entries.

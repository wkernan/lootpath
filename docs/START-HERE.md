# Start here

The short way in. `docs/ARCHITECTURE.md` (the brain) is the full record, but at
over 2 MB it is never read whole: use this page to orient, then `grep` the
brain for what your work touches. Refreshed by the coordinating session when it
folds the brain inbox (`docs/brain/inbox/README.md`). Last refreshed
2026-10-19, from `main` 208c0f4 (the first inbox fold).

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
  (option B, §7 2026-10-18 night). The owner's in-game check is owed. The
  tooltip's words are defined in `docs/ROADS-UX.md`.
- **E-x (the own engine):** developer-only, never on a player surface.
  - E-4 (WKE-708): the weights file schema v2, one shape per spec.
  - E-5 (WKE-711): Restoration weights from the owner's own combat log.
  - E-6 (WKE-712): the engine scores the current spec.
  - E-7 (WKE-710): SimulationCraft-run weights for DPS and tank specs.
  - Route C (§7, 2026-10-15 early morning): shipped weights come from
    combat logs, never fitted to QE Live.
- **A-1 (WKE-709):** rate on arrival, behind the developer switch. The
  player-facing step waits on promotion (§11).
- **UX-5x:** item cards and the character-sheet background.
- **Scope:** every class and spec is in scope (§7, 2026-10-15 morning), with
  the tracks in parallel. Healer specs stay the only player-facing ones (H-1).
- **Stokowski:** held since 2026-10-15, except the one test issue, WKE-707
  (§7, 2026-10-18 evening), which merged. Its five problems found on that run
  were fixed the same day. Lifting the hold for more issues is the owner's
  call. Issues for it are written with the `stokowski-ticket` skill.

Check `gh pr list` for what is actually open: a lane's "PR open" above may have
merged since.

## Open decisions that are the owner's

From §11. Grep it for the full text.

- What a combat-log weight must show before it may ship (E-5).
- What a tank's stat weight measures: survival, damage or a blend (E-7).
- Whether to lift the Stokowski hold beyond WKE-707.

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

# Lootpath - working rules

**`docs/ARCHITECTURE.md` is the central brain, but at over 2 MB it is never
read whole and never edited by a work PR (decision 2026-10-18 night,
`docs/brain/inbox/brain-inbox.md`).**

- **Start with `docs/START-HERE.md`**: what Lootpath is, the rules that bind
  every change, where each lane stands, and how to find the rest.
- **Look things up in the brain by search.** `grep -n` for the issue's tag
  (`R-2s`, `E-5`), its `WKE-` number or the symbol, then read the hits by
  line range. §7 holds the decisions; do not reopen one without a new entry.
- **Record what you learned, discussed, decided, created or worked on in
  your own inbox file, `docs/brain/inbox/WKE-<n>.md`** (template in
  `docs/brain/inbox/README.md`): the §0 entry, the §7 decision, and any
  other section's change. A conversation that only settled a question still
  writes one, through a docs-only PR if nothing else is in flight. Two PRs
  never edit the same lines, so they never conflict.
- **The coordinating session folds the inbox in.** After merging, it moves
  each merged inbox file's entries into `ARCHITECTURE.md`, deletes the
  file, and refreshes `START-HERE.md`, in one docs-only PR per batch.

This file stays short; everything else lives in the brain.

**Lootpath never computes a healer value.** Every healing number on screen is
QE Live's `qe-live-droptimizer` v1 export, transported unchanged. Lootpath
scans, walks the journal, matches, and displays. If a gap tempts you to
estimate, stop. **One scoped exception, decided 2026-09-30 (ARCHITECTURE.md
§7, E-0; `docs/OWN-ENGINE.md`):** the developer-only engine modules
(`EngineStats`, `EngineScore`, `EngineCompare`, `EngineEffects`, `EngineSearch`,
`Data/EngineWeights.lua`, `Data/EngineEffects.lua`, and the developer panel
`UI/EngineDevPanel.lua` that shows them)
may compute a value BESIDE QE Live's, behind `db.global.developer.engine`,
on no player surface and never in a list with QE Live's numbers, to measure
parity. "Never in a list" means never sorted or combined with them: the
developer panel's separate `theirs` and `ours` columns, in stored order, are
allowed (the owner, 2026-10-11). The rule above still governs every surface a player sees.

## Before you start building: your own worktree

Several sessions work on this repo at the same time, one Linear issue each.
A branch alone is not enough: two branches checked out in one directory
still edit the same files on disk. **Every issue gets its own git worktree,
created before the first edit, even if the checkout looks idle:**

```powershell
cd C:\Code\lootpath
git fetch origin
git worktree add C:\Code\lootpath-<n> -b lp-<n>-<slug> origin/main
cd C:\Code\lootpath-<n>
.\tools\fetch-libs.ps1          # Lootpath/Libs is gitignored, so each worktree needs it
.\tools\fetch-annotations.ps1   # same for .luals (only if you will run the LuaLS gate)
```

Work, commit, push and open the PR from that directory. `tools\check.ps1`
and `tools\sync.ps1` work from any worktree; the Docker image is shared.
Never edit files under `C:\Code\lootpath` itself while another session may
be active there, and never `git add -A` in a directory you did not create.
After your PR merges: `git worktree remove C:\Code\lootpath-<n>` from the
main checkout, then `git worktree prune`. If you inherit a session that
already edited the shared checkout, move the work to a worktree first
(`git stash`, create the worktree, `git stash pop` there).

## How work moves

- Branch per issue (`lp-<n>-<slug>`) in its own worktree, PR to `main`,
  never commit to `main` directly. Agents open the PR and never merge it;
  the coordinating session merges, only when every CI check is green
  (ARCHITECTURE.md §7, 2026-10-15). Never bypass a check; never disable a
  test to get green.
- Read the whole Linear issue, including its "Working in this repo" section.
  Verify the issue's premise against the code before building. A wrong premise
  is reported in the PR and the right thing is built instead: scaling down is
  fine, widening is not.
- Commits end with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
  PR bodies end with the Claude Code attribution line and carry every section
  of `.github/pull_request_template.md`.
- **Rebase onto `origin/main` before opening the PR, and again before
  merging** (`git fetch origin`, `git rebase origin/main` in your worktree,
  resolve, re-run `tools\check.ps1`, `git push --force-with-lease`). `main`
  moves several times a day and several PRs land beside yours; a PR that
  conflicts with `main` gets no CI run at all. Zero checks means rebase, not
  broken CI.
- Every Linear issue an agent picks up carries both rules in its own text -
  the worktree and the rebase - under "Working in this repo". An issue
  without them is not ready; add them before handing it out. **Except an
  issue for Stokowski:** write it with the `stokowski-ticket` skill and leave
  the worktree recipe, the `.ps1` steps and status changes out; the section
  below covers them.

## If you are a Stokowski agent

You are one if your prompt came from Stokowski: a headless run on the Linux
orchestrator VM, in a workspace under `~/workspaces/lootpath/`. There, these
replace the Windows rules above (decision 2026-10-18, ARCHITECTURE.md §7):

- **The workspace is your worktree.** Stokowski cloned it for this issue
  alone. Do not create another, and ignore `C:\` paths.
- **Use Stokowski's branch**, the one your prompt names, not `lp-<n>-<slug>`.
  Linear links the PR to the issue by that name.
- **The gates run natively.** There is no PowerShell: run CI's own commands
  from the repo root instead of `tools\check.ps1`: `luacheck . --no-color`,
  `stylua --check .`, `bash tools/luals-check.sh`, `busted`, and
  `node --test`, but only in a `tools/` directory your change touches
  (`tools/companion`, `tools/engine`, `tools/simc`, `tools/combatlog`). A
  Lua-only change runs none of them: CI runs all four on every PR, and
  `tools/engine` alone takes over 2 minutes here. Run them one at a time,
  never in parallel. The LuaLS gate needs the annotations first, from CI's
  own clone step: `git clone --depth 1 --recurse-submodules
  --shallow-submodules https://github.com/Ketho/vscode-wow-api.git
  .luals/vscode-wow-api`.
  The full `busted` run takes about 2 minutes on this VM when nothing else is
  running (120 s measured 2026-10-18): run it once, in the foreground, and
  run only the covering specs while you work.
- **Never merge, and never change the Linear issue.** Stokowski moves its
  status and posts your `.stokowski/report.json` as the comment. A
  "set this issue In Progress" line in an older issue does not apply to you.
- **The rebase rule still applies.** Rebase onto `origin/main` before opening
  the PR. On a rework run, add commits rather than force-pushing.
- **Every other rule in this file applies unchanged:** the brain, evidence,
  guards proven red, client rules, attribution and the PR template.
- You cannot run anything in game, sync into the game, or touch the owner's
  machine. Book each in-game step as human-required.

## Evidence

- Never write a measured figure you did not read from a tool.
- Every guard is proven red: break it, watch it fail, restore it, say so.
- A return shape or restriction that Blizzard's exported API docs (Ketho's
  annotations under `.luals/`) or a committed fixture under `spec/fixtures/`
  cannot confirm is not guessed. Write the capture, hand it to the owner as a
  human-required step, build against the transcript. The Warcraft Wiki is
  stale after 10.1.7.
- The owner runs every in-game step. You cannot.

## Client rules

- Every value read from the client passes `ns.Safe` / `ns.CopyRaw`
  (`issecretvalue` / `issecrettable`). Nothing runs in combat. No network. No
  backend. Everything external arrives by paste, or by the one file the local
  companion writes into the addon folder (`Data/QEVerdict.lua`, decision
  2026-09-07, ARCHITECTURE.md §7); the addon still reads nothing but its own
  Lua at load. SavedVariables flush only on
  `/reload` or logout.
- Captures (`/lootpath capture <name>`) only read, with three recorded
  exceptions:
  `capture journal` sets the Adventure Guide's view state because the API has
  no other way to ask for loot, and restores what it can (ARCHITECTURE.md §7) -
  and since 2026-10-02 (E-0g, WKE-677, the owner's "merge") `capture linklevel`
  does the same through the same walk and the same restore, because a
  context-scaled journal link reads at a level the Guide's view may decide and
  the only way to learn which is to read it while the Guide previews the row;
  `capture vault` **and once at login** call `C_WeeklyRewards.OnUIInteract()`,
  read on every `WEEKLY_REWARDS_UPDATE` for a bounded few seconds - settling on
  the read that carries rewards - and then call `CloseInteraction()` - always,
  including when the bound ends it - because after the week's first progress
  the client stops carrying last week's unclaimed rewards until something
  interacts with the vault, and that pair is what Blizzard's own vault frame
  calls on every open and close (decision 2026-09-14, ARCHITECTURE.md §7). The
  login ask captures nothing and reloads nothing: it is the same one
  interaction moved off the refresh, because a refresh that waits for it can no
  longer reload - the client refuses a `ReloadUI` it cannot attribute to the
  player (M3-16a, 2026-09-15, ARCHITECTURE.md §7). **It never happens at the
  flush, and on RESET DAY it is not enough:** the week's new rewards are
  generated by the Great Vault window being opened, not by this interaction, so
  the tab asks the player to open it and the addon does not get a second
  exception to try (M3-16b, 2026-09-15, ARCHITECTURE.md §7). And
  `capture upgrade` puts each owned upgradeable item into the OPEN upgrade
  vendor's window (`SetItemUpgradeFromLocation`) to read its crest type and
  cost, because the client answers `GetItemUpgradeItemInfo()` only about the
  item in that window, and clears the window again after every item and once
  more at the end (decision 2026-09-14 evening, ARCHITECTURE.md §7) - nothing
  is bought, nothing is upgraded, nothing moves, and `UpgradeItem` is never
  called.
  Every function a capture calls is named in `Lootpath/Captures.lua` or
  `Lootpath/Modules/Journal.lua`; nothing acts on the character, its items or
  its money. Never call what a namespace walk finds.

## Tooling

- `.\tools\check.ps1` runs every CI gate locally (StyLua and LuaLS natively,
  luacheck and busted in Docker via `tools/docker/Dockerfile`).
- `.\tools\fetch-libs.ps1` and `.\tools\fetch-annotations.ps1` pull the
  gitignored Ace3 libraries and Ketho annotations.
- `.\tools\sync.ps1` copies the addon into the game; `-Pull` brings
  SavedVariables back to `spec/fixtures/captures/`.
- Licences: every dependency is recorded in `Lootpath/Libs/LICENSES.md` before
  it is vendored. QE Live's repo has no licence: read, never copy.

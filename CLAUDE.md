# Lootpath - working rules

**`docs/ARCHITECTURE.md` is the central brain. Read its §0 first in every
session, then the sections it points at. Before the session ends, update it
with anything learned, discussed, decided, created or worked on: §0 always,
plus the numbered section the change belongs to. A conversation that only
settled a question still updates §0, through a docs-only PR if nothing else
is in flight.** This file stays short; everything else lives there.

**Lootpath never computes a healer value.** Every healing number on screen is
QE Live's `qe-live-droptimizer` v1 export, transported unchanged. Lootpath
scans, walks the journal, matches, and displays. If a gap tempts you to
estimate, stop.

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
  never commit to `main` directly. Merge your own PR only when every CI
  check is green. Never bypass a check; never disable a test to get green.
- Read the whole Linear issue, including its "Working in this repo" section.
  Verify the issue's premise against the code before building. A wrong premise
  is reported in the PR and the right thing is built instead: scaling down is
  fine, widening is not.
- Commits end with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
  PR bodies end with the Claude Code attribution line and carry every section
  of `.github/pull_request_template.md`.
- A PR that conflicts with `main` gets no CI run at all. Zero checks means
  rebase, not broken CI.

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
  backend. Everything external arrives by paste. SavedVariables flush only on
  `/reload` or logout.
- Captures (`/lootpath capture <name>`) only read, with one recorded exception:
  `capture journal` sets the Adventure Guide's view state because the API has
  no other way to ask for loot, and restores what it can (ARCHITECTURE.md §7).
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

# Stokowski agents run a Node suite only where their change is

## §0
**As of 2026-10-19, small hours: Stokowski agents run `node --test` only in a `tools/` directory their change touches (docs-only PR; no addon file changed, nothing synced).**
Measured on WKE-707's second rework (Stokowski transcript, 2026-10-19 01:11-01:39 UTC): the change touched Lua and docs only, yet the agent ran all four Node suites because `CLAUDE.md`'s Stokowski section listed them as gates. `tools/engine` took 143 s, `tools/companion` 23 s (started 1 s apart, so they overlapped), `tools/combatlog` 12 s, `tools/simc` 1 s; CI ran the same four again on the PR. **Changed:** the Stokowski section now says to run `node --test` only in a `tools/` directory the change touches, one at a time; CI still runs all four on every PR.

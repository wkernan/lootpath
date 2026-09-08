# SimulationCraft addon strings from the owner's client (`/simc`, copied by hand)

Raw, unedited. Character name and realm are in them; that is fine for this
repo of the owner's own character (WKE-519's note). Each is named in the PR
that commits it.

- `hotornot-20260907.txt` - 2026-09-07 18:36 local, hotornot, Restoration,
  US/Arthas, SimC addon 12.1.0-03, client 12.1.0.69587; 6115 bytes; carries
  `talents=`, equipped gear, `### Gear from Bags` (line 57), no weekly-reward
  section (the vault had not generated rewards). Fixture for WKE-531 (fed to
  the fork headless) and WKE-532 (the profile built from SavedVariables is
  diffed against it).

## Built by Lootpath, not by the client

- `hotornot-from-savedvariables.simc` - WKE-532. Not a `/simc` string: the
  profile `tools/companion-spike/simc-profile.js` builds from
  `spec/fixtures/captures/Lootpath-20260906-200908.lua` (its newest `inventory`
  snapshot, 2026-09-05 13:33:25, bank closed). 5395 bytes, 148 lines, 15
  equipped and 35 bag items, no vault section. Committed so the spike's diff
  against `hotornot-20260907.txt` can be re-read without re-running anything;
  `simc-profile.test.js` fails if the builder and this file drift apart.

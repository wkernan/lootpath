# Companion fixtures

Text the companion really produced, kept verbatim so both halves of the addon
can be tested against the bytes rather than against a paraphrase.

- `playwright-go-disabled.txt` - C-14 (WKE-603). The `message` the companion
  wrote into `Data/CompanionStatus.lua` at 2026-09-16 21:27:27Z, copied out of
  the owner's own `Data/companion.log` with the log's stamp and its `FAILED: `
  prefix removed and nothing else changed: Playwright's whole `locator.click:
  Timeout 20000ms exceeded` error, seventeen lines of call log, with the real
  ANSI escape sequences (`ESC [ 2 m` / `ESC [ 22 m`) still in it - which the
  game's font draws as little boxes. This is what reached the status strip's
  tooltip and what the owner read as a blob the height of his screen. It is the
  input to the one-sentence guards in `tools/companion/test/status.test.js` and
  `spec/companion_spec.lua`.

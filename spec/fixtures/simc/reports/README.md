# SimulationCraft scale-factor reports (E-7, WKE-710)

Written by `tools/simc/run-scale-factors.js` on 2026-10-15 with SimulationCraft
`1210-01`, git `2358079` (game data 12.1.5.70391 Live, hotfix 2026-10-14), the
nightly archive `simc-1210.01.2358079-win64.7z` (sha256
`b0ec78d5cf533f34d599aba9493183d589e6cb411bfe6d2bbfb0f9fa811fb36f`, kept outside
the repo; `Lootpath/Libs/LICENSES.md`'s Data table). Every run:
`iterations=100000 target_error=0 threads=16 deterministic=1 seed=7101`
(`seed=7102` for `.seed7102`), `report_details=0`, `calculate_scale_factors=1`,
`scale_only=strength,agility,intellect,haste,crit,mastery,versatility`,
`scale_over=<metric>`. The input was SimC's own sample profile, by path: MID2
Feral, MID1 Balance, MID1 Guardian (the MID2 tier has no Balance or Guardian
profile in this build). The profiles are not here.

Per run, three files, named `<specID>-<fight>-<metric>[.<tag>]`:

- `.json` - SimC's JSON report (`json2=`), **unedited**.
- `.scale.txt` - the lines `lib/report.js` reads from SimC's text report
  (`output=`), **verbatim**: the `Player:` line, the metric lines, the `Scale
  Factors:` / `Weights :` pair. The scale factors' errors are only there (the
  JSON report carries none). The full text report is NOT committed: it prints
  the profile's action priority list, which is SimC's GPL-3.0 profile content.
  Its sha256 is in the run record, so a rerun can be checked against it.
- `.run.json` - the runner's own record of the run: SimC's arguments, the
  profile's path, tier and sha256, the full text report's sha256, `simc.exe`'s
  sha256.

`103-Patchwerk-dps.rerun` is the same run again (same seed): every factor agrees
to 3.1e-13 relative or better. `103-Patchwerk-dps.seed7102` is the same run with
another seed: every factor agrees within SimC's printed errors
(`tools/simc/test/determinism.test.js`). `104-DungeonSlice-dtps` is kept as the
evidence that SimC's DungeonSlice deals the Guardian no damage (DTPS 0 on every
iteration), so its text report has no `DTPS=` line and its factors are all 0.

| File | Bytes | sha256 |
|---|---|---|
| `102-DungeonSlice-dps.json` | 19298 | `d7d754e5024e27989d9c234b76f77c47f10f099242aeeccae2438194bdd5b2f8` |
| `102-DungeonSlice-dps.run.json` | 830 | `63d5d0e7602d785c78c3c12f81b7c60bb74127a38bff3d675ee693054521c666` |
| `102-DungeonSlice-dps.scale.txt` | 417 | `7d9b9ac7112dc4b2dbcdd9f8c6f498b5f1348240d96aa836d79e66adb0fca047` |
| `102-Patchwerk-dps.json` | 18042 | `9bb4fb816d87e9211181aa12fdd486ee51d094b471a84d993050899c28ce4f95` |
| `102-Patchwerk-dps.run.json` | 821 | `33b404199aa6092100a15e9af2ae2864e969c0d20e206387c3eb42466d8e5d52` |
| `102-Patchwerk-dps.scale.txt` | 420 | `35272b92a79959d37962cd7d542d62a88ef3a7f676488e892823ac40b1330eac` |
| `103-DungeonSlice-dps.json` | 19761 | `ae9d120a8b55e045d69470b4bc624cf62dd4e42f93d3a7ab8777cccab8099bf8` |
| `103-DungeonSlice-dps.run.json` | 828 | `cc170828ba4c762b9f212b6ca1d5d9f49c2111321ed34c7caf9388abecc806a9` |
| `103-DungeonSlice-dps.scale.txt` | 432 | `aa6bb1c69f9fbc20048942f53e1bfedf5006d0a520c8451edfffc65eda3a50cf` |
| `103-Patchwerk-dps.json` | 18772 | `029a447f234d55748929f89ee1061868c5982eb388c40c065fab43822f4c78ae` |
| `103-Patchwerk-dps.rerun.json` | 18784 | `b787c20b37f23b31aea1f40f90ddaeecd921f7792c3b28371d1fb035075876eb` |
| `103-Patchwerk-dps.rerun.run.json` | 831 | `eb68732c9e12325bbbd9577fa7d6c96625c5be83e8f4922b333ab3acf5608c49` |
| `103-Patchwerk-dps.rerun.scale.txt` | 431 | `442b7e8d7e47e0f4466d847a78e021e3bf19969cd1d0d68a7073b3a996f1d566` |
| `103-Patchwerk-dps.run.json` | 819 | `88961e88ff77a9b819b11b29e4fd4ce7b10c216de12100b218bcc4d02d806366` |
| `103-Patchwerk-dps.scale.txt` | 430 | `6400f6aa8701c20945849458d84b7323cfacac45c1dddca192700261b5537ca0` |
| `103-Patchwerk-dps.seed7102.json` | 18789 | `9a8b17cb117262fce45849de4ace22b62530ec0dd54de795717c8731828a7792` |
| `103-Patchwerk-dps.seed7102.run.json` | 837 | `365758143c88ee8944657533ea7ad08acf7a359fbd86c45abaabdcaedf34ae1b` |
| `103-Patchwerk-dps.seed7102.scale.txt` | 431 | `1c9299c07aa90744d47b5cb879bb4920ac8c7eaa3c1822653c93326a9aa08d77` |
| `104-DungeonSlice-dps.json` | 24145 | `91a6498f6a85843d7d85d215880d9ba2ef67ba4be57ca88078bcd951b8e01937` |
| `104-DungeonSlice-dps.run.json` | 831 | `249bbed3c60e968251811224fb16a69806b5d42e67b21e9d181f1774e67c30a5` |
| `104-DungeonSlice-dps.scale.txt` | 455 | `57962c48b24792a378d483bb3c89e499d367b83f6cd7a90a9ecd7baf71fc295f` |
| `104-DungeonSlice-dtps.json` | 24073 | `8a7c85548ef5629bccd6cf64463fefa215e915ba3eca3d06507d7929dbfe44da` |
| `104-DungeonSlice-dtps.run.json` | 834 | `db13d5bba4454284f9cbf764638f51b638c9bdc1fdffc836596c90a57c8de00e` |
| `104-DungeonSlice-dtps.scale.txt` | 282 | `6a3b1024e80c3590c1fd2a1b3ffbbef71fc6531f1680135e1b3130df3f06e0d4` |
| `104-Patchwerk-dps.json` | 32793 | `3c718ea6d30b24f0b08de058f1513fe3b1d7d0d1a6e4041c7ffa3a83fb2d4d5a` |
| `104-Patchwerk-dps.run.json` | 822 | `7b753c67bc723ae41120f0dc1a558a03112b9530dd98c58ada0fc5450c5e5321` |
| `104-Patchwerk-dps.scale.txt` | 644 | `93824377bf920132fedb12dcb587e90f45ae34efc228a169db4d5fa56993b90d` |
| `104-Patchwerk-dtps.json` | 32810 | `0020956feaf48ddf5d57460055a0e8c4620cf10f36653c502a519925d8297c4a` |
| `104-Patchwerk-dtps.run.json` | 825 | `7fe713bcfd68e38cdf6a60a9188d296841e6ec8dc262eb93ece2b5ec5ab4394a` |
| `104-Patchwerk-dtps.scale.txt` | 648 | `4c8d351a1a6fcd61d2defb0ad30365c1831d323e16c872284cff8192980360ca` |

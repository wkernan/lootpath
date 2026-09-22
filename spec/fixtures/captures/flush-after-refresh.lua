-- spec/fixtures/captures/flush-after-refresh.lua (C-16a, WKE-622)
--
-- NOT A PULL. Hand-written, like `empty-equipment-flush.lua` beside it and for
-- the same reason: the interesting thing is the SHAPE of a small `env` list, and
-- a real pull of the owner's file is 11 MB of gear the question does not need.
--
-- The shape is read, not invented. The owner's live SavedVariables
-- (`WTF\Account\<account>\SavedVariables\Lootpath.lua`) were parsed on
-- 2026-09-22 with `tools/companion/lib/lua-savedvariables.js`; its `env` list
-- held exactly four snapshots for Blueheeler-Arthas, a Restoration Shaman:
--
--   2026-09-21T17:39:15 trigger=refresh class=SHAMAN specInfo = 264 / "Restoration"
--   2026-09-21T17:39:16 trigger=flush   class=SHAMAN specInfo = 0 / no name
--   2026-09-21T17:40:19 trigger=flush   class=SHAMAN specInfo = 0 / no name
--   2026-09-21T17:42:49 trigger=flush   class=SHAMAN specInfo = 0 / no name
--
-- That is the whole of WKE-622 in four lines. `/lootpath refresh` ends in a
-- `/reload`, so the refresh's `env` is followed within a second by that
-- reload's flush `env`, and the NEWEST snapshot is a flush - which names no
-- spec, because `GetSpecializationInfo` answers id 0 and nothing else at
-- `PLAYER_LOGOUT`. The three flushes' real packs are `{ 0, [7]=0, [9]=0,
-- [10]=true, n=10 }` and are copied here field for field; the refresh's first
-- seven returns are copied too, the description string shortened, because only
-- the second one is read.
--
-- The gear halves are deliberately thin: this fixture is about the `env` list
-- and nothing else. One `inventory` snapshot with nothing in it is enough for
-- `buildProfile` to run, and it produces the same `0 equipped` counts
-- `empty-equipment-flush.lua` does.
LootpathDB = {
["global"] = {
["captures"] = {
["env"] = {
{
["name"] = "env",
["trigger"] = "refresh",
["capturedAt"] = 1790030355,
["capturedAtLocal"] = "2026-09-21T17:39:15",
["addonVersion"] = "dev",
["data"] = {
["player"] = { "Blueheeler", ["n"] = 1 },
["realm"] = { "Arthas", ["n"] = 1 },
["class"] = { "Shaman", "SHAMAN", 11, ["n"] = 3 },
["level"] = { 90, ["n"] = 1 },
["race"] = { "Orc", "Orc", 2, ["n"] = 3 },
["region"] = { "US", ["n"] = 1 },
["specIndex"] = { 3, ["n"] = 1 },
["specInfo"] = { 264, "Restoration", "A healer who calls upon ancestral spirits.", 136052, "HEALER", 4, 0, [9] = 0, [10] = true, ["n"] = 10 },
["build"] = { "12.1.0", "69875", "Sep 15 2026", 120100, ["n"] = 6 },
},
},
{
["name"] = "env",
["trigger"] = "flush",
["capturedOn"] = "flush",
["capturedAt"] = 1790030356,
["capturedAtLocal"] = "2026-09-21T17:39:16",
["addonVersion"] = "dev",
["data"] = {
["player"] = { "Blueheeler", ["n"] = 1 },
["realm"] = { "Arthas", ["n"] = 1 },
["class"] = { "Shaman", "SHAMAN", 11, ["n"] = 3 },
["level"] = { 90, ["n"] = 1 },
["race"] = { "Orc", "Orc", 2, ["n"] = 3 },
["region"] = { "US", ["n"] = 1 },
["specIndex"] = { 3, ["n"] = 1 },
["specInfo"] = { 0, [7] = 0, [9] = 0, [10] = true, ["n"] = 10 },
["build"] = { "12.1.0", "69875", "Sep 15 2026", 120100, ["n"] = 6 },
},
},
{
["name"] = "env",
["trigger"] = "flush",
["capturedOn"] = "flush",
["capturedAt"] = 1790030419,
["capturedAtLocal"] = "2026-09-21T17:40:19",
["addonVersion"] = "dev",
["data"] = {
["player"] = { "Blueheeler", ["n"] = 1 },
["realm"] = { "Arthas", ["n"] = 1 },
["class"] = { "Shaman", "SHAMAN", 11, ["n"] = 3 },
["level"] = { 90, ["n"] = 1 },
["race"] = { "Orc", "Orc", 2, ["n"] = 3 },
["region"] = { "US", ["n"] = 1 },
["specIndex"] = { 3, ["n"] = 1 },
["specInfo"] = { 0, [7] = 0, [9] = 0, [10] = true, ["n"] = 10 },
["build"] = { "12.1.0", "69875", "Sep 15 2026", 120100, ["n"] = 6 },
},
},
{
["name"] = "env",
["trigger"] = "flush",
["capturedOn"] = "flush",
["capturedAt"] = 1790030569,
["capturedAtLocal"] = "2026-09-21T17:42:49",
["addonVersion"] = "dev",
["data"] = {
["player"] = { "Blueheeler", ["n"] = 1 },
["realm"] = { "Arthas", ["n"] = 1 },
["class"] = { "Shaman", "SHAMAN", 11, ["n"] = 3 },
["level"] = { 90, ["n"] = 1 },
["race"] = { "Orc", "Orc", 2, ["n"] = 3 },
["region"] = { "US", ["n"] = 1 },
["specIndex"] = { 3, ["n"] = 1 },
["specInfo"] = { 0, [7] = 0, [9] = 0, [10] = true, ["n"] = 10 },
["build"] = { "12.1.0", "69875", "Sep 15 2026", 120100, ["n"] = 6 },
},
},
},
["inventory"] = {
{
["name"] = "inventory",
["trigger"] = "flush",
["capturedAt"] = 1790030569,
["capturedAtLocal"] = "2026-09-21T17:42:49",
["addonVersion"] = "dev",
["data"] = {
["equipped"] = {},
["bags"] = {},
["bank"] = { ["predicates"] = {} },
},
},
},
},
},
}

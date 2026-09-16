-- spec/fixtures/captures/empty-equipment-flush.lua (R-7b, WKE-591)
--
-- NOT A PULL. Every other file in this directory is the owner's own
-- SavedVariables copied back by `tools\sync.ps1 -Pull`; this one is written by
-- hand, to the shape of a flush that read nothing, because the write that
-- carried the real one was four snapshots deep and the flushes after it pushed
-- it off the end before it could be pulled.
--
-- The shape is read, not invented. The owner's live SavedVariables were parsed
-- on 2026-09-16 with `tools/companion/lib/lua-savedvariables.js` and carried the
-- flush of his 2026-09-15 22:11:52 logout - the same failure as the 19:19 one
-- the issue was filed over:
--
--   inventory[1] 2026-09-15T22:11:52 trigger=flush dur=0.58  equipped=0  bagRecords=20 totalNumSlots=0 bagItems=0
--   inventory[2] 2026-09-16T12:22:28 trigger=refresh dur=15.4 equipped=15 bagRecords=20 totalNumSlots=188 bagItems=161
--   env[1]       2026-09-15T22:11:52 trigger=flush capturedOn=flush level=90 class=Druid specInfo=(id 0, no name)
--
-- So: `trigger = "flush"` and `capturedOn = "flush"` present - which is what
-- refutes the issue's third premise, that the addon stopped writing the field -
-- a character the client still names (level 90, Druid), `specInfo` absent, and
-- an equipment read with nothing in it. Built through
-- `tools/companion/lib/profile.js` it produces `0 equipped, 0 in bags, 0 in the
-- bank, 0 vault, 14 lines`, which is the owner's 2026-09-15 22:07 terminal line
-- for line.
--
-- The bag half is left empty rather than modelled: the real one carried twenty
-- bag records all answering `numSlots 0`, and the profile counts 0 either way.
LootpathDB = {
["global"] = {
["captures"] = {
["env"] = {
{
["name"] = "env",
["trigger"] = "flush",
["capturedAt"] = 1789531177,
["capturedAtLocal"] = "2026-09-15T19:19:37",
["capturedOn"] = "flush",
["flushMs"] = 21,
["addonVersion"] = "dev",
["data"] = {
["player"] = { "Hotornot", nil, ["n"] = 1 },
["realm"] = { "Arthas", ["n"] = 1 },
["class"] = { "Druid", "DRUID", 11, ["n"] = 3 },
["level"] = { 90, ["n"] = 1 },
["race"] = { "Night Elf", "NightElf", 4, ["n"] = 3 },
["region"] = { "US", ["n"] = 1 },
["regionID"] = { 1, ["n"] = 1 },
["specIndex"] = { 4, ["n"] = 1 },
["specInfo"] = { ["absent"] = true },
["build"] = { "12.1.0", "69587", "Sep 10 2026", 120100, ["n"] = 6 },
},
},
},
["inventory"] = {
{
["name"] = "inventory",
["trigger"] = "flush",
["capturedAt"] = 1789531177,
["capturedAtLocal"] = "2026-09-15T19:19:37",
["durationMs"] = 1,
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

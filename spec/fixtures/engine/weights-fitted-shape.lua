-- spec/fixtures/engine/weights-fitted-shape.lua (E-0h, WKE-678)
-- SYNTHETIC. No figure here is a game value. A weights table in the SHAPE E-0e's
-- fit writes (tools/engine/lib/luaout.js buildTable, the shape of the owner's
-- 2026-10-01 `EngineWeights.dev.lua`): one band per fitted document, keyed by
-- the key level as a STRING - Dungeon `["2"]`, `["4"]`, `["6"]`, `["8"]`,
-- `["10"]` (the `--key-levels 1=2,2=4,4=6,6=8,7=10` mapping of
-- tools/engine/README.md) - and Raid `["raid-3"]`; specs keyed `[105]`;
-- `method`, `devOnly`, `fittedTo`, `superseded` as buildTable writes them.
--
-- Every band is weights-synthetic.lua's one band, except that its baseValue is
-- 1000 plus its key level (Dungeon) or 2000 (Raid), so which band scored a set
-- can be read off the value. `method` stays "synthetic": this is not a fit.
--
-- Loaded with dofile: it returns the table rather than setting a field.
local base = dofile("spec/fixtures/engine/weights-synthetic.lua")
local source = base.specs[105].Dungeon.bands["10+"]

local function copy(t)
    if type(t) ~= "table" then
        return t
    end
    local out = {}
    for k, v in pairs(t) do
        out[k] = copy(v)
    end
    return out
end

local function band(baseValue, fittedTo)
    local b = copy(source)
    b.baseValue = baseValue
    b.fittedTo = fittedTo
    b.r2 = 0
    b.mae = 0
    return b
end

local dungeon = {}
for _, level in ipairs({ 2, 4, 6, 8, 10 }) do
    dungeon[tostring(level)] = band(1000 + level, "synthetic-dungeon-" .. level)
end

return {
    schema = base.schema,
    version = base.version,
    method = "synthetic",
    devOnly = true,
    patch = base.patch,
    derivedAt = "never",
    fittedTo = {},
    superseded = {},
    specs = {
        [105] = {
            Dungeon = { bands = dungeon },
            Raid = { bands = { ["raid-3"] = band(2000, "synthetic-raid-3") } },
        },
    },
    dr = copy(base.dr),
    tiers = copy(base.tiers),
}

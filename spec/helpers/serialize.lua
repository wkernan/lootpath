-- spec/helpers/serialize.lua
-- Deterministic Lua serialisation (sorted keys) for golden fixtures under
-- spec/fixtures/expected/. Handles strings, numbers, booleans and tables.
local S = {}

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then
            return ta < tb
        end
        return a < b
    end)
    return keys
end

local function key(k)
    if type(k) == "number" then
        -- Not %q: Lua 5.1 coerces numbers to strings there, which would turn
        -- array indexes into string keys on reload.
        return "[" .. tostring(k) .. "]"
    end
    if type(k) == "string" and k:match("^[%a_][%w_]*$") then
        return k
    end
    return "[" .. string.format("%q", tostring(k)) .. "]"
end

function S.serialize(value, indent)
    indent = indent or ""
    local t = type(value)
    if t == "string" then
        return string.format("%q", value)
    elseif t == "number" or t == "boolean" then
        return tostring(value)
    elseif t == "table" then
        local inner = indent .. "    "
        local parts = {}
        for _, k in ipairs(sortedKeys(value)) do
            parts[#parts + 1] = inner .. key(k) .. " = " .. S.serialize(value[k], inner) .. ","
        end
        if #parts == 0 then
            return "{}"
        end
        return "{\n" .. table.concat(parts, "\n") .. "\n" .. indent .. "}"
    end
    error("cannot serialise a " .. t)
end

function S.write(path, value, header)
    local f = assert(io.open(path, "w"))
    f:write(header or "")
    f:write("return ", S.serialize(value), "\n")
    f:close()
end

return S

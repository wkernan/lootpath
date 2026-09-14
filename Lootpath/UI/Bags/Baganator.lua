-- Lootpath/UI/Bags/Baganator.lua (R-2, WKE-563)
-- The owner's own bag window, marked.
--
-- His screenshot of 2026-09-14 is the single-view "Hotornot's Bags" frame -
-- search bar, bag-icon row, Guild Vault section, currency footer - with Pawn's
-- green arrows drawn in it through Baganator's upgrade plugin. So the mark goes
-- in as a CORNER WIDGET, not as an upgrade plugin:
--
--   Baganator.API.RegisterCornerWidget(label, id, onUpdate, onInit,
--                                      defaultPosition, isFast)
--       Baganator/API/Main.lua:229 in the installed copy (read, never copied).
--       `onInit(itemButton)` returns the widget frame, which Baganator parents,
--       skins, hides and anchors itself; `onUpdate(widget, BGR)` answers true
--       to show it and false to hide it. `BGR.itemLink` is the slot's link.
--       Baganator/ItemViewCommon/ItemButton.lua:127-149 and 265-300 are where
--       both halves are called.
--
-- **Only one upgrade plugin is active at a time** (`ItemButton.lua:102-112`
-- reads one `upgrade_plugin` setting), so registering Lootpath's through
-- `RegisterUpgradePlugin` would displace Pawn's arrow in the owner's own bags.
-- He has not asked for that, and a mark that costs him another addon's mark is
-- not a mark he asked for. A corner widget sits beside Pawn's arrow instead.
--
-- `isFast` is true: the callback is `ns.Glow.Wants`, one table index over a map
-- built off the hover path, so it never needs Baganator's deferred queue.
--
-- **Nothing here knows what a road is.** It asks `ns.Glow.Wants` and draws a
-- texture.

local _, ns = ...

local Adapter = {
    name = "baganator",
    label = "drawn in Baganator's bag window, beside whatever else marks a slot",
}

-- Lootpath's OWN picture, never Blizzard's `UpgradeIcon` and never another
-- addon's.
--
-- **Why it is not an atlas any more (R-2b, WKE-575).** R-2 drew
-- `evergreen-weeklyrewards-reward-selected` - the Great Vault's own selection
-- glow, which is what the Vault tab puts on the picked cell (M5-4) - into this
-- 15-point frame with `SetAllPoints`, so that the bag and the Vault tab shared
-- one picture. The owner measured that atlas on his own client with
-- `C_Texture.GetAtlasInfo`, 2026-09-14: **214 x 121**. It is a wide,
-- soft-edged banner made to sit BEHIND a vault cell, and at 15 points it is
-- squeezed to a seventh of its width and an eighth of its height. That is what
-- his second night showed: the widget answered `glow yes` on the helmet, the
-- corner was `top_right`, and the slot had nothing in it. Two surfaces sharing
-- a picture was R-2's wish, not a rule, and a picture that cannot be seen
-- shares nothing. The Vault tab keeps its glow, at the size it was drawn for.
--
-- **No other atlas is guessed at in its place.** Every candidate would be a
-- name whose size, shape and alpha nobody here has read, and this file has now
-- cost the owner two nights of exactly that. A corner badge has to read at 15
-- points over any icon art, and the addon can draw one itself with no client
-- lookup at all: Blizzard's flat `WHITE8X8`, the same 1-pixel texture the
-- Vault tab's fallback border tints, in two layers -
--
--   * a near-black square filling the frame, which is the 1-point edge, so the
--     mark still has a shape over pale icon art;
--   * the accent square inset by 1 point inside it, fully opaque.
--
-- The accent is `ItemLine.TONE.better`'s hex, which is the one definition of
-- this addon's gold and is the tone the Vault tab's own pick is edged with, so
-- the two surfaces still mean the same thing in the same colour - only at a
-- size each of them can actually be seen at.
Adapter.TEXTURE = [[Interface\Buttons\WHITE8X8]]
Adapter.SIZE = 15
Adapter.EDGE_INSET = 1
Adapter.EDGE_COLOR = { 0.05, 0.05, 0.06, 1 }
Adapter.FILL_HEX = ns.UI.ItemLine.TONE.better.hex

-- WHICH corner, and why it is not the one R-2 chose (R-2a, WKE-571). Read off
-- the installed copy, which is the only place these two facts are written:
--
--   * `Core/Config.lua:46-49` - the corner defaults. `top_left` ships
--     `{"junk", "item_level"}`; `top_right` ships `{}`. So top-left is where
--     Baganator draws the item level, on a fresh profile and on the owner's.
--   * `ItemViewCommon/ItemButton.lua:174-177` - one corner's widgets are walked
--     in array order and the walk **breaks on the first one that returns true**.
--     Only one widget is ever shown per corner.
--
-- Together those two mean R-2's `{ corner = "top_left", priority = 1 }` was not
-- a mark beside the item level: `API/Main.lua:185-196` inserts at the priority
-- index, so Lootpath would have been FIRST in top-left and the item level would
-- have vanished from every slot the plan marks. A mark that costs the reader a
-- number he already had is not the mark he asked for - the same rule that kept
-- Lootpath out of Baganator's upgrade-plugin slot, applied to a corner.
--
-- `top_right` is empty by default, so the mark collides with nothing there, and
-- priority 1 in an empty array is simply first.
Adapter.CORNER = "top_right"
Adapter.PRIORITY = 1
Adapter.WIDGET_ID = "lootpath_glow"

function Adapter.Available()
    return type(Baganator) == "table"
        and type(Baganator.API) == "table"
        and type(Baganator.API.RegisterCornerWidget) == "function"
end

-- The widget, one per item button, made once and kept by Baganator. Two
-- textures, the edge under the fill; both are the flat 1-point texture with a
-- tint over it, so there is nothing here for a missing atlas to take away.
function Adapter.OnInit(itemButton)
    local widget = CreateFrame("Frame", nil, itemButton)
    widget:SetSize(Adapter.SIZE, Adapter.SIZE)

    local edge = widget:CreateTexture(nil, "OVERLAY")
    edge:SetAllPoints()
    edge:SetTexture(Adapter.TEXTURE)
    edge:SetVertexColor(unpack(Adapter.EDGE_COLOR))

    local inset = Adapter.EDGE_INSET
    local fill = widget:CreateTexture(nil, "OVERLAY", nil, 1)
    fill:SetPoint("TOPLEFT", widget, "TOPLEFT", inset, -inset)
    fill:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", -inset, inset)
    fill:SetTexture(Adapter.TEXTURE)
    fill:SetVertexColor(ns.UI.ItemLine.RGB(Adapter.FILL_HEX))

    widget.edge = edge
    widget.fill = fill
    return widget
end

-- ---------------------------------------------------------------------------
-- What the widget was asked, and what it said (R-2b, WKE-575).
--
-- The one number the owner's two nights could not produce. `/lootpath glow`
-- could say the widget was registered, which corner Baganator puts it in, and
-- what the map answers for one link - and still not say whether Baganator ever
-- CALLED the thing. Zero calls after the bags have been opened means the mark
-- was never asked for and no picture can fix it; a count with a `yes` in it
-- means the answer path ran and the eye is the only thing left.
--
-- Session-lived, on the adapter rather than in SavedVariables: it is a fact
-- about this login, and the sentence says so.
Adapter.calls = 0
Adapter.lastLink = nil
Adapter.lastAnswer = nil

function Adapter.ResetCalls()
    Adapter.calls = 0
    Adapter.lastLink = nil
    Adapter.lastAnswer = nil
end

-- Shown or not, for one slot. `BGR.itemLink` is Baganator's own field; every
-- value read from it passes `ns.Safe` on its way through `ns.Glow.WantsLink`,
-- and the copy kept for the diagnosis is `ns.Safe`'s, never the raw field.
--
-- The answer is forced to a plain boolean. Baganator's `ItemButton.lua:140`
-- branches on `show == nil` to QUEUE a slot rather than hide it, so anything
-- but `true` or `false` out of here would put the slot in a queue it does not
-- belong in; `ns.Glow.WantsLink` already answers a boolean, and `== true` is
-- what keeps that true of this callback whatever it grows into.
function Adapter.OnUpdate(_, cacheData)
    local link = type(cacheData) == "table" and cacheData.itemLink or nil
    local answer = ns.Glow.WantsLink(link) == true
    local safe = ns.Safe(link)
    Adapter.calls = Adapter.calls + 1
    Adapter.lastLink = type(safe) == "string" and safe ~= "" and safe or nil
    Adapter.lastAnswer = answer
    return answer
end

function Adapter.Install()
    if not Adapter.Available() then
        return false
    end
    local ok = pcall(
        Baganator.API.RegisterCornerWidget,
        "Lootpath",
        Adapter.WIDGET_ID,
        Adapter.OnUpdate,
        Adapter.OnInit,
        { corner = Adapter.CORNER, priority = Adapter.PRIORITY },
        true
    )
    return ok
end

-- Whether Baganator is actually drawing the widget, which is a different
-- question from whether it was registered and is the one nothing on screen
-- answered (R-2a, WKE-571: the owner saw no mark and no way to tell "never
-- installed" from "never shown" from "answered false").
--
-- `RegisterCornerWidget` only OFFERS a widget; what draws it is the widget's id
-- being in one of the four saved corner arrays. Registering with a
-- `defaultPosition` asks Baganator to put it there once - `API/Main.lua:185`
-- guards that with `icon_corners_auto_insert_applied`, per id, so a widget new
-- to a saved profile is inserted and a widget the player has since REMOVED
-- stays removed. Both of those are answered by Baganator's own two readers,
-- which are public API and are the only thing asked here.
function Adapter.Corner()
    if type(Baganator) ~= "table" or type(Baganator.API) ~= "table" then
        return nil
    end
    if type(Baganator.API.GetCurrentCornerForWidget) ~= "function" then
        return nil
    end
    local ok, corner = pcall(Baganator.API.GetCurrentCornerForWidget, Adapter.WIDGET_ID)
    return ok and corner or nil
end

-- The adapter's own lines for `/lootpath glow`: what Baganator says about the
-- widget, in Baganator's own words, never in a guess.
Adapter.NOT_IN_A_CORNER = "Baganator has the widget but no corner is drawing it."
    .. " Turn Lootpath on under Baganator's settings > Icon corners > Top right."

-- What the status strip adds when the widget is registered and no corner is
-- drawing it: the reader who went looking for a missing mark is exactly the
-- reader this sentence is for, and it names the settings page rather than
-- asking him to find it.
Adapter.STATUS_NOTE = "bag glow: turn Lootpath on under Baganator's settings > Icon corners > Top right"

function Adapter.StatusNote()
    if not Adapter.Available() or Adapter.Corner() then
        return nil
    end
    return Adapter.STATUS_NOTE
end

-- What the count comes to, in words. `NEVER_ASKED` is the whole finding when
-- it is zero and the bags have been opened: the mark was never asked for, so
-- nothing about the picture, the map or the lookup can be the cause.
Adapter.NEVER_ASKED = "Baganator asked the widget 0 times this session."
    .. " If the bags have been opened, Baganator never called it and the cause is upstream of the picture."
Adapter.CALLS_LINE = "Baganator asked the widget %d times this session, last answer: %s for %s"
Adapter.UNNAMED_ITEM = "an item it gave no link for"

-- The name inside a link, which is the only part of it a reader recognises.
-- Read off the link's own `|h[...]|h`, never from the client: this is a
-- diagnosis line, and a name that needed a load would be blank exactly when
-- the reader most wants it.
function Adapter.LinkName(link)
    if type(link) ~= "string" then
        return nil
    end
    local name = link:match("|h%[(.-)%]|h")
    if name and name ~= "" then
        return name
    end
    local parsed = ns.ParseItemLink(link)
    return parsed and parsed.key and string.format("item %s", parsed.key) or nil
end

function Adapter.CallsText()
    if Adapter.calls <= 0 then
        return Adapter.NEVER_ASKED
    end
    return string.format(
        Adapter.CALLS_LINE,
        Adapter.calls,
        Adapter.lastAnswer and "yes" or "no",
        Adapter.LinkName(Adapter.lastLink) or Adapter.UNNAMED_ITEM
    )
end

function Adapter.DiagnosisLines()
    local lines = {}
    if not Adapter.Available() then
        lines[#lines + 1] = "Baganator: not loaded, or its corner-widget API is not there."
        return lines
    end
    local corner = Adapter.Corner()
    if corner then
        lines[#lines + 1] = string.format("Baganator draws the widget in its %s corner.", corner:gsub("_", " "))
    else
        lines[#lines + 1] = Adapter.NOT_IN_A_CORNER
    end
    lines[#lines + 1] = Adapter.CallsText()
    return lines
end

-- A rebuilt map has to reach a bag that is already open. Baganator's own
-- refresh call is what does it; there is no Lootpath frame to touch.
function Adapter.Refresh()
    if type(Baganator) ~= "table" or type(Baganator.API) ~= "table" then
        return false
    end
    if type(Baganator.API.RequestItemButtonsRefresh) ~= "function" then
        return false
    end
    return pcall(Baganator.API.RequestItemButtonsRefresh) == true
end

ns.UI.Bags.Register(Adapter)
ns.UI.Bags.Baganator = Adapter

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
-- UX-4b (WKE-611) keeps every word of that and changes only what the two layers
-- are made of. The flat square is now the **Waymark** - the double chevron a
-- walked route is blazed with, candidate A of the WKE-602 proposal, picked by
-- the owner on 2026-09-16 - drawn from `Media/mark16.tga`, which is the mark's
-- REDUCED form redrawn on a 16-unit grid rather than a 64-point drawing shrunk.
-- That is R-2b's own rule applied to art instead of to an atlas, and it is why
-- `SIZE` is 16 rather than 15: at 16 the texture's texels and the frame's points
-- are one to one, and a mark drawn at 15/16 of itself is a mark nobody drew.
--
-- **UX-4c (WKE-612): one chevron became two, and the shadow became a keyline.**
-- The owner opened his full bags on 2026-09-17: "I like it, but the colour
-- makes it a bit hard to see when looking at your entire bags." He named the
-- COLOUR; the sign-off page put the two causes to him and argued hue is the
-- smaller one, because a thin shape with an offset shadow has no ground to sit
-- on whatever colour it is. He then picked Fix E at 16 - the FULL double
-- chevron, the upper solid and the lower at 65%, with a one-unit near-black
-- outline around every edge and NO plate behind it - which changes the shape
-- and the keyline and left the colour alone. So the bag corner, the launcher badge, the
-- compartment entry and the listing tile are now one shape, and the item's own
-- art stays visible under the mark.
--
-- **UX-4d (WKE-613): thicker, one colour, brighter.** He saw that in his full
-- bags the same day - "let's increase the thickness of both chevrons by a bit
-- more and let's also keep them the same color. It still seems difficult to see
-- them, I would say we need to go brighter on the pink" - and picked rung 5 of
-- the brand page's five, `#FFB3DB`. Nothing in this file changes for it: each
-- band is a unit thicker and the lower body is at full alpha inside the two
-- textures, and the colour is `ns.UI.BRAND_HEX` as it always was. `SIZE` is
-- still 16, the anchor is still R-2b's, and there is still no plate.
--
-- The two layers are still edge under fill, and what changed is what each is
-- made of and where it sits. They are two FILES now - `mark16-edge` is the
-- outline silhouette of both chevrons, `mark16-fill` the two bodies - because
-- one texture cannot carry two tints and the brand colour has to stay a Lua
-- string. And they are drawn at the SAME anchor with NO offset: the dilation
-- baked into the edge file is the keyline, all the way round both chevrons.
-- `EDGE_INSET` is gone with the offset it described. Insetting the fill was the
-- old mark's way of showing a rim, and it worked by drawing the fill smaller
-- than the shape it was meant to fill - which is why the rim was a shadow on
-- one side rather than an outline on every edge.
--
-- **The accent is no longer QE Live's gold, and that is the point.** The owner
-- asked for a colour of Lootpath's own (WKE-602, answer 2), so the fill is
-- `ns.UI.BRAND_HEX`. R-2b paired this mark's colour with the Vault tab's pick
-- edge so the two surfaces meant one thing in one colour; what UX-4b separates
-- is the two MEANINGS, which were never the same. The Vault tab's gold edge and
-- every number on screen go on saying "better", which is QE Live's word about an
-- item. The mark in a bag corner says "this is Lootpath" - and a third gold
-- thing in a corner that already holds Baganator's green arrow was the crowd the
-- proposal named.
Adapter.EDGE_TEXTURE = ns.UI.MEDIA.MARK16_EDGE
Adapter.FILL_TEXTURE = ns.UI.MEDIA.MARK16_FILL
Adapter.SIZE = 16
Adapter.EDGE_COLOR = { 0.05, 0.05, 0.06, 1 }
Adapter.FILL_HEX = ns.UI.BRAND_HEX

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
-- textures, the edge under the fill, both filling the frame - the addon's own
-- files with a tint over each, so there is nothing here for a missing atlas to
-- take away.
function Adapter.OnInit(itemButton)
    local widget = CreateFrame("Frame", nil, itemButton)
    widget:SetSize(Adapter.SIZE, Adapter.SIZE)

    local edge = widget:CreateTexture(nil, "OVERLAY")
    edge:SetAllPoints()
    edge:SetTexture(Adapter.EDGE_TEXTURE)
    edge:SetVertexColor(unpack(Adapter.EDGE_COLOR))

    -- The same anchor, not an inset one: the two files are the same drawing, so
    -- the keyline only lands on the chevrons' edges if the two are registered
    -- texel for texel.
    local fill = widget:CreateTexture(nil, "OVERLAY", nil, 1)
    fill:SetAllPoints()
    fill:SetTexture(Adapter.FILL_TEXTURE)
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

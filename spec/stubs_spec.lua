-- spec/stubs_spec.lua (T-1, WKE-560)
-- The stub's own contract: every widget it models carries THAT widget's mixin
-- chain and nothing more.
--
-- This file exists because of 2026-09-10. The Upgrade Map tab errored on open
-- in the owner's client - `UpgradeMapPanel.lua:1865: attempt to call a nil
-- value` - with 761 tests green, because the difficulty control was a
-- `WowStyle1FilterDropdownTemplate` and the stub gave every DropdownButton
-- `SetDefaultText`, which only `WowStyle1DropdownTemplate`'s mixin has. A
-- superset is a test that cannot go red, so every removal the T-1 audit made is
-- locked here: the method is asserted ABSENT on the kind or template that does
-- not have it, and asserted PRESENT on the one that does.
--
-- Everything asserted below was read under
-- `.luals/vscode-wow-api/` (Ketho's annotations, MIT) at the file and line
-- named beside it, never remembered and never taken from the wiki.
local Stub = require("spec.stubs.wow")

-- Every method name here is `nil` on the widget it is listed against, and the
-- comment says whose it really is.
local NOT_A_FRAME = {
    -- FontString's (Core/Widget/Font/FontString.lua): SetText :222, GetText
    -- :119, SetTextColor :229, SetWordWrap :245, SetNonSpaceWrap :194, and the
    -- font-instance setters. A Frame has none of them.
    "SetText",
    "GetText",
    "SetTextColor",
    "SetWordWrap",
    "SetNonSpaceWrap",
    "SetJustifyH",
    "SetJustifyV",
    "SetFont",
    "SetFontObject",
    -- TextureBase's (Core/Widget/Base/TextureBase.lua, Texture/Texture.lua).
    "SetTexture",
    "GetTexture",
    "SetAtlas",
    "GetAtlas",
    "SetTexCoord",
    "SetMask",
    "GetMask",
    "GetDrawLayer",
    -- ScrollFrame's (Core/Widget/Frame/ScrollFrame.lua).
    "SetScrollChild",
    "GetScrollChild",
    "SetVerticalScroll",
    "GetVerticalScrollRange",
    "UpdateScrollChildRect",
}

local TEXTURE_ONLY =
    { "SetTexture", "GetTexture", "SetAtlas", "GetAtlas", "SetTexCoord", "SetMask", "GetMask", "GetDrawLayer" }
local FONTSTRING_ONLY = {
    "SetText",
    "GetText",
    "SetTextColor",
    "SetWordWrap",
    "SetNonSpaceWrap",
    "SetJustifyH",
    "SetJustifyV",
    "SetFont",
    "SetFontObject",
}
local SCROLLFRAME_ONLY = {
    "SetScrollChild",
    "GetScrollChild",
    "SetVerticalScroll",
    "GetVerticalScrollRange",
    "UpdateScrollChildRect",
}
-- DropdownSelectionTextMixin's, which only some dropdown templates mix in
-- (Blizzard_Menu/MenuTemplates.lua:578 GetDefaultText, :582 SetDefaultText).
local SELECTION_TEXT = { "SetDefaultText", "GetDefaultText" }

local function assertAbsent(widget, names, why)
    for _, name in ipairs(names) do
        assert.is_nil(widget[name], why .. " must not have " .. name)
    end
end

local function assertPresent(widget, names, why)
    for _, name in ipairs(names) do
        assert.is_function(widget[name], why .. " must have " .. name)
    end
end

describe("the headless stub's widget surface", function()
    before_each(function()
        Stub.install()
    end)

    after_each(function()
        Stub.uninstall()
    end)

    -- ---------------------------------------------------------------------
    -- Kinds
    -- ---------------------------------------------------------------------

    it("gives a bare Frame no text, no texture and no scroll setters", function()
        local frame = CreateFrame("Frame", nil, UIParent)
        assertAbsent(frame, NOT_A_FRAME, "a Frame")
        -- What a Frame DOES have (Core/Widget/Frame/Frame.lua:3 `Frame : Region,
        -- ScriptObject`), so the absences above are a narrowing and not a gutting.
        assertPresent(frame, {
            "SetPoint",
            "SetSize",
            "Show",
            "Hide",
            "SetShown",
            "IsShown",
            "SetAlpha",
            "GetAlpha",
            "SetVertexColor",
            "SetScript",
            "CreateFontString",
            "CreateTexture",
            "SetID",
            "GetID",
        }, "a Frame")
    end)

    it("gives a FontString its text setters and none of a Texture's", function()
        local fs = CreateFrame("Frame", nil, UIParent):CreateFontString()
        assertPresent(fs, FONTSTRING_ONLY, "a FontString")
        assertAbsent(fs, TEXTURE_ONLY, "a FontString")
        -- SetVertexColor and SetAlpha are Region's (Base/Region.lua:75, :71), so
        -- a FontString has them as much as a Texture does.
        assertPresent(fs, { "SetAlpha", "SetVertexColor" }, "a FontString")
    end)

    it("gives a Texture its texture setters and none of a FontString's", function()
        local tex = CreateFrame("Frame", nil, UIParent):CreateTexture()
        assertPresent(tex, TEXTURE_ONLY, "a Texture")
        assertAbsent(tex, FONTSTRING_ONLY, "a Texture")
    end)

    it("gives the scroll setters to a ScrollFrame and to nothing else", function()
        assertPresent(CreateFrame("ScrollFrame", nil, UIParent), SCROLLFRAME_ONLY, "a ScrollFrame")
        assertAbsent(CreateFrame("Frame", nil, UIParent), SCROLLFRAME_ONLY, "a Frame")
        assertAbsent(CreateFrame("Button", nil, UIParent), SCROLLFRAME_ONLY, "a Button")
        assertAbsent(CreateFrame("EditBox", nil, UIParent), SCROLLFRAME_ONLY, "an EditBox")
        -- The 11.0 box is a Frame with a scroll TARGET, not a scroll child
        -- (ScrollTemplates.xml:4, ScrollBox.lua:94 GetScrollTarget).
        local box = CreateFrame("Frame", nil, UIParent, "WowScrollBoxList")
        assertAbsent(box, SCROLLFRAME_ONLY, "a WowScrollBoxList")
        assert.is_function(box.GetScrollTarget)
    end)

    it("gives an EditBox the four font setters it has and not the fifth", function()
        local box = CreateFrame("EditBox", nil, UIParent)
        -- Frame/EditBox.lua:262 SetFont, :266 SetFontObject, :285 SetJustifyH,
        -- :289 SetJustifyV, :347 SetText, :354 SetTextColor.
        assertPresent(box, {
            "SetFont",
            "SetFontObject",
            "SetJustifyH",
            "SetJustifyV",
            "SetText",
            "GetText",
            "SetTextColor",
        }, "an EditBox")
        -- SetWordWrap and SetNonSpaceWrap are FontString's alone
        -- (FontString.lua:245, :194).
        assertAbsent(box, { "SetWordWrap", "SetNonSpaceWrap" }, "an EditBox")
        assertAbsent(box, TEXTURE_ONLY, "an EditBox")
    end)

    it("gives a Button its own surface and no stub helper in a Blizzard slot", function()
        local button = CreateFrame("Button", nil, UIParent)
        -- Frame/Button/Button.lua:47 Click, :102 GetText, :199 SetText, :143
        -- SetEnabled, :114 IsEnabled, :69 GetFontString.
        assertPresent(button, {
            "Click",
            "SetText",
            "GetText",
            "SetEnabled",
            "Enable",
            "Disable",
            "IsEnabled",
            "GetFontString",
            "RegisterForClicks",
        }, "a Button")
        -- The client has no Button:Enter and no Button:Leave; firing a script
        -- by hand is the stub's own affair and lives on the shelf.
        assertAbsent(button, { "Enter", "Leave" }, "a Button")
        assert.is_function(button.stub.Enter)
        assert.is_function(button.stub.Leave)
    end)

    it("fires OnEnter and OnLeave from the shelf", function()
        local button = CreateFrame("Button", nil, UIParent)
        local seen = {}
        button:SetScript("OnEnter", function(self)
            seen[#seen + 1] = { "enter", self }
        end)
        button:SetScript("OnLeave", function(self)
            seen[#seen + 1] = { "leave", self }
        end)
        button.stub:Enter()
        button.stub:Leave()
        assert.equal(2, #seen)
        assert.equal("enter", seen[1][1])
        assert.equal(button, seen[1][2])
        assert.equal("leave", seen[2][1])
        assert.equal(button, seen[2][2])
    end)

    -- ---------------------------------------------------------------------
    -- The dropdowns: the 2026-09-10 crash, locked
    -- ---------------------------------------------------------------------

    it("gives no DropdownButton the caption methods until a template mixes them in", function()
        -- The intrinsic is DropdownButtonMixin + Button
        -- (Core/Widget/Intrinsic/DropdownButton.lua:9). DropdownButtonMixin
        -- declares no SetDefaultText: that is DropdownSelectionTextMixin's.
        -- Before T-1 the stub handed the pair to every DropdownButton and took
        -- them back inside attachTemplate, so a dropdown with NO template - one
        -- that never reached the subtraction - answered them headlessly.
        local bare = CreateFrame("DropdownButton", nil, UIParent)
        assertAbsent(bare, SELECTION_TEXT, "a DropdownButton with no template")
        -- The menu surface IS the intrinsic's, so it comes with the kind
        -- (DropdownButton.lua:237 SetupMenu, :255 GenerateMenu, :275 IsMenuOpen).
        assertPresent(bare, { "SetupMenu", "GenerateMenu", "IsMenuOpen" }, "a DropdownButton")
    end)

    it("gives WowStyle1DropdownTemplate the caption and the filter dropdown none", function()
        -- MenuTemplates.xml:3 `mixin="WowStyle1DropdownMixin"` and
        -- MenuTemplates.lua:753 `CreateFromMixins(ButtonStateBehaviorMixin,
        -- DropdownSelectionTextMixin)`.
        local selection = CreateFrame("DropdownButton", nil, UIParent, "WowStyle1DropdownTemplate")
        assertPresent(selection, SELECTION_TEXT, "WowStyle1DropdownTemplate")
        selection:SetDefaultText("All difficulties")
        assert.equal("All difficulties", selection:GetDefaultText())
        -- MenuTemplates.xml:66 and MenuTemplates.lua:776: the filter dropdown's
        -- mixin is ButtonStateBehaviorMixin + DropdownTextMixin +
        -- WowFilterButtonMixin, with no selection text anywhere in it. This is
        -- the exact shape that errored in the owner's client.
        local filter = CreateFrame("DropdownButton", nil, UIParent, "WowStyle1FilterDropdownTemplate")
        assertAbsent(filter, SELECTION_TEXT, "WowStyle1FilterDropdownTemplate")
        -- DropdownTextMixin:SetText (MenuTemplates.lua:522) and Button:SetText
        -- (Button.lua:199) are both real, so both dropdowns take one.
        assertPresent(filter, { "SetText", "SetupMenu" }, "WowStyle1FilterDropdownTemplate")
    end)

    it("keeps the test's way of picking a menu row off the dropdown itself", function()
        -- DropdownButtonMixin:Pick takes a menu DESCRIPTION and an input
        -- context (DropdownButton.lua:341), not an index, and the client has no
        -- SelectedIndex and no SelectByText at all. All three are the stub's.
        local dropdown = CreateFrame("DropdownButton", nil, UIParent, "WowStyle1DropdownTemplate")
        assertAbsent(dropdown, { "Pick", "SelectedIndex", "SelectByText" }, "a dropdown")

        local chosen
        dropdown:SetupMenu(function(_, root)
            root:SetTag("MENU_TEST")
            for _, label in ipairs({ "one", "two" }) do
                root:CreateRadio(label, function(data)
                    return chosen == data
                end, function(data)
                    chosen = data
                end, label)
            end
        end)
        assert.equal(2, #dropdown.menuElements)
        assert.equal("MENU_TEST", dropdown.menuTag)
        assert.is_nil(dropdown.stub:SelectedIndex())
        assert.is_true(dropdown.stub:Pick(2))
        assert.equal("two", chosen)
        assert.equal(2, dropdown.stub:SelectedIndex())
        assert.is_true(dropdown.stub:SelectByText("one"))
        assert.equal("one", chosen)
        assert.is_false(dropdown.stub:SelectByText("three"))
        assert.is_false(dropdown.stub:Pick(9))
    end)

    -- ---------------------------------------------------------------------
    -- The scroll box
    -- ---------------------------------------------------------------------

    it("keeps the frame pool off the scroll box", function()
        -- Acquiring and releasing are the VIEW's and the frame factory's
        -- (ScrollBoxListView.lua:335 AcquireInternal, :131
        -- `self.frameFactory:ReleaseAll()`); a ScrollBox answers neither.
        local box = CreateFrame("Frame", nil, UIParent, "WowScrollBoxList")
        assertAbsent(box, { "Acquire", "ReleaseAll" }, "a WowScrollBoxList")
        assert.is_function(box.stub.Acquire)
        assert.is_function(box.stub.ReleaseAll)
        -- What it DOES answer (ScrollBox.lua:86 GetView, :94 GetScrollTarget,
        -- :332 GetFrames, :662 GetDataProvider, :699 SetDataProvider, :712
        -- GetDataProviderSize, :674 FlushDataProvider, :284 ScrollToBegin).
        assertPresent(box, {
            "Init",
            "GetView",
            "GetScrollTarget",
            "GetFrames",
            "GetDataProvider",
            "GetDataProviderSize",
            "SetDataProvider",
            "FlushDataProvider",
            "ScrollToBegin",
        }, "a WowScrollBoxList")
    end)

    it("takes GetElementData off a row the moment the row goes back in the pool", function()
        -- ScrollBoxListView.lua:90 sets the reader on acquire and :114 clears
        -- it on release, so a pooled frame cannot still answer for its old row.
        local box = CreateFrame("Frame", nil, UIParent, "WowScrollBoxList")
        box:SetSize(100, 100)
        local view = CreateScrollBoxListLinearView()
        view:SetElementExtent(20)
        view:SetElementInitializer("Frame", function(frame, elementData)
            frame.seen = elementData
        end)
        box:Init(view)
        box:SetDataProvider(CreateDataProvider({ { id = 1 }, { id = 2 } }))
        local first = box:GetFrames()[1]
        assert.is_function(first.GetElementData)
        assert.equal(1, first:GetElementData().id)
        box.stub:ReleaseAll()
        assert.is_nil(first.GetElementData)
    end)

    -- ---------------------------------------------------------------------
    -- The panel templates, member by member
    -- ---------------------------------------------------------------------

    it("builds BasicFrameTemplate's title and close button and nothing else", function()
        -- BaseBasicFrameTemplate carries TitleText (UIPanelTemplates.xml:569)
        -- and CloseButton (:607); BasicFrameTemplate (:611) and
        -- BasicFrameTemplateWithInset (:638) add textures only, which a
        -- headless test has no pixels for.
        local frame = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
        assert.equal("FontString", frame.TitleText:GetObjectType())
        assert.equal("Button", frame.CloseButton:GetObjectType())
        assert.is_nil(frame.PortraitContainer)
        assert.is_nil(frame.EditBox)
    end)

    it("builds PortraitFrameTemplate's containers, and no close button on the NoCloseButton one", function()
        -- SharedUIPanelTemplates.xml:544 PortraitFrameBaseTemplate, which is
        -- where NineSlice (:550), PortraitContainer and its `portrait` texture
        -- (:551, :558) and TitleContainer with TitleText (:576, :583) come
        -- from; :629 PortraitFrameTemplateNoCloseButton adds nothing and :631
        -- PortraitFrameTemplate adds the CloseButton.
        local frame = CreateFrame("Frame", nil, UIParent, "PortraitFrameTemplate")
        assert.equal("FontString", frame.TitleText:GetObjectType())
        assert.equal(frame.TitleContainer.TitleText, frame.TitleText)
        assert.equal("Texture", frame.PortraitContainer.portrait:GetObjectType())
        assert.is_not_nil(frame.NineSlice)
        assert.is_not_nil(frame.CloseButton)

        local plain = CreateFrame("Frame", nil, UIParent, "PortraitFrameTemplateNoCloseButton")
        assert.is_not_nil(plain.PortraitContainer)
        assert.is_nil(plain.CloseButton)
    end)

    it("appends a PanelTabButtonTemplate to its parent's Tabs", function()
        -- SharedUIPanelTemplates.xml:905 declares parentArray="Tabs".
        local parent = CreateFrame("Frame", nil, UIParent)
        local first = CreateFrame("Button", nil, parent, "PanelTabButtonTemplate")
        local second = CreateFrame("Button", nil, parent, "PanelTabButtonTemplate")
        assert.same({ first, second }, parent.Tabs)
        -- A plain button is not a tab.
        CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        assert.equal(2, #parent.Tabs)
    end)

    it("builds InputScrollFrameTemplate's editbox with no letter limit", function()
        -- SecureUIPanelTemplates.xml:106, its maxLetters KeyValue at :108, the
        -- CharCount font string at :172, the ScrollChild EditBox at :183
        -- (multiLine="true") and its Instructions font string at :190.
        local scroll = CreateFrame("ScrollFrame", nil, UIParent, "InputScrollFrameTemplate")
        assert.equal(0, scroll.maxLetters)
        assert.equal("FontString", scroll.CharCount:GetObjectType())
        assert.equal("EditBox", scroll.EditBox:GetObjectType())
        assert.is_true(scroll.EditBox:IsMultiLine())
        assert.equal(0, scroll.EditBox:GetMaxLetters())
        assert.equal("FontString", scroll.EditBox.Instructions:GetObjectType())
        assert.equal(scroll.EditBox, scroll:GetScrollChild())
    end)

    it("gives a template nothing when the frame is built without one", function()
        local frame = CreateFrame("Frame", nil, UIParent)
        assert.is_nil(frame.TitleText)
        assert.is_nil(frame.CloseButton)
        assert.is_nil(frame.PortraitContainer)
        assert.is_nil(frame.CharCount)
        assert.is_nil(frame.EditBox)
        assert.is_nil(frame.Init)
    end)

    -- ---------------------------------------------------------------------
    -- The tooltip
    -- ---------------------------------------------------------------------

    it("makes GameTooltip a GameTooltip and keeps the test's reader off it", function()
        -- Core/Widget/Frame/GameTooltip.lua:3 `GameTooltip : Frame`. Every
        -- method the stub gives it is one of its own; `Text()` is not one of
        -- them, so it is on the shelf.
        assert.equal("GameTooltip", GameTooltip:GetObjectType())
        assertAbsent(GameTooltip, { "Text" }, "GameTooltip")
        GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
        GameTooltip:SetText("first")
        GameTooltip:AddLine("second")
        assert.equal("first\nsecond", GameTooltip.stub:Text())
    end)
end)

-- V-4 (WKE-589). The stub's modelled clock exists so a daylight-saving fault
-- can be made red in a container that has no timezone database at all. It is
-- only worth having if it behaves the way a real `date` and `mktime` do, so
-- every number below was first read from musl's own pair under
-- TZ=America/Chicago (`docker run -e TZ=America/Chicago lootpath-lua`, tzdata
-- installed, 2026-09-15) and is asserted here against the model.
describe("the headless stub's modelled clock", function()
    local H = require("spec.helpers.addon")
    local world

    -- 2026-09-15T22:20:31Z, the stamp on the owner's screen, and the same wall
    -- clock in January. Both computed as UTC seconds, not remembered.
    local SUMMER = 1789510831
    local WINTER = 1768515631

    before_each(function()
        world = Stub.install()
        H.chicagoClock(world, SUMMER)
    end)

    after_each(function()
        Stub.uninstall()
    end)

    it('writes UTC fields with isdst false, the way Lua\'s date("!*t") does', function()
        local utc = date("!*t", SUMMER)
        assert.equal(2026, utc.year)
        assert.equal(9, utc.month)
        assert.equal(15, utc.day)
        assert.equal(22, utc.hour)
        assert.equal(20, utc.min)
        assert.equal(31, utc.sec)
        assert.is_false(utc.isdst)
        -- and in winter too: UTC never has a daylight offset
        assert.is_false(date("!*t", WINTER).isdst)
    end)

    it("writes local fields with the instant's own isdst and offset", function()
        local summer = date("*t", SUMMER)
        assert.is_true(summer.isdst)
        assert.equal(17, summer.hour) -- UTC-5
        assert.equal(20, summer.min)
        local winter = date("*t", WINTER)
        assert.is_false(winter.isdst)
        assert.equal(16, winter.hour) -- UTC-6
        assert.equal("17:20", date("%H:%M", SUMMER))
        assert.equal("16:20", date("%H:%M", WINTER))
        assert.equal("22:20", date("!%H:%M", SUMMER))
    end)

    -- The field this whole issue turns on. musl, TZ=America/Chicago, on the UTC
    -- fields of an instant in September: auto=1789881631 false=1789885231
    -- true=1789881631 - `false` an hour later than the other two, because it
    -- means "read these as STANDARD time" and standard time is an hour behind.
    -- In January: auto=1768537231 false=1768537231 true=1768533631, the other
    -- way round. The model reproduces both relationships.
    it("reads isdst on the way in the way mktime reads tm_isdst", function()
        local function at(epoch, isdst)
            local t = date("!*t", epoch)
            local fields = { year = t.year, month = t.month, day = t.day, hour = t.hour, min = t.min, sec = t.sec }
            fields.isdst = isdst
            return time(fields)
        end
        -- September: absent and true agree, false is an hour later
        assert.equal(at(SUMMER, nil), at(SUMMER, true))
        assert.equal(at(SUMMER, nil) + 3600, at(SUMMER, false))
        -- January: absent and false agree, true is an hour earlier
        assert.equal(at(WINTER, nil), at(WINTER, false))
        assert.equal(at(WINTER, nil) - 3600, at(WINTER, true))
        -- and `false` is the same 6 hours from the UTC wall clock in both,
        -- which is what makes it the pairing ns.EpochFromISO uses
        assert.equal(SUMMER - H.CHICAGO.standard, at(SUMMER, false))
        assert.equal(WINTER - H.CHICAGO.standard, at(WINTER, false))
    end)

    it("answers bare time() with the modelled now", function()
        assert.equal(SUMMER, time())
        H.chicagoClock(world, WINTER)
        assert.equal(WINTER, time())
    end)
end)

describe("a masked texture", function()
    before_each(function()
        Stub.install()
    end)
    after_each(function()
        Stub.uninstall()
    end)

    it("refuses tex coords the way the client does", function()
        -- The owner's Lua Error window, 2026-09-16 14:39:48: `Texture:SetTexCoord():
        -- Cannot set tex coords when texture has mask.` (M5-2a, WKE-593).
        local frame = CreateFrame("Frame")
        local texture = frame:CreateTexture(nil, "ARTWORK")
        texture:SetTexCoord(0.05, 0.95, 0.05, 0.95)
        assert.same({ 0.05, 0.95, 0.05, 0.95 }, texture.texCoord)
        texture:SetMask("Interface/CharacterFrame/TempPortraitAlphaMask")
        assert.has_error(function()
            texture:SetTexCoord(0.05, 0.95, 0.05, 0.95)
        end, "Texture:SetTexCoord(): Cannot set tex coords when texture has mask.")
    end)
end)

-- spec/stubs/wow.lua
-- The minimum fake WoW API surface for headless busted runs. Shapes come from
-- Blizzard's exported API docs (Ketho's annotations, checked 2026-09-05) and
-- the build tuple from the Healper spike's in-client capture of GetBuildInfo()
-- (2026-09-01, 12.1.0 build 69587). Nothing here comes from the wiki.
--
-- Values are placeholders: a test that needs a real return shape reads a
-- committed capture under spec/fixtures/ instead. The stub exists so the pure
-- modules can be exercised without a client; it proves nothing about the client.
--
-- Usage: local world = Stub.install()  ... Stub.uninstall()
-- `world` is the mutable model behind the API (combat state, bags, vault...).

local Stub = {}

-- What one character is worth when a headless FontString is asked how wide its
-- text is (M5-2b, WKE-601). Not a measurement of any font: the client measures
-- glyphs and a test cannot, so the stub answers something PROPORTIONAL to the
-- string instead, which is all a "does this fit" decision needs. Tests read it
-- from here rather than writing 6 twice.
Stub.CHAR_WIDTH = 6

local function deepcopy(value, seen)
    if type(value) ~= "table" then
        return value
    end
    seen = seen or {}
    if seen[value] then
        return seen[value]
    end
    local out = {}
    seen[value] = out
    for k, v in pairs(value) do
        out[deepcopy(k, seen)] = deepcopy(v, seen)
    end
    return out
end
Stub.deepcopy = deepcopy

local saved = {}
local installedNames = {}

local function define(name, value)
    if not installedNames[name] then
        installedNames[name] = true
        saved[name] = _G[name]
    end
    _G[name] = value
end

-- Widgets. Enough of the real thing for the UI (M2-2) to be built and driven
-- headlessly: anchors, sizes, show/hide, scripts, font strings, buttons and an
-- editbox. It models the API's CONTRACT (SetMaxLetters(0) means no limit;
-- SetEnabled(false) means OnClick does not fire), never its pixels - what a
-- frame looks like on the owner's screen is an in-game step (M2-3), not a test.
--
-- **One widget carries one widget's methods** (WKE-560, T-1). Which methods a
-- kind gets is read under `.luals/vscode-wow-api/Annotations/Core/Widget/`,
-- class by class, and the stub gives a kind nothing its own class does not
-- have. A superset is a test that cannot go red: on 2026-09-10 the Upgrade Map
-- tab errored in the owner's client on `SetDefaultText` while 761 tests were
-- green, because the stub handed the method to every DropdownButton. Missing
-- the other way is safe and deliberate - a method no panel calls is simply not
-- modelled, and a panel that starts calling it fails headlessly first.
--
-- The class hierarchy, as the annotations declare it:
--   Region : ScriptRegion, ScriptRegionResizing, AnimatableObject  (Base/Region.lua:3)
--   Frame : Region, ScriptObject                                   (Frame/Frame.lua:3)
--   Button : Frame  /  CheckButton : Button                        (Frame/Button/Button.lua:3, CheckButton.lua:3)
--   EditBox : Frame  /  ScrollFrame : Frame                        (Frame/EditBox.lua:3, Frame/ScrollFrame.lua:3)
--   EventFrame : EventFrameMixin, Frame                            (Intrinsic/EventFrame.lua:13)
--   DropdownButton : DropdownButtonMixin, Button                   (Intrinsic/DropdownButton.lua:9)
--   FontString : Region                                            (Font/FontString.lua:3)
--   Texture : TextureBase : Region                                 (Texture/Texture.lua:3, Base/TextureBase.lua:3)
-- So text setters are a FontString's (and, for four of them, an EditBox's),
-- texture setters are a Texture's, and the scroll setters are a ScrollFrame's.
-- None of the three belongs on a bare Frame.

-- Appearance-only setters: accepted and ignored, because a headless test has no
-- pixels to check them against. `SetDrawLayer` is Region's (Base/Region.lua:56),
-- so every widget answers it.
local IGNORED_REGION_METHODS = {
    "SetDrawLayer",
}

-- The font setters a FontString ignores. All five are FontString's
-- (Font/FontString.lua:194 SetNonSpaceWrap, and the four inherited font-instance
-- setters); an EditBox has four of them (Frame/EditBox.lua:262, :266, :285, :289)
-- and not SetNonSpaceWrap, which is why the two lists are separate.
local IGNORED_FONT_METHODS = {
    "SetJustifyH",
    "SetJustifyV",
    "SetFontObject",
    "SetFont",
    "SetNonSpaceWrap",
}
local IGNORED_EDITBOX_FONT_METHODS = {
    "SetJustifyH",
    "SetJustifyV",
    "SetFontObject",
    "SetFont",
}

-- Stub-only affordances - a test clicking a menu row, firing an OnEnter, or
-- reading a tooltip back - live on `widget.stub` and never in a Blizzard method
-- slot (WKE-560). A panel that reached for one in the client would index a nil
-- field and say so on the first frame, instead of passing headlessly and
-- erroring on the owner's screen.
local function stubShelf(r)
    local shelf = { widget = r }
    r.stub = shelf
    return shelf
end

-- The Region surface every widget has, whatever its class: anchors, size,
-- visibility, scale, alpha and vertex colour (Base/Region.lua,
-- Base/ScriptRegion.lua, Base/ScriptRegionResizing.lua).
local function attachRegion(r)
    function r:GetObjectType()
        return self.kind
    end
    function r:GetParent()
        return self.parent
    end
    -- Every widget answers GetName; an anonymous one answers nil (Blizzard's
    -- ScriptObject annotations). CreateFrame sets frameName when it was given
    -- a name, which is exactly when the real client registers a global.
    function r:GetName()
        return self.frameName
    end
    function r:SetParent(p)
        self.parent = p
    end
    function r:SetPoint(...)
        self.points[#self.points + 1] = { ... }
    end
    function r:ClearAllPoints()
        self.points = {}
    end
    -- The relative region is kept (UX-4c, WKE-612). `SetAllPoints(other)` and a
    -- bare `SetAllPoints()` are different anchorings - one pins to a named
    -- region, the other to the parent - and a test that cannot tell them apart
    -- cannot say two layers of one mark sit on the same rectangle. A bare call
    -- still records `{ "ALL" }`, because the second slot is then nil.
    function r:SetAllPoints(relativeTo)
        self.points[#self.points + 1] = { "ALL", relativeTo }
    end
    function r:SetSize(w, h)
        self.width, self.height = w, h
    end
    function r:SetWidth(w)
        self.width = w
    end
    function r:SetHeight(h)
        self.height = h
    end
    function r:GetWidth()
        return self.width
    end
    function r:GetHeight()
        return self.height
    end
    function r:Show()
        self.shown = true
    end
    function r:Hide()
        self.shown = false
    end
    function r:SetShown(value)
        self.shown = value and true or false
    end
    function r:IsShown()
        return self.shown
    end
    function r:IsVisible()
        return self.shown
    end
    function r:SetScale(value)
        self.scale = tonumber(value) or 1
    end
    function r:GetScale()
        return self.scale or 1
    end
    function r:GetEffectiveScale()
        return self.effectiveScale or self.scale or 1
    end
    -- The frame's centre in UI coordinates (Base/ScriptRegion.lua:51). Nothing
    -- here lays anything out, so it is whatever a test set (used by the minimap
    -- drag, M5-2); 0, 0 unset.
    function r:GetCenter()
        local c = self.center
        if not c then
            return 0, 0
        end
        return c[1], c[2]
    end
    -- Alpha and vertex colour are Region's (Base/Region.lua:75 SetVertexColor),
    -- so a Frame has them as much as a Texture does. Whether a badge is at a
    -- downgrade's opacity is a decision this addon makes and a test can hold it
    -- to (M5-1, WKE-550); the real widget has no getter for the colour, so none
    -- is faked - the last arguments are left under names of the stub's own
    -- (`vertexColor`, `alpha`).
    function r:SetAlpha(value)
        self.alpha = value
    end
    function r:GetAlpha()
        return self.alpha == nil and 1 or self.alpha
    end
    function r:SetVertexColor(red, green, blue, alpha)
        self.vertexColor = { red, green, blue, alpha }
    end
    for _, name in ipairs(IGNORED_REGION_METHODS) do
        r[name] = function() end
    end
end

-- A FontString's own text surface (Font/FontString.lua): SetText/GetText at
-- :222/:119, SetTextColor at :229, SetWordWrap at :245, and the five ignored
-- font setters above. A Frame has none of these.
local function attachFontSurface(r)
    function r:SetText(value)
        self.text = value == nil and "" or tostring(value)
    end
    function r:GetText()
        return self.text
    end
    -- Not appearance-only: whether a font string wraps decides whether a long
    -- line is shown or cut off at the frame's edge, which is a contract a test
    -- can hold the UI to. Recorded as stub state (`region.wordWrap`); the real
    -- widget has no getter for it, so none is faked here.
    function r:SetWordWrap(value)
        self.wordWrap = value and true or false
    end
    function r:SetTextColor(red, green, blue, alpha)
        self.textColor = { red, green, blue, alpha }
    end
    -- FontString:GetStringWidth (Font/FontString.lua:115) is real, and since
    -- M5-2b (WKE-601) the status strip and the vault's currency chips fit
    -- themselves with it. Nothing headless can measure a glyph, so the stub
    -- answers a fixed width PER CHARACTER of the text it is holding
    -- (`Stub.CHAR_WIDTH`) - enough for a test to build a line that does or does
    -- not fit a given row - and records every string it was asked about in
    -- `region.measured`, so a test can also see WHICH candidates the fit tried.
    function r:GetStringWidth()
        local text = self.text or ""
        self.measured = self.measured or {}
        self.measured[#self.measured + 1] = text
        return #text * Stub.CHAR_WIDTH
    end
    for _, name in ipairs(IGNORED_FONT_METHODS) do
        r[name] = function() end
    end
end

-- A Texture's own surface (Base/TextureBase.lua and Texture/Texture.lua).
-- WHICH texture a region was given is a decision the code makes - the spec icon
-- or the class sheet, the class sheet at which corner - and not a pixel, so it
-- is recorded rather than ignored (M5-1, M5-2). The real widget has no getter
-- for the tex coords; nothing here is faked beyond remembering what it was told.
local function attachTextureSurface(r)
    -- A texture and an atlas are the same slot in the real widget: setting one
    -- replaces the other, which is why a row that stops being a swap and drops
    -- its arrow atlas cannot still be showing it.
    function r:SetTexture(value)
        self.texture = value
        self.atlas = nil
    end
    function r:GetTexture()
        return self.texture
    end
    -- `TextureBase:SetAtlas(atlas, useAtlasSize, ...)`: the second argument
    -- makes the client size the texture to the art's own size (Ketho,
    -- Core/Widget/Base/TextureBase.lua). The stub does the same, so a test can
    -- read the size a texture ended up with and see whether the art was drawn at
    -- its own proportions or squashed into someone else's box (V-5a, WKE-607).
    function r:SetAtlas(value, useAtlasSize)
        self.atlas = value
        self.texture = nil
        self.atlasUsedSize = useAtlasSize and true or false
        if useAtlasSize and C_Texture and C_Texture.GetAtlasInfo then
            local info = C_Texture.GetAtlasInfo(value)
            if info and info.width and info.height then
                self.width, self.height = info.width, info.height
            end
        end
    end
    function r:GetAtlas()
        return self.atlas
    end
    -- `TextureBase:SetColorTexture(r, g, b, a)` (Core/Widget/Base/
    -- TextureBase.lua): a flat colour in place of a file or an atlas. It is
    -- what a mark falls back to on a client that does not ship the art, and
    -- what the slot bar's segments are made of (M5-1b, WKE-610). It fills the
    -- same slot as the other two, so setting one clears the others - exactly as
    -- SetTexture and SetAtlas already do to each other here. The real widget has
    -- no getter for it, so the colour is recorded under a name of the stub's own
    -- and a test reads it back from there.
    function r:SetColorTexture(red, green, blue, alpha)
        self.colorTexture = { red, green, blue, alpha }
        self.texture = nil
        self.atlas = nil
    end
    -- The client refuses tex coords on a masked texture - `Texture:SetTexCoord():
    -- Cannot set tex coords when texture has mask.`, read off the owner's Lua
    -- Error window on 2026-09-16 14:39:48 (M5-2a, WKE-593), where it stopped
    -- the minimap button half built. The stub throws the same sentence, so a
    -- test can catch the pairing before a screen does.
    function r:SetTexCoord(...)
        if self.mask ~= nil then
            error("Texture:SetTexCoord(): Cannot set tex coords when texture has mask.", 2)
        end
        self.texCoord = { ... }
    end
    -- TextureBase:SetMask(file) (Core/Widget/Base/TextureBase.lua:142): the
    -- one-file form of a MaskTexture, which crops the texture to the mask's
    -- alpha over the texture's own bounds. Recorded, never drawn - a test can
    -- only ask WHICH mask, not what it looked like (M5-2a, WKE-593).
    function r:SetMask(file)
        self.mask = file
    end
    function r:GetMask()
        return self.mask
    end
    -- `TextureBase:SetGradient(orientation, minColor, maxColor)` (Core/Widget/
    -- Base/TextureBase.lua:130-134): the two colours are `colorRGBA`s, which is
    -- what the stub's `CreateColor` hands back. Recorded under a name of the
    -- stub's own - the real widget has no getter - so a test can read which way
    -- the gradient runs and from what to what (UX-5a, WKE-634). A client
    -- without it is `world.textureGradient = false`, which strips the method
    -- from every texture made after it is set.
    function r:SetGradient(orientation, minColor, maxColor)
        self.gradient = { orientation = orientation, minColor = minColor, maxColor = maxColor }
    end
    -- The layer a texture was created in, as Frame:CreateTexture's second
    -- argument names it. The real client returns the sub-level too; nothing
    -- here sets one, so it answers the default 0.
    function r:GetDrawLayer()
        return self.drawLayer, 0
    end
end

local function newRegion(kind, parent)
    local r = {
        kind = kind,
        parent = parent,
        points = {},
        shown = true,
        text = "",
        width = 0,
        height = 0,
        children = {},
        regions = {},
    }
    attachRegion(r)
    stubShelf(r)
    if kind == "FontString" then
        attachFontSurface(r)
    elseif kind == "Texture" then
        attachTextureSurface(r)
    end
    return r
end

local newFrame

-- ---------------------------------------------------------------------------
-- The 11.0 ScrollBox, as far as its CONTRACT goes (M5-3, WKE-552). Read under
-- .luals/ in Blizzard_SharedXML/Shared/Scroll/ rather than remembered:
--   * `CreateDataProvider(tbl)` returns a DataProviderMixin whose collection is
--     the table it was handed (DataProvider.lua:14, :261).
--   * `CreateScrollBoxListLinearView(top, bottom, left, right, spacing)`
--     returns a view; `SetElementInitializer(templateOrType, initializer)` is
--     sugar over `SetElementFactory(function(factory, elementData) ... end)`
--     (ScrollBoxListView.lua:461), and a list of mixed element kinds uses the
--     factory directly.
--   * `ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)` registers the
--     pair and calls `box:Init(view)` (ScrollUtil.lua:92).
--   * **The list is VIRTUALIZED.** `ValidateDataRange` acquires frames only for
--     the data indices `CalculateDataIndices` says are on screen and releases
--     the rest back to a frame factory (ScrollBoxListView.lua:335, :414, :655,
--     and :575 `IsVirtualized`). That is the one behaviour the panel is built
--     for - 478 rows must not mean 478 frames - so it is modelled here rather
--     than ignored: the box lays out from the top until it has covered its own
--     height, and every element past that gets no frame at all.
-- Nothing here draws anything. What a row looks like is still an in-game step.

local function newDataProvider(tbl)
    local provider = { collection = {} }
    for _, value in ipairs(tbl or {}) do
        provider.collection[#provider.collection + 1] = value
    end
    function provider:GetSize()
        return #self.collection
    end
    function provider:Find(index)
        return self.collection[index]
    end
    function provider:Insert(...)
        for i = 1, select("#", ...) do
            self.collection[#self.collection + 1] = (select(i, ...))
        end
    end
    function provider:InsertTable(list)
        for _, value in ipairs(list or {}) do
            self.collection[#self.collection + 1] = value
        end
    end
    function provider:Flush()
        self.collection = {}
    end
    function provider:Enumerate(indexBegin, indexEnd)
        local index = (indexBegin or 1) - 1
        local last = indexEnd or #self.collection
        return function()
            index = index + 1
            if index > last then
                return nil
            end
            return index, self.collection[index]
        end
    end
    function provider:EnumerateEntireRange()
        return self:Enumerate()
    end
    return provider
end

local function newScrollBoxListLinearView(top, bottom, left, right, spacing)
    local view = {
        padding = { top = top or 0, bottom = bottom or 0, left = left or 0, right = right or 0 },
        spacing = spacing or 0,
    }
    function view:SetPadding(t, b, l, r, sp)
        self.padding = { top = t or 0, bottom = b or 0, left = l or 0, right = r or 0 }
        self.spacing = sp or 0
    end
    function view:SetElementFactory(factory)
        self.elementFactory = factory
    end
    function view:SetElementInitializer(frameTemplateOrType, initializer)
        self.frameTemplateOrFrameType = frameTemplateOrType
        self:SetElementFactory(function(factory)
            factory(frameTemplateOrType, initializer)
        end)
    end
    function view:SetElementExtent(extent)
        self.elementExtent = extent
    end
    function view:SetElementExtentCalculator(calculator)
        self.elementExtentCalculator = calculator
    end
    function view:GetElementExtent(dataIndex, elementData)
        if self.elementExtentCalculator then
            return self.elementExtentCalculator(dataIndex, elementData)
        end
        return self.elementExtent or 20
    end
    function view:SetElementResetter(resetter)
        self.frameResetter = resetter
    end
    return view
end

-- Which template and initializer an element wants, without creating a frame:
-- the real view asks its factory the same way when it only needs the extent
-- (ScrollBoxListView.lua, "This local factory function allows us to ask for
-- the template and initializer without actually creating a frame").
local function factoryDataFor(view, elementData)
    local template, initializer
    if view.elementFactory then
        view.elementFactory(function(t, init)
            template, initializer = t, init
        end, elementData)
    end
    return template, initializer
end

local function attachScrollBoxList(box, world)
    box.frames = {}
    box.pool = {} -- [template] = { frames }
    box.framesCreated = 0
    box.scrollTarget = newFrame("Frame", world, box)

    function box:Init(view)
        self.view = view
    end
    function box:GetView()
        return self.view
    end
    function box:GetScrollTarget()
        return self.scrollTarget
    end
    function box:GetDataProvider()
        return self.dataProvider
    end
    function box:GetFrames()
        return self.frames
    end
    function box:GetDataProviderSize()
        return self.dataProvider and self.dataProvider:GetSize() or 0
    end
    box.ScrollToBegin = function() end
    box.SetInterpolateScroll = function() end
    box.CanInterpolateScroll = function()
        return false
    end

    -- The frame pool is the VIEW's and the frame factory's, never the box's:
    -- `ScrollBoxListViewMixin:AcquireInternal` (ScrollBoxListView.lua:335) and
    -- `self.frameFactory:ReleaseAll()` (:131). A ScrollBox answers neither, so
    -- neither sits in a Blizzard method slot here - they are the stub's own.
    function box.stub.Acquire(shelf, template)
        local self = shelf.widget
        local pool = self.pool[template]
        if not pool then
            pool = {}
            self.pool[template] = pool
        end
        for _, frame in ipairs(pool) do
            if not frame.inUse then
                frame.inUse = true
                return frame
            end
        end
        -- The frame TYPE and the frame TEMPLATE are one argument in the real
        -- factory: "Frame" and "MyRowTemplate" both arrive here.
        local kind = (template == "Button" or template == "Frame" or template == "CheckButton") and template or "Frame"
        local frame = newFrame(kind, world, self.scrollTarget, kind == template and nil or template)
        frame.inUse = true
        pool[#pool + 1] = frame
        self.framesCreated = self.framesCreated + 1
        return frame
    end

    function box.stub.ReleaseAll(shelf)
        local self = shelf.widget
        for _, pool in pairs(self.pool) do
            for _, frame in ipairs(pool) do
                if frame.inUse then
                    frame.inUse = false
                    frame:Hide()
                    if self.view and self.view.frameResetter then
                        self.view.frameResetter(frame, frame.elementData)
                    end
                    -- The real view clears the reader when it releases a
                    -- frame (ScrollBoxListView.lua:114), so a frame that is
                    -- back in the pool cannot still answer for its old row.
                    frame.GetElementData = nil
                end
            end
        end
        self.frames = {}
    end

    -- One layout pass: a frame for every element from the top down until the
    -- box's own height is covered, and nothing for the rest. The real widget
    -- calculates the same range from its scroll offset; a headless box never
    -- scrolls, so its range always begins at 1.
    function box:Layout()
        local view = self.view
        self.stub:ReleaseAll()
        if not (view and self.dataProvider) then
            return
        end
        -- How much of the list is on screen. A real scroll box is sized by
        -- its anchors - the panels anchor one to two corners of their frame -
        -- and nothing here lays anything out, so a box with no size of its own
        -- takes the nearest ancestor that has one. That errs towards MORE
        -- visible rows than the client would show, which makes a bounded-pool
        -- assertion harder to pass rather than easier.
        local height = self:GetHeight() or 0
        local ancestor = self.parent
        while height <= 0 and ancestor do
            height = ancestor.GetHeight and ancestor:GetHeight() or 0
            ancestor = ancestor.parent
        end
        if height <= 0 then
            height = 1
        end
        local used, total = 0, 0
        for index, elementData in self.dataProvider:Enumerate() do
            local extent = view:GetElementExtent(index, elementData) or 1
            total = total + extent + view.spacing
            if used <= height then
                local template, initializer = factoryDataFor(view, elementData)
                if template then
                    local frame = self.stub:Acquire(template)
                    frame.elementData = elementData
                    frame.GetElementData = function(element)
                        return element.elementData
                    end
                    frame:SetHeight(extent)
                    frame:Show()
                    self.frames[#self.frames + 1] = frame
                    if initializer then
                        initializer(frame, elementData)
                    end
                end
                used = used + extent + view.spacing
            end
        end
        self.extent = total
    end

    -- ScrollBox.lua:869. The real call asks its view to prepare, finds the
    -- data index by predicate (ScrollBoxListView.lua:200, which is the data
    -- provider's own FindIndexByPredicate), and returns the element data it
    -- scrolled to - or nothing at all when no element matches. A headless box
    -- has no offset to move, so what is modelled is the FIND and the answer:
    -- `scrolledTo` records which element the box was asked to put on screen.
    function box:ScrollToElementDataByPredicate(predicate)
        if not (self.dataProvider and type(predicate) == "function") then
            return nil
        end
        for index, elementData in self.dataProvider:Enumerate() do
            if predicate(elementData) then
                self.scrolledToIndex = index
                self.scrolledTo = elementData
                return elementData
            end
        end
        return nil
    end

    function box:SetDataProvider(dataProvider)
        self.dataProvider = dataProvider
        self:Layout()
    end
    function box:FlushDataProvider()
        self:SetDataProvider(newDataProvider({}))
    end
end

-- The DropdownButton INTRINSIC's menu surface, which is DropdownButtonMixin's
-- and therefore every DropdownButton's, template or none
-- (Core/Widget/Intrinsic/DropdownButton.lua:9 `DropdownButton : DropdownButtonMixin,
-- Button`; Blizzard_Menu/DropdownButton.lua:237 SetupMenu, :255 GenerateMenu,
-- :275 IsMenuOpen). The generator is handed the dropdown and a root description
-- and calls CreateRadio / CreateButton / CreateTitle / SetTag on it
-- (MenuUtil.lua:226 CreateRadio(text, isSelected, setSelected, data)). What is
-- modelled is which elements the generator asked for and what each one does
-- when it is picked, which is the whole contract the panels depend on; the
-- menu's pixels are the client's.
--
-- The CAPTION on the closed control is NOT here: SetDefaultText and friends are
-- DropdownSelectionTextMixin's, which only some templates mix in (see
-- attachDropdownSelectionText below).
local function attachDropdownButton(dropdown)
    dropdown.menuElements = {}

    local function rootDescription(list)
        local root = { elements = list }
        local function add(kind, text, isSelected, setSelected, data)
            local element = {
                kind = kind,
                text = text,
                isSelected = isSelected,
                setSelected = setSelected,
                data = data,
            }
            function element:IsSelected()
                if type(self.isSelected) == "function" then
                    return self.isSelected(self.data) and true or false
                end
                return false
            end
            -- What a click on this row does, which is the only way a test can
            -- pick an option: the real menu calls setSelected with the data.
            function element:Select()
                if type(self.setSelected) == "function" then
                    self.setSelected(self.data)
                end
            end
            list[#list + 1] = element
            return element
        end
        function root:SetTag(tag)
            self.tag = tag
        end
        root.CreateRadio = function(_, text, isSelected, setSelected, data)
            return add("radio", text, isSelected, setSelected, data)
        end
        root.CreateCheckbox = function(_, text, isSelected, setSelected, data)
            return add("checkbox", text, isSelected, setSelected, data)
        end
        root.CreateButton = function(_, text, onSelect, data)
            return add("button", text, nil, onSelect, data)
        end
        root.CreateTitle = function(_, text)
            return add("title", text)
        end
        root.CreateDivider = function()
            return add("divider")
        end
        return root
    end

    function dropdown:GenerateMenu()
        if type(self.menuGenerator) ~= "function" then
            return
        end
        self.menuElements = {}
        self.rootDescription = rootDescription(self.menuElements)
        self.menuGenerator(self, self.rootDescription)
        -- The generic DropdownButton's Pick/SelectedIndex read these.
        self.menuEntries = self.menuElements
        self.menuTag = self.rootDescription.tag
    end
    function dropdown:SetupMenu(generator)
        assert(type(generator) == "function", "SetupMenu: argument is not a function")
        self.menuGenerator = generator
        self:GenerateMenu()
    end
    dropdown.IsMenuOpen = function()
        return false
    end

    -- Picking an option the way a player does. None of these three is a client
    -- method: DropdownButtonMixin:Pick takes a menu DESCRIPTION and an input
    -- context (DropdownButton.lua:341), not an index, and there is no
    -- SelectedIndex or SelectByText at all - so they sit on the stub shelf
    -- where they cannot be mistaken for API. The real menu rebuilds its rows
    -- from the owner's state every time it opens, so each one regenerates.
    function dropdown.stub.Pick(_, index)
        dropdown:GenerateMenu()
        local element = dropdown.menuElements[index]
        if not element then
            return false
        end
        element:Select()
        return true
    end
    function dropdown.stub.SelectedIndex()
        dropdown:GenerateMenu()
        for index, element in ipairs(dropdown.menuElements) do
            if element:IsSelected() then
                return index
            end
        end
        return nil
    end
    function dropdown.stub.SelectByText(_, text)
        for _, element in ipairs(dropdown.menuElements) do
            if element.text == text then
                element:Select()
                return true
            end
        end
        return false
    end
end

-- DropdownSelectionTextMixin: the words on the CLOSED control. Mixed into
-- WowStyle1DropdownTemplate through WowStyle1DropdownMixin
-- (Blizzard_Menu/Mainline/MenuTemplates.xml:3 `mixin="WowStyle1DropdownMixin"`;
-- MenuTemplates.lua:753 `WowStyle1DropdownMixin = CreateFromMixins(
-- ButtonStateBehaviorMixin, DropdownSelectionTextMixin)`), and NOT into
-- WowStyle1FilterDropdownTemplate, whose WowStyle1FilterDropdownMixin is
-- ButtonStateBehaviorMixin + DropdownTextMixin + WowFilterButtonMixin
-- (MenuTemplates.xml:66, MenuTemplates.lua:776) and carries a fixed FILTER
-- caption instead (the KeyValue at MenuTemplates.xml:69). That difference is
-- what the owner's client raised as "attempt to call a nil value" on the
-- Upgrade Map tab on 2026-09-10. GetDefaultText / SetDefaultText are
-- MenuTemplates.lua:578 / :582; SetTooltip (:659) is real too and is still not
-- modelled, because no panel calls it.
--
-- SetSelectionText (:591) IS modelled since M5-2b (WKE-601), because the Vault
-- tab now calls it: the menu's rows keep the long sentence and the CLOSED
-- control says the scenario's short name. What the client does with it is
-- UpdateToMenuSelections (:604): the selection function's answer wins, the
-- selected row's own text is the fallback, and the default text is what is left
-- when nothing is selected. `dropdown.stub:Caption()` is that reading - the
-- words a player would see on the closed control - and it is on the shelf
-- because the real widget has no getter for them.
local function attachDropdownSelectionText(dropdown)
    function dropdown:SetDefaultText(text)
        self.defaultText = text
    end
    function dropdown:GetDefaultText()
        return self.defaultText
    end
    function dropdown:SetSelectionText(selectionFunc)
        self.selectionFunc = selectionFunc
    end
    function dropdown.stub.Caption()
        local index = dropdown.stub:SelectedIndex()
        local selected = index and dropdown.menuElements[index] or nil
        if type(dropdown.selectionFunc) == "function" then
            local text = dropdown.selectionFunc(selected and { selected } or nil)
            if text ~= nil then
                return text
            end
        end
        if selected then
            return selected.text
        end
        return dropdown.defaultText
    end
end

-- The stub's stand-in for whatever font object the client gives a
-- UIPanelButtonTemplate button (R-6d, WKE-630; see attachTemplate).
local UIPANEL_BUTTON_TEMPLATE_FONT = { fontName = "stub: UIPanelButtonTemplate's own NormalFont" }

local function attachTemplate(f, world, template)
    if type(template) ~= "string" then
        return
    end
    -- UIPanelButtonTemplate -> UIPanelButtonNoTooltipTemplate carries a
    -- HighlightTexture of its own, `UIPanelButtonHighlightTexture`, which is
    -- `Interface\Buttons\UI-Panel-Button-Highlight` in ADD blend mode
    -- (Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml:3 and :307). The
    -- addon never creates that texture - it asks the template's own back with
    -- `GetHighlightTexture` and tints it (R-6c, WKE-629) - so the stub hands
    -- over the one the template would have made, or the code under test finds
    -- nothing where the client has art.
    if template:find("UIPanelButtonTemplate", 1, true) and f.SetHighlightTexture then
        f:SetHighlightTexture([[Interface\Buttons\UI-Panel-Button-Highlight]], "ADD")
    end
    -- And the font object the template gives the button, which the addon reads
    -- back with `GetNormalFontObject` and restores (R-6d, WKE-630). The
    -- annotations name it `GameFontNormalOutline` (ibid.:304), but the owner's
    -- screen says the live client's answer is not that object - `Refresh`, set
    -- to it, looked unlike `Import...` and `Options`, which are never set. So
    -- the stub hands a sentinel of its own, the SAME object to every such
    -- button and distinct from `_G.GameFontNormalOutline`: a test can then tell
    -- "put back what it had" from "set the annotation's name".
    if template:find("UIPanelButtonTemplate", 1, true) and f.SetNormalFontObject then
        f.normalFontObject = UIPANEL_BUTTON_TEMPLATE_FONT
    end
    -- BasicFrameTemplate -> BaseBasicFrameTemplate carries TitleText and
    -- CloseButton (Blizzard_UIPanelTemplates/UIPanelTemplates.xml).
    if template:find("BasicFrameTemplate", 1, true) then
        f.TitleText = f:CreateFontString()
        f.CloseButton = newFrame("Button", world, f)
    end
    -- PortraitFrameTemplate -> PortraitFrameTemplateNoCloseButton ->
    -- PortraitFrameTexturedBaseTemplate -> PortraitFrameBaseTemplate, which is
    -- where PortraitContainer (with the `portrait` texture), TitleContainer and
    -- its TitleText come from; the CloseButton is PortraitFrameTemplate's own
    -- (Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml:544-635).
    if template:find("PortraitFrameTemplate", 1, true) then
        local titleContainer = newFrame("Frame", world, f)
        titleContainer.TitleText = titleContainer:CreateFontString()
        f.TitleContainer = titleContainer
        f.TitleText = titleContainer.TitleText
        local portraitContainer = newFrame("Frame", world, f)
        portraitContainer.portrait = portraitContainer:CreateTexture()
        f.PortraitContainer = portraitContainer
        f.NineSlice = newFrame("Frame", world, f)
        if not template:find("NoCloseButton", 1, true) then
            f.CloseButton = newFrame("Button", world, f)
        end
    end
    -- WowScrollBoxList is a Frame inheriting ScrollBoxBaseTemplate with
    -- ScrollBoxListMixin (Blizzard_SharedXML/Shared/Scroll/ScrollTemplates.xml:4),
    -- M5-3's.
    if template:find("WowScrollBoxList", 1, true) then
        attachScrollBoxList(f, world)
    end
    -- The caption surface is ADDED to the one template whose mixin chain has
    -- DropdownSelectionTextMixin, rather than handed to every dropdown and
    -- taken back from the rest. A superset that is subtracted again is still a
    -- superset: a `CreateFrame("DropdownButton")` with no template never
    -- reached the subtraction at all, and answered SetDefaultText headlessly
    -- while the intrinsic in the client does not have it.
    if template:find("WowStyle1DropdownTemplate", 1, true) then
        attachDropdownSelectionText(f)
    end
    -- PanelTabButtonTemplate declares parentArray="Tabs"
    -- (Blizzard_SharedXML/SharedUIPanelTemplates.xml line 905), so a tab built
    -- from it appends itself to its parent's `Tabs` list.
    if template:find("PanelTabButtonTemplate", 1, true) and f.parent then
        f.parent.Tabs = f.parent.Tabs or {}
        f.parent.Tabs[#f.parent.Tabs + 1] = f
    end
    -- InputScrollFrameTemplate's scroll child is a multiLine EditBox at
    -- parentKey EditBox, with maxLetters 0 and a CharCount label
    -- (Blizzard_SharedXML/SecureUIPanelTemplates.xml).
    if template:find("InputScrollFrameTemplate", 1, true) then
        f.maxLetters = 0
        f.CharCount = f:CreateFontString()
        local box = newFrame("EditBox", world, f)
        box:SetMultiLine(true)
        box:SetMaxLetters(f.maxLetters)
        box.Instructions = box:CreateFontString()
        f.EditBox = box
        f.scrollChild = box
    end
    -- UIPanelScrollFrameTemplate carries its scroll bar at parentKey ScrollBar
    -- (`@field ScrollBar UIPanelScrollFrameTemplate_ScrollBar : Slider`,
    -- Blizzard_SharedXML/SecureScrollTemplates.xml:44/46 in Ketho's
    -- annotations), and the bar is what actually moves the frame:
    -- `UIPanelScrollBar_OnValueChanged` is `self:GetParent():SetVerticalScroll(value)`
    -- (SecureScrollTemplates.lua:22), and `ScrollFrame_OnScrollRangeChanged`
    -- re-applies `math.min(scrollbar:GetValue(), yrange)` to it whenever the
    -- child is re-sized (:64) - it clamps the offset, it does not clear it.
    -- The bar is modelled to that much and no further: its min/max are recorded
    -- and nothing here invents a range, because no range is read from a test.
    if
        template:find("UIPanelScrollFrameTemplate", 1, true)
        or template:find("UIPanelInputScrollFrameTemplate", 1, true)
    then
        local bar = newFrame("Slider", world, f)
        bar.value = 0
        bar.minValue, bar.maxValue = 0, 0
        function bar:SetValue(value)
            self.value = value
            local owner = self:GetParent()
            if owner and owner.SetVerticalScroll then
                owner:SetVerticalScroll(value)
            end
        end
        function bar:GetValue()
            return self.value
        end
        function bar:SetMinMaxValues(minValue, maxValue)
            self.minValue, self.maxValue = minValue, maxValue
        end
        function bar:GetMinMaxValues()
            return self.minValue, self.maxValue
        end
        f.ScrollBar = bar
    end
end

function newFrame(kind, world, parent, template)
    kind = kind or "Frame"
    local f = newRegion(kind, parent)
    f.events = {}
    f.scripts = {}
    f.shown = false
    f.enabled = true
    f.template = template

    function f:RegisterEvent(event)
        self.events[event] = true
    end
    function f:UnregisterEvent(event)
        self.events[event] = nil
    end
    function f:UnregisterAllEvents()
        self.events = {}
    end
    function f:SetScript(handler, fn)
        self.scripts[handler] = fn
    end
    function f:GetScript(handler)
        return self.scripts[handler]
    end
    function f:HookScript(handler, fn)
        local previous = self.scripts[handler]
        self.scripts[handler] = function(...)
            if previous then
                previous(...)
            end
            fn(...)
        end
    end
    function f:CreateFontString()
        local fs = newRegion("FontString", self)
        self.regions[#self.regions + 1] = fs
        return fs
    end
    function f:CreateTexture(name, drawLayer)
        local tex = newRegion("Texture", self)
        tex.frameName = name
        tex.drawLayer = drawLayer
        if world and world.textureGradient == false then
            tex.SetGradient = nil
        end
        self.regions[#self.regions + 1] = tex
        return tex
    end
    function f:SetMovable(value)
        self.movable = value
    end
    function f:IsMovable()
        return self.movable
    end
    function f:EnableMouse(value)
        self.mouseEnabled = value
    end
    function f:RegisterForDrag(...)
        self.dragButtons = { ... }
    end
    f.StartMoving = function() end
    f.StopMovingOrSizing = function() end
    function f:SetClampedToScreen(value)
        self.clamped = value
    end
    function f:SetFrameStrata(value)
        self.strata = value
    end
    -- R-8a (WKE-618): frame levels, because a level is what decides which of two
    -- overlapping frames takes a click. A frame's default is its parent's plus
    -- one - the owner's own `/fstack` over the window read `LootpathMainFrame`
    -- at 1 and every child of it at 2 - and the setter is Blizzard's
    -- (Core/Widget/Frame/Frame.lua:441 SetFrameLevel, :176 GetFrameLevel). A
    -- level set here is remembered: nothing in the exported documentation says a
    -- hide or a show changes it, so neither does this.
    f.frameLevel = (parent and parent.frameLevel or 0) + 1
    function f:SetFrameLevel(value)
        self.frameLevel = value
    end
    function f:GetFrameLevel()
        return self.frameLevel
    end
    function f:SetToplevel(value)
        self.toplevel = value
    end
    function f:SetHyperlinksEnabled(value)
        self.hyperlinksEnabled = value
    end
    function f:SetID(value)
        self.id = value
    end
    function f:GetID()
        return self.id
    end
    -- The scroll setters are a ScrollFrame's alone (Core/Widget/Frame/ScrollFrame.lua:3
    -- `ScrollFrame : Frame`, which declares SetScrollChild, GetScrollChild,
    -- SetVerticalScroll, GetVerticalScrollRange and UpdateScrollChildRect). A
    -- bare Frame answers none of them, and neither does a WowScrollBoxList -
    -- the 11.0 box is a Frame with a scroll TARGET, not a scroll child.
    if kind == "ScrollFrame" then
        function f:SetScrollChild(child)
            self.scrollChild = child
        end
        function f:GetScrollChild()
            return self.scrollChild
        end
        function f:SetVerticalScroll(value)
            self.verticalScroll = value
        end
        f.GetVerticalScrollRange = function()
            return 0
        end
        f.UpdateScrollChildRect = function() end
    end

    -- Button's own surface (Core/Widget/Frame/Button/Button.lua): Click at :47,
    -- Disable :50, Enable :53, GetFontString :69, GetText :102, IsEnabled :114,
    -- RegisterForClicks :118, SetDisabledFontObject :135, SetEnabled :143,
    -- SetHighlightFontObject :161, SetNormalFontObject :178, SetText :199.
    -- CheckButton : Button (CheckButton.lua:3) and DropdownButton : Button
    -- (Intrinsic/DropdownButton.lua:9) both inherit all of it, so both get it -
    -- the Upgrade Map's difficulty control is a DropdownButton and calls
    -- SetText, which it has twice over (Button.lua:199 and, on the templates
    -- that mix it in, DropdownTextMixin:SetText at MenuTemplates.lua:522).
    -- CheckButton's own SetChecked / GetChecked are not modelled, because no
    -- panel uses a check button.
    if kind == "Button" or kind == "CheckButton" or kind == "DropdownButton" then
        function f:SetText(value)
            self.text = value == nil and "" or tostring(value)
        end
        function f:GetText()
            return self.text
        end
        function f:SetEnabled(value)
            self.enabled = value and true or false
        end
        function f:Enable()
            self.enabled = true
        end
        function f:Disable()
            self.enabled = false
        end
        function f:IsEnabled()
            return self.enabled
        end
        function f:GetFontString()
            return self.fontString
        end
        -- `Button:SetHighlightTexture(asset, blendMode)` (Button.lua:166) and
        -- its getter (:73). The client makes a Texture of its own out of the
        -- asset and draws it while the pointer is over the button; the stub
        -- makes the same region, so a test can read back WHICH art a button
        -- highlights with - a decision the code makes - without any of it being
        -- drawn. Blizzard's own buttons pass a file and a blend mode this way
        -- (`self:SetHighlightTexture([[Interface\Buttons\ButtonHilight-Square]],
        -- "ADD")`, Blizzard_ActionBar's VehicleLeaveButton).
        function f:SetHighlightTexture(asset, blendMode)
            local texture = self.highlightTexture or newRegion("Texture", self)
            self.highlightTexture = texture
            self.highlightBlendMode = blendMode
            if type(asset) == "string" then
                texture:SetTexture(asset)
            end
            return texture
        end
        function f:GetHighlightTexture()
            return self.highlightTexture
        end
        -- `Button:SetNormalFontObject` (Button.lua:178) is not appearance-only
        -- any more: since R-6c (WKE-629) the Refresh button wears Blizzard's
        -- own `GameFontDisable` while the rating is being made and, since R-6d
        -- (WKE-630), the font object it had at creation otherwise, which is a
        -- decision the addon makes and a test can hold it to. The object it was given is
        -- recorded under a name of the stub's own (`normalFontObject`); the two
        -- siblings stay no-ops, because nothing sets them.
        function f:SetNormalFontObject(font)
            self.normalFontObject = font
        end
        -- Its getter (Button.lua:85): what was set, or what the template gave
        -- (attachTemplate), or nil for a button with neither - R-6d (WKE-630)
        -- reads it at creation to put the same object back later.
        function f:GetNormalFontObject()
            return self.normalFontObject
        end
        f.SetDisabledFontObject = function() end
        f.SetHighlightFontObject = function() end
        -- `Frame:LockHighlight` / `Frame:UnlockHighlight` (Frame.lua:339, :547):
        -- the client draws the button's highlight texture as if the pointer
        -- were over it until it is unlocked. Recorded as stub state
        -- (`highlightLocked`), because whether a button is glowing is a
        -- decision and not a pixel.
        function f:LockHighlight()
            self.highlightLocked = true
        end
        function f:UnlockHighlight()
            self.highlightLocked = false
        end
        f.RegisterForClicks = function() end
        -- A disabled button swallows the click, exactly as the client does; its
        -- OnEnter still fires, which is how the combat tooltip is reachable.
        function f:Click(button)
            if not self.enabled then
                return false
            end
            local fn = self.scripts.OnClick
            if fn then
                fn(self, button or "LeftButton")
            end
            return true
        end
        -- Firing a script by hand is the stub's own affair - the client has no
        -- Button:Enter or Button:Leave - so both sit on the stub shelf.
        function f.stub.Enter()
            local fn = f.scripts.OnEnter
            if fn then
                fn(f)
            end
        end
        function f.stub.Leave()
            local fn = f.scripts.OnLeave
            if fn then
                fn(f)
            end
        end
    end

    -- DropdownButton is an intrinsic, so the menu surface comes with the KIND
    -- and not with any template (Core/Widget/Intrinsic/DropdownButton.lua:9).
    -- There is exactly one menu implementation here, attachDropdownButton
    -- above, so a dropdown built with a template and one built without cannot
    -- drift apart. What is modelled is the CONTRACT the panels use and nothing
    -- else: SetupMenu takes a generator of (dropdown, rootDescription); the
    -- root description takes a tag and radio entries of (text, isSelected,
    -- setSelected).
    if kind == "DropdownButton" then
        attachDropdownButton(f)
    end

    -- EditBox's own surface (Core/Widget/Frame/EditBox.lua): SetText :347,
    -- GetText, SetTextColor :354 and the four font setters at :262, :266, :285
    -- and :289 - an EditBox is the one frame besides a FontString that has
    -- them, and it does NOT have SetNonSpaceWrap or SetWordWrap.
    if kind == "EditBox" then
        f.maxLetters = 0
        function f:GetText()
            return self.text
        end
        function f:SetTextColor(red, green, blue, alpha)
            self.textColor = { red, green, blue, alpha }
        end
        for _, name in ipairs(IGNORED_EDITBOX_FONT_METHODS) do
            f[name] = function() end
        end
        function f:SetMaxLetters(value)
            self.maxLetters = tonumber(value) or 0
        end
        function f:GetMaxLetters()
            return self.maxLetters
        end
        -- The one behaviour the paste box depends on: 0 means no limit, and any
        -- other value truncates.
        function f:SetText(value)
            value = value == nil and "" or tostring(value)
            if self.maxLetters and self.maxLetters > 0 then
                value = value:sub(1, self.maxLetters)
            end
            self.text = value
            local fn = self.scripts.OnTextChanged
            if fn then
                fn(self, false)
            end
        end
        function f:GetNumLetters()
            return #self.text
        end
        function f:Insert(value)
            self:SetText(self.text .. tostring(value))
        end
        function f:SetMultiLine(value)
            self.multiLine = value and true or false
        end
        function f:IsMultiLine()
            return self.multiLine
        end
        function f:SetAutoFocus(value)
            self.autoFocus = value
        end
        function f:SetFocus()
            self.focused = true
        end
        function f:ClearFocus()
            self.focused = false
        end
        f.HighlightText = function() end
        f.SetCountInvisibleLetters = function() end
        f.SetTextInsets = function() end
    end

    attachTemplate(f, world, template)

    world.frames[#world.frames + 1] = f
    return f
end

function Stub.install()
    local world = {
        inCombat = false,
        hasSecretRestrictions = true,
        -- GetBuildInfo() on the live client, 2026-09-01 (HealperSpike SavedVariables).
        build = { "12.1.0", "69587", "Aug 27 2026", 120100, "", " " },
        locale = "enUS",
        realm = "TestRealm",
        playerName = "Tester",
        playerLevel = 90,
        -- localizedClassName, classToken, classID (UnitClass). The TOKEN is the
        -- second, and it is what C-15's character gate compares: `Restoration`
        -- is the spec name of both a Druid and a Shaman, and `DRUID` is not
        -- `SHAMAN`. Settable so a test can log an alt in.
        playerClass = { "Druid", "DRUID", 11 },
        -- localizedRaceName, englishRaceName, raceID
        playerRace = { "Zandalari Troll", "ZandalariTroll", 31 },
        region = "US",
        regionID = 1,
        addons = {
            { name = "Lootpath", title = "Lootpath", loaded = true },
            { name = "Simulationcraft", title = "SimulationCraft", loaded = false },
        },
        metadata = { Version = "0.0.0-test" },
        -- The active specialization, or nil for a client that names none.
        -- Placeholder in every particular except the shape (M2-2, M5-2).
        spec = { index = 4, id = 105, name = "Restoration", icon = 136041, role = "HEALER" },
        -- Every specialization this character's class has, which is what
        -- `GetNumSpecializations` counts and what `GetSpecializationInfo(i)`
        -- describes for an index that is not the active one (H-1, WKE-596:
        -- `ns.Companion.HealingSpecName` walks them to name the healing spec
        -- without a table of its own). Placeholders in every particular except
        -- the shape and the ROLE strings, which are Blizzard's own words
        -- (`ClubFinder.lua:827`, `Blizzard_CompactRaidFrameManager.lua:1177`,
        -- under .luals/). A test giving a class no healing spec sets this to a
        -- list without one; `{}` is a client that describes none at all.
        specs = {
            { index = 1, id = 102, name = "Balance", icon = 136096, role = "DAMAGER" },
            { index = 2, id = 103, name = "Feral", icon = 132115, role = "DAMAGER" },
            { index = 3, id = 104, name = "Guardian", icon = 132276, role = "TANK" },
            { index = 4, id = 105, name = "Restoration", icon = 136041, role = "HEALER" },
        },
        -- The keystone the character owns, or nil for one holding none, which
        -- the client answers as 0/0/0 (R-0, WKE-561). A test that wants a key
        -- sets { level = 8, challengeMapID = 542, mapID = 2664 }.
        keystone = nil,
        cursor = { 0, 0 },
        equipped = {}, -- [invSlot] = { link = , id = }
        bags = {}, -- [bagIndex] = { numSlots = , items = { [slot] = { info = , link = , id = } } }
        items = {}, -- [link] = { level = , info = {...}, instant = {...} }
        -- [guid] = link, for C_Item.GetItemLinkByGUID; a tooltip whose data
        -- carries a GUID reaches its hyperlink through this (R-0, WKE-561).
        itemLinksByGUID = {},
        -- Every itemID C_Item.RequestLoadItemDataByID was asked for, in order.
        -- The stub never answers by itself: a test that wants the data to
        -- arrive registers the item and fires ITEM_DATA_LOAD_RESULT (or
        -- GET_ITEM_INFO_RECEIVED) itself, which is how "the client answered
        -- late" and "the client never answered" are both drivable (M3-12).
        itemDataRequests = {},
        -- [itemInfo] = { specID, ... }, for C_Item.GetItemSpecInfo. Nothing is
        -- answered unless a test says so, which is the client that names no
        -- spec list at all (UX-6b).
        itemSpecs = {},
        -- Whether a texture has `SetGradient` (UX-5a, WKE-634). A test that
        -- wants a client without it sets this false before the frame is built.
        textureGradient = true,
        -- What C_Texture.GetAtlasInfo answers for. Both entries were read from
        -- Blizzard's own shipped XML under .luals/ on 2026-09-09 -
        -- `common-icon-checkmark` in Blizzard_ChromieTimeUI.xml and the
        -- Housing dashboard, `common-icon-forwardarrow` in
        -- Blizzard_RotateControlFrame.xml - so a client that has those files
        -- has these atlases. A test that wants the fallback empties the table.
        atlases = {
            ["common-icon-checkmark"] = true,
            ["common-icon-forwardarrow"] = true,
            -- The Great Vault's own selected art, from the SelectedTexture of
            -- WeeklyRewardsActivityTemplate in Blizzard's shipped
            -- Blizzard_WeeklyRewards.xml under .luals/ (read 2026-09-09).
            --
            -- V-5a (WKE-607): an entry is either `true`, which answers the
            -- default square below, or a `{ width, height }` pair that
            -- GetAtlasInfo answers with.
            --
            -- THIS one is measured: the owner read
            -- `evergreen-weeklyrewards-reward-selected` at 214 x 121 with
            -- `C_Texture.GetAtlasInfo` on his own client the night of R-2b
            -- (WKE-575), where the same atlas had been squeezed by
            -- `SetAllPoints` into a 15-point square - the same fault this issue
            -- is about, in another surface. See `spec/tooltip_spec.lua`.
            ["evergreen-weeklyrewards-reward-selected"] = { width = 214, height = 121 },
            -- M5-1b (WKE-610): Equip Now's four marks and its empty-slot
            -- frame. Every one was read from Blizzard's own shipped XML or Lua
            -- under `.luals/` on 2026-09-17, and each cite is in
            -- `Lootpath/UI/EquipPanel.lua`'s mark block. No size is given: the
            -- marks are drawn at MARK_SIZE, the size they are seen at (R-2b),
            -- so nothing here ever asks for the art's own size. A test that
            -- wants the flat-colour fallback empties the table.
            ["gficon-chest-evergreen-greatvault-collect"] = true,
            ["transmog-icon-warning-small"] = true,
            ["common-radiobutton-circle"] = true,
            ["auctionhouse-itemicon-empty"] = true,
            -- V-5 (WKE-600): the rest of the Great Vault's own art the tab
            -- draws. The two cell backgrounds are the two strings
            -- `WeeklyRewardsActivityMixin:Refresh` passes to SetAtlas; the
            -- three category atlases are the three
            -- `WeeklyRewardsMixin:OnLoad` passes to SetUpActivity; the tick is
            -- the CompletedIcon of WeeklyRewardActivityTemplate in
            -- Blizzard_WeeklyRewards.xml. All read from Blizzard's own shipped
            -- files under `.luals/` on 2026-09-16. A test that wants the
            -- fallback empties the table.
            --
            -- Their sizes are PLACEHOLDER, in the same sense as `qualityColors`
            -- further down: nobody has measured these five on a client, and no
            -- test asserts a figure - each asserts that what was DRAWN carries
            -- the ratio the client reported, whatever it reported. The pairs are
            -- shaped from the only thing that could be read here: the size of
            -- Blizzard's own frame that carries each atlas at
            -- `useAtlasSize="true"` in Blizzard_WeeklyRewards.xml - 219x126 for
            -- WeeklyRewardActivityTemplate and 326x131 for
            -- WeeklyRewardActivityTypeTemplate. The one atlas that HAS been
            -- measured came out 5 points inside its frame either way (214x121 in
            -- a 219x126 template), so a frame is a close stand-in for the art it
            -- holds - close, and not the thing itself.
            ["evergreen-weeklyrewards-reward-locked"] = { width = 219, height = 126 },
            ["evergreen-weeklyrewards-reward-unlocked"] = { width = 219, height = 126 },
            ["evergreen-weeklyrewards-category-raids"] = { width = 326, height = 131 },
            ["evergreen-weeklyrewards-category-dungeons"] = { width = 326, height = 131 },
            ["evergreen-weeklyrewards-category-world"] = { width = 326, height = 131 },
            ["activities-icon-checkmark"] = true,
        },
        -- ITEM_QUALITY_COLORS, in Blizzard's documented shape
        -- ({ r, g, b, hex }, ColorManager.lua under .luals/) with PLACEHOLDER
        -- values: the real client's quality colours are a data table this
        -- harness has no transcript of, and a test asserts that the border was
        -- tinted with the colour the client gave, never that the colour is a
        -- particular red. Quality 0..7 = Poor..Heirloom.
        qualityColors = {
            [0] = { r = 0.1, g = 0.1, b = 0.1 },
            [1] = { r = 0.2, g = 0.2, b = 0.2 },
            [2] = { r = 0.3, g = 0.3, b = 0.3 },
            [3] = { r = 0.4, g = 0.4, b = 0.4 },
            [4] = { r = 0.5, g = 0.5, b = 0.5 },
            [5] = { r = 0.6, g = 0.6, b = 0.6 },
            [6] = { r = 0.7, g = 0.7, b = 0.7 },
            [7] = { r = 0.8, g = 0.8, b = 0.8 },
        },
        -- E-1a (WKE-605): which equipment slots the client says an item can go
        -- into, keyed by item link - [link] = { 11, 12 } for a ring. It is the
        -- ONLY source GetInventoryItemsForSlot below draws on, because which
        -- slots a real client offers an item for is a data table this harness
        -- has no transcript of; a test states what the client answers and
        -- asserts what Lootpath does with it, never that a particular item
        -- belongs in a particular slot. An item with no entry here is one the
        -- client offers for no slot at all, which is the unmappable case.
        slotsForItem = {},
        bankOpen = false,
        vaultOpen = false,
        -- The upgrade vendor's window (M3-17, WKE-574). `frameOpen` is what
        -- ItemUpgradeFrame:IsShown answers; `items` is keyed by item link and
        -- carries placeholders in Blizzard's documented shapes (see the
        -- C_ItemUpgrade stub below); `calls` counts what the capture asked
        -- for; `setLinks` is every link it put in the window, in order;
        -- `current` is what the window holds now. `answersWithEvent = false`
        -- plays a client that never fires ITEM_UPGRADE_MASTER_SET_ITEM, and
        -- `errorOnSet` a client that refuses one item.
        upgrade = {
            frameOpen = false,
            items = {},
            answersWithEvent = true,
            eventDelaySeconds = 0,
            errorOnSet = nil,
            current = nil,
            setLinks = {},
            calls = { set = 0, clear = 0, canUpgrade = 0 },
        },
        reloads = 0,
        -- M3-16a (WKE-581): every StaticPopup_Show, in order, and every
        -- StaticPopup_Hide key.
        popupsShown = {},
        popupsHidden = {},
        -- `currentPeriod` and `generated` are M3-16's two extra reads
        -- (AreRewardsForCurrentRewardPeriod, HasGeneratedRewards); `interact`
        -- counts the two calls the vault capture may make, and
        -- `answerOnInteract` is how a test plays the client answering
        -- OnUIInteract with the rewards it was holding back.
        vault = {
            hasAvailable = false,
            canClaim = false,
            currentPeriod = true,
            generated = false,
            activities = {},
            links = {},
            examples = {},
            -- V-5 (WKE-600): what GetDifficultyIDForActivityTier answers,
            -- keyed by activityTierID. Empty by default, which is a client
            -- that says nothing about the tier - the answer the panel has to
            -- survive, since in the activity data a Heroic dungeon week and a
            -- Mythic one are both level 0 and only this read tells them apart.
            difficultyIDs = {},
            interact = { onUIInteract = 0, closeInteraction = 0 },
            answerOnInteract = nil,
            answerDelaySeconds = 0,
        },
        -- The currency list, in the order the client would list it, in
        -- Blizzard's documented CurrencyInfo shape (Ketho's
        -- CurrencyInfoDocumentation.lua: name, description, currencyID,
        -- isHeader, quantity, ...). Placeholders in every particular - no
        -- `/lootpath capture currencies` transcript exists yet, so no name or
        -- ID here is claimed to be a real one (WKE-544).
        currencies = {},
        -- What `GetCurrencyInfo(id)` answers, keyed by currencyID, for a
        -- currency the LIST does not show. The real client's currency tab lists
        -- only the rows of expanded headers while `GetCurrencyInfo` answers for
        -- any ID (WKE-546), and this is how a test says so. Entries left out of
        -- it still resolve out of `world.currencies` by ID, as the client's own
        -- two calls agree about anything the tab is showing.
        currencyByID = {},
        secondsUntilReset = 3600,
        difficultyNames = {},
        printed = {},
        frames = {},
        equipCalls = {},
        -- The cursor, as much of it as equipping by bag and slot needs (E-1,
        -- WKE-604). `world.heldItem` is what the cursor holds and is absent
        -- while it holds nothing, which is how it starts - `world.cursor` is
        -- already taken, by the mouse POSITION GetCursorPosition answers with.
        -- The three counters below
        -- record the calls in the order they were made, so a test can say what
        -- was picked up, what it was equipped into, and that the cursor was
        -- cleared.
        pickupCalls = {},
        equipCursorCalls = {},
        clearCursorCalls = 0,
        secrets = setmetatable({}, { __mode = "k" }),
        -- C_Timer.After runs on a fake clock a test drives with runTimers.
        now = 0,
        timers = {},
        -- The Encounter Journal. Placeholders in every particular: WKE-523's
        -- transcript is what settles the real shapes. What is modelled here is
        -- the BEHAVIOUR the adapter has to survive - loot that is out of date
        -- until EJ_LOOT_DATA_RECIEVED arrives, and journal view state that a
        -- walk must put back.
        journal = {
            numTiers = 3,
            currentTier = 1,
            tierInfo = { { "Tier One", "tierlink1" }, { "Tier Two", "tierlink2" }, { "Tier Three", "tierlink3" } },
            difficulty = 1,
            lootFilter = { 0, 0 },
            previewLevel = nil,
            previewLevelCalls = {},
            selectedInstance = nil,
            instances = { dungeons = {}, raids = {} },
            encounters = {}, -- [instanceID] = { { name, description, encounterID } }
            loot = {}, -- [instanceID] = { [difficultyID] = { EncounterJournalItemInfo } }
            validDifficulty = {}, -- [instanceID] = { [difficultyID] = boolean }
            mapTable = {},
            mapUIInfo = {}, -- [mapChallengeModeID] = { name, id, timeLimit, texture, background, mapID }
            instanceForGameMap = {}, -- [mapID] = journalInstanceID
            instanceForMap = {}, -- [mapID] = journalInstanceID
            season = 15,
            -- nil = loot is ready the moment it is selected. A number delays
            -- EJ_LOOT_DATA_RECIEVED by that many fake seconds; `false` means
            -- the event never comes at all.
            lootDelaySeconds = nil,
            lootPending = false,
            -- The SECOND stage the 2026-09-06 transcript found: the loot list
            -- is current, but the item data behind its rows is not cached, so
            -- GetLootInfoByIndex answers rows carrying only itemID,
            -- encounterID and the displayAs* flags. nil = every row is already
            -- cached; a number = the rows arrive bare and fill in that many
            -- fake seconds later, one EJ_LOOT_DATA_RECIEVED per row; false =
            -- the item data never arrives at all.
            itemDataDelaySeconds = nil,
            itemDataPending = false,
            selectCalls = {},
            lootFilterCalls = {},
        },
    }

    -- Secrets: a sentinel registered here answers issecretvalue / issecrettable.
    function world.secret(label)
        local sentinel = { secret = label or "value" }
        world.secrets[sentinel] = "value"
        return sentinel
    end
    function world.secretTable(label)
        local sentinel = { secret = label or "table" }
        world.secrets[sentinel] = "table"
        return sentinel
    end
    -- Marks a value that already exists - a string, a number - as secret and
    -- hands it straight back. The two helpers above return a fresh TABLE, so a
    -- guard that only type-checks its input passes them by accident; this one
    -- is how a test proves ns.Safe itself is doing the work (C-2).
    function world.markSecret(value)
        world.secrets[value] = "value"
        return value
    end
    function world.fireEvent(event, ...)
        for _, f in ipairs(world.frames) do
            if f.events[event] and f.scripts.OnEvent then
                f.scripts.OnEvent(f, event, ...)
            end
        end
    end
    function world.output()
        return table.concat(world.printed, "\n")
    end

    -- Drives C_Timer.After on a fake clock: fires every pending timer whose
    -- due time falls within `budgetSeconds` of now, earliest first, letting
    -- callbacks schedule more. Nothing here sleeps, so an async walk runs to
    -- completion inside a synchronous test.
    function world.runTimers(budgetSeconds)
        local deadline = world.now + (budgetSeconds or 0)
        local guard = 0
        while true do
            guard = guard + 1
            assert(guard < 100000, "stub: runaway timer loop")
            local pick
            for i = 1, #world.timers do
                local timer = world.timers[i]
                if not timer.done and (not pick or timer.at < pick.at) then
                    pick = timer
                end
            end
            if not pick or pick.at > deadline then
                return
            end
            pick.done = true
            if pick.at > world.now then
                world.now = pick.at
            end
            pick.fn()
        end
    end

    define("issecretvalue", function(value)
        return world.secrets[value] == "value"
    end)
    define("issecrettable", function(value)
        return world.secrets[value] == "table"
    end)
    define("InCombatLockdown", function()
        return world.inCombat
    end)
    define("GetBuildInfo", function()
        return unpack(world.build)
    end)
    define("GetLocale", function()
        return world.locale
    end)
    define("GetRealmName", function()
        return world.realm
    end)
    define("UnitName", function(unit)
        if unit == "player" then
            return world.playerName, nil
        end
        return nil
    end)
    define("UnitClass", function()
        return world.playerClass[1], world.playerClass[2], world.playerClass[3]
    end)
    define("UnitLevel", function(unit)
        return unit == "player" and world.playerLevel or 0
    end)
    -- UnitRace -> localizedRaceName, englishRaceName, raceID (Blizzard's exported
    -- UnitDocumentation). The English name is the one the SimC profile tokenizes.
    define("UnitRace", function(unit)
        if unit ~= "player" then
            return nil
        end
        return world.playerRace[1], world.playerRace[2], world.playerRace[3]
    end)
    define("GetCurrentRegionName", function()
        return world.region
    end)
    define("GetCurrentRegion", function()
        return world.regionID
    end)
    -- The spec pair. `world.spec` is what a test drives: nil is a client that
    -- names no specialization, which is what makes the portrait's class-icon
    -- fallback reachable headlessly (M5-2). Blizzard's annotations deprecate
    -- both globals in favour of C_SpecializationInfo, so the namespaced pair is
    -- defined over the same model and the globals are kept beside it, which is
    -- exactly the client the addon has to survive either half of.
    define("GetSpecialization", function()
        return world.spec and world.spec.index or nil
    end)
    -- How many specializations the class has, for the walk that names its
    -- healing one (H-1, WKE-596). A global and only a global: Ketho's
    -- annotations carry `GetNumSpecializations` in `Core/Data/Wiki.lua:5896`
    -- and `C_SpecializationInfo` has no twin of it, only
    -- `GetNumSpecializationsForClassID`.
    define("GetNumSpecializations", function()
        return #(world.specs or {})
    end)
    -- The active spec answers about itself whatever `world.specs` says, so a
    -- test can set `world.spec` alone and be describing a real client; any
    -- other index is described out of `world.specs`, which is the only way an
    -- addon can be told about a spec the player is not standing in.
    define("GetSpecializationInfo", function(index)
        local spec = world.spec
        if not spec or index ~= spec.index then
            spec = (world.specs or {})[index]
        end
        if not spec then
            return nil
        end
        return spec.id, spec.name, "placeholder", spec.icon, spec.role, 4
    end)
    define("C_SpecializationInfo", {
        GetSpecialization = function()
            return world.spec and world.spec.index or nil
        end,
        GetSpecializationInfo = function(index)
            return _G.GetSpecializationInfo(index)
        end,
    })
    -- CLASS_ICON_TCOORDS: the four corners of each class's circle in the shared
    -- UI-Classes-Circles sheet. Only the stub's own class (DRUID, from
    -- UnitClass above) is modelled, and the four numbers are PLACEHOLDERS like
    -- every other value here - what is tested is that the four the client gives
    -- are the four the portrait is set to, never which four they are.
    define("CLASS_ICON_TCOORDS", {
        DRUID = { 0.75, 1, 0, 0.25 },
    })
    -- Where the mouse is, in UI coordinates before the frame's own scale. The
    -- minimap drag divides by the minimap's effective scale, exactly as the
    -- client's own buttons do.
    define("GetCursorPosition", function()
        return world.cursor[1], world.cursor[2]
    end)
    -- GetDifficultyInfo(difficultyID) -> name, instanceType, ... (Blizzard's
    -- exported InstanceDocumentation via Ketho). Names here are placeholders;
    -- world.difficultyNames is what a test drives, and an empty table is a
    -- client that does not answer, which the M3-3 panel has to survive.
    define("GetDifficultyInfo", function(difficultyID)
        local name = world.difficultyNames[difficultyID]
        if not name then
            return nil
        end
        return name, "party", false, false, false, false
    end)
    -- ReloadUI: protected in combat in the real client, which is why
    -- Companion.Refresh checks InCombatLockdown before it ever gets here. The
    -- stub only counts the calls; what a reload does is the client's.
    define("ReloadUI", function()
        world.reloads = world.reloads + 1
    end)
    -- StaticPopup (M3-16a, WKE-581). The dialog table is Blizzard's global that
    -- addons add an entry to, and `StaticPopup_Show(which)` is what puts one on
    -- screen (`.luals/.../Blizzard_StaticPopup/StaticPopup.lua.annotated.lua`
    -- line 278: `StaticPopup_Show(which, text_arg1, text_arg2, data,
    -- insertedFrame, customOnHideScript)`). The stub records which keys were
    -- shown and hands the registered entry back, so a test clicks a button by
    -- calling `OnAccept` the way the real dialog does - which is the point: the
    -- client only allows `ReloadUI` from that click.
    define("StaticPopupDialogs", {})
    define("StaticPopup_Show", function(which, text_arg1, text_arg2, data)
        world.popupsShown[#world.popupsShown + 1] = {
            which = which,
            text_arg1 = text_arg1,
            text_arg2 = text_arg2,
            data = data,
        }
        return _G.StaticPopupDialogs[which]
    end)
    define("StaticPopup_Hide", function(which)
        world.popupsHidden[#world.popupsHidden + 1] = which
    end)
    -- Clicks a shown popup's button the way the client does: `OnAccept(dialog,
    -- data)`, with no dialog frame, because nothing Lootpath registers touches
    -- one. Returns false when that key was never shown.
    function world.clickPopup(which, button)
        for _, shown in ipairs(world.popupsShown) do
            if shown.which == which then
                local entry = _G.StaticPopupDialogs[which]
                local handler = entry and entry[button or "OnAccept"]
                if type(handler) == "function" then
                    handler(nil, shown.data)
                    return true
                end
                return false
            end
        end
        return false
    end
    define("debugprofilestop", function()
        return os.clock() * 1000
    end)
    define("time", os.time)
    define("date", os.date)
    -- A MODELLED clock, for the tests that have to pin what `time` and `date`
    -- do across a daylight-saving boundary (V-4, WKE-589). `os.time` and
    -- `os.date` answer for whatever timezone the machine running the suite is
    -- in - UTC inside CI's container, and Alpine carries no tzdata at all - so a
    -- fault that only shows while daylight time is in effect cannot be made red
    -- against them. `world.setClock(zone)` swaps both globals for a pair that
    -- models one zone with one daylight rule, the way C's `mktime` and
    -- `localtime` behave:
    --
    --   world.setClock({
    --       now = 1789856431,            -- what bare time() answers
    --       standard = -6 * 3600,        -- offset from UTC outside daylight time
    --       daylight = -5 * 3600,        -- offset from UTC during it
    --       isDaylight = function(epoch) return ... end,
    --   })
    --
    -- The three behaviours that matter, each checked against musl's own `date`
    -- and `mktime` under TZ=America/Chicago on 2026-09-15 (spec/stubs_spec.lua
    -- records the same three): `date("!*t")` answers UTC fields with
    -- `isdst = false`; `date("*t")` answers local fields with the instant's own
    -- `isdst`; and `time(t)` reads `t.isdst` the way `mktime` reads `tm_isdst` -
    -- `false` means "these fields are standard time", `true` means "daylight
    -- time", and ABSENT means "decide". Nothing else about a timezone is
    -- modelled: there is one rule, it applies to every year, and an hour that a
    -- transition repeats or skips resolves to the daylight reading when one
    -- exists. A test that needs more than that needs a real clock, not this.
    local function daysFromCivil(y, m, d)
        y = m <= 2 and y - 1 or y
        local era = math.floor(y / 400)
        local yoe = y - era * 400
        local mp = m > 2 and m - 3 or m + 9
        local doy = math.floor((153 * mp + 2) / 5) + d - 1
        local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
        return era * 146097 + doe - 719468
    end

    local function civilFromDays(z)
        z = z + 719468
        local era = math.floor(z / 146097)
        local doe = z - era * 146097
        local yoe =
            math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
        local y = yoe + era * 400
        local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
        local mp = math.floor((5 * doy + 2) / 153)
        local d = doy - math.floor((153 * mp + 2) / 5) + 1
        local m = mp < 10 and mp + 3 or mp - 9
        return (m <= 2 and y + 1 or y), m, d
    end

    -- The six fields read as if they were UTC. `mktime` normalises out-of-range
    -- fields and so does this: the arithmetic below never looks at a calendar.
    local function fieldsAsUTC(t)
        return daysFromCivil(t.year, t.month, t.day) * 86400 + (t.hour or 12) * 3600 + (t.min or 0) * 60 + (t.sec or 0)
    end

    function world.setClock(zone)
        world.clock = zone
        local function offsetAt(epoch)
            return zone.isDaylight(epoch) and zone.daylight or zone.standard
        end
        local function breakdown(epoch, isdst)
            local days = math.floor(epoch / 86400)
            local rest = epoch - days * 86400
            local y, m, d = civilFromDays(days)
            return {
                year = y,
                month = m,
                day = d,
                hour = math.floor(rest / 3600),
                min = math.floor(rest % 3600 / 60),
                sec = rest % 60,
                wday = (days + 4) % 7 + 1,
                yday = days - daysFromCivil(y, 1, 1) + 1,
                isdst = isdst,
            }
        end
        define("time", function(t)
            if t == nil then
                return zone.now
            end
            local fields = fieldsAsUTC(t)
            if t.isdst == false then
                return fields - zone.standard
            end
            if t.isdst == true then
                return fields - zone.daylight
            end
            local asDaylight = fields - zone.daylight
            if zone.isDaylight(asDaylight) then
                return asDaylight
            end
            return fields - zone.standard
        end)
        define("date", function(fmt, epoch)
            fmt = fmt or "%c"
            epoch = epoch or zone.now
            local utc = fmt:sub(1, 1) == "!"
            if utc then
                fmt = fmt:sub(2)
            end
            local shifted = utc and epoch or (epoch + offsetAt(epoch))
            if fmt == "*t" then
                -- `utc and false or ...` would answer the daylight flag for a
                -- UTC breakdown: false is false. Written out instead.
                local isdst = false
                if not utc then
                    isdst = zone.isDaylight(epoch)
                end
                return breakdown(shifted, isdst)
            end
            -- Every other format is os.date's own, applied in UTC to the
            -- already-shifted second, so "%H:%M" reads as the modelled zone's
            -- wall clock without asking the host what its timezone is.
            return os.date("!" .. fmt, shifted)
        end)
    end
    define("print", function(...)
        local parts = {}
        for i = 1, select("#", ...) do
            parts[i] = tostring((select(i, ...)))
        end
        world.printed[#world.printed + 1] = table.concat(parts, " ")
    end)
    define("CreateFrame", function(kind, name, parent, template)
        local f = newFrame(kind, world, parent, template)
        if type(name) == "string" and name ~= "" then
            f.frameName = name
            define(name, f)
        end
        return f
    end)
    -- The ScrollBox globals the panels build on (see the block above for where
    -- each shape was read from).
    define("CreateDataProvider", newDataProvider)
    define("CreateScrollBoxListLinearView", newScrollBoxListLinearView)
    define("CreateScrollBoxLinearView", newScrollBoxListLinearView)
    define("ScrollUtil", {
        InitScrollBoxListWithScrollBar = function(scrollBox, _, view)
            scrollBox:Init(view)
        end,
        InitScrollBoxWithScrollBar = function(scrollBox, _, view)
            scrollBox:Init(view)
        end,
        RegisterScrollBoxWithScrollBar = function() end,
        AddManagedScrollBarVisibilityBehavior = function()
            return {}
        end,
    })

    define("SlashCmdList", {})
    -- The two font objects `UIPanelButtonTemplate` itself names - its NormalFont
    -- and its DisabledFont (Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml
    -- :303 and :306) - which R-6c (WKE-629) swaps to dim the Refresh button's
    -- label while the rating is being made. The client's are real Font objects
    -- (`CreateFont`, Core/Widget/UIType/Font.lua:545 and :477); nothing headless
    -- can render a glyph, so each is an identity a test can compare against and
    -- nothing more.
    define("GameFontNormalOutline", { fontName = "GameFontNormalOutline" })
    define("GameFontDisable", { fontName = "GameFontDisable" })
    define("UIParent", newFrame("Frame", world))
    define("UISpecialFrames", {})
    -- The minimap, for the launcher to hang off (M5-2). 140 points across at
    -- default scale, centred where a test puts it.
    local minimap = newFrame("Frame", world)
    minimap:SetSize(140, 140)
    minimap.center = { 0, 0 }
    minimap.shown = true
    world.minimap = minimap
    define("Minimap", minimap)

    -- The tab helpers from Blizzard_SharedXML/SharedUIPanelTemplates.lua, as
    -- far as a headless run can model them: which tab is selected is state, and
    -- the selected/deselected ARTWORK those functions also swap is a pixel
    -- question that only M3-4 can answer. PanelTabButtonTemplate carries
    -- parentArray="Tabs", which is why a tab lands in frame.Tabs.
    define("PanelTemplates_SetNumTabs", function(frame, numTabs)
        frame.numTabs = numTabs
    end)
    define("PanelTemplates_SetTab", function(frame, id)
        frame.selectedTab = id
    end)
    define("PanelTemplates_GetSelectedTab", function(frame)
        return frame.selectedTab
    end)

    -- GameTooltip: what it was told to show is recorded so a test can read the
    -- combat message back off it. Its KIND is GameTooltip, not Frame - a
    -- GameTooltip is its own widget class (Core/Widget/Frame/GameTooltip.lua:3
    -- `GameTooltip : Frame`) and every method below is one of its own
    -- (SetOwner, SetText, AddLine, SetHyperlink, SetItemByID, ClearLines). The
    -- ONE reader that is not the client's, `Text()`, is on the stub shelf.
    -- Every GameTooltip in the client answers the same six methods, so they are
    -- attached by a function rather than to the singleton: `ShoppingTooltip1`,
    -- `ShoppingTooltip2` and another addon's private tooltip are GameTooltips
    -- too, and R-2's handler is built on telling them apart from this one.
    local function attachTooltipMethods(f)
        f.lines = {}
        function f:SetOwner(owner, anchor)
            self.owner, self.anchor = owner, anchor
            self.lines = {}
        end
        function f:SetText(text)
            self.lines = { tostring(text) }
        end
        function f:AddLine(text)
            self.lines[#self.lines + 1] = tostring(text)
        end
        function f:SetHyperlink(link)
            self.hyperlink = link
            self.itemID = nil
            self.lines = { tostring(link) }
        end
        -- What a row with an id and no link is shown by: QE Live names an item
        -- by id, so the tooltip has to take one.
        function f:SetItemByID(itemID)
            self.itemID = itemID
            self.hyperlink = nil
            self.lines = { "item " .. tostring(itemID) }
        end
        function f:ClearLines()
            self.lines = {}
        end
        function f.stub.Text()
            return table.concat(f.lines, "\n")
        end
        return f
    end

    local tooltip = attachTooltipMethods(newFrame("GameTooltip", world))
    world.tooltip = tooltip
    define("GameTooltip", tooltip)
    -- The shopping compare. A FrameXML global, not an exported API, so what is
    -- modelled is only that it was asked for and on whose behalf.
    world.compareCalls = {}
    define("GameTooltip_ShowCompareItem", function(self, anchorFrame)
        world.compareCalls[#world.compareCalls + 1] = { self, anchorFrame }
    end)

    -- Blizzard's tooltip data handler, only the parts the R-0 spike (WKE-561)
    -- touches, each read from the shipped source under
    -- `.luals/vscode-wow-api/Annotations/FrameXML/.../Blizzard_SharedXMLGame/Tooltip/`:
    --
    --   TooltipDataHandler.lua:199  TooltipDataProcessor.AddTooltipPostCall(type, func)
    --   TooltipDataHandler.lua:298  the call: func(tooltip, tooltipData)
    --   TooltipUtil.lua:9           GetDisplayedItem(tooltip) -> name, hyperlink, id
    --
    -- Only AddTooltipPostCall is modelled: the file also declares
    -- AddTooltipPreCall, AddLinePreCall and AddLinePostCall and NO remover of
    -- any kind, which is the fact the spike is built around, so a stub that
    -- offered one would be a superset of the client.
    world.tooltipPostCalls = {}

    -- TooltipDataHandlerMixin's two questions. Mixed into tooltips only, which
    -- is where the real client mixes it in.
    local function attachTooltipData(f, name)
        f.frameName = name
        function f:IsTooltipType(dataType)
            return self.tooltipDataType == dataType
        end
        function f:GetPrimaryTooltipData()
            return self.tooltipData
        end
        return f
    end

    attachTooltipData(tooltip, "GameTooltip")

    -- A second named tooltip, so a test can prove the spike counts by frame
    -- the way the owner's client will (ItemRefTooltip, Baganator's own, ...).
    function world.newTooltip(name)
        return attachTooltipData(attachTooltipMethods(newFrame("GameTooltip", world)), name)
    end

    define("TooltipDataProcessor", {
        AllTypes = "ALL",
        AddTooltipPostCall = function(dataType, func)
            local list = world.tooltipPostCalls[dataType] or {}
            world.tooltipPostCalls[dataType] = list
            list[#list + 1] = func
        end,
    })

    define("TooltipUtil", {
        GetDisplayedItem = function(displayed)
            if displayed:IsTooltipType(Enum.TooltipDataType.Item) then
                local data = displayed:GetPrimaryTooltipData()
                local hyperlink
                if data.guid then
                    hyperlink = C_Item.GetItemLinkByGUID(data.guid)
                elseif data.hyperlink then
                    hyperlink = data.hyperlink
                end
                if hyperlink then
                    local name = C_Item.GetItemInfo(hyperlink)
                    return name, hyperlink, data.id
                end
            end
        end,
    })

    -- One item tooltip, shown: the data is set and every registered post-call
    -- runs against it, in the order Blizzard runs them.
    function world.showItemTooltip(data, frame)
        local shown = frame or tooltip
        shown.tooltipDataType = Enum.TooltipDataType.Item
        shown.tooltipData = data or {}
        for _, fn in ipairs(world.tooltipPostCalls[Enum.TooltipDataType.Item] or {}) do
            fn(shown, shown.tooltipData)
        end
        return shown
    end

    -- The Settings API, from Blizzard's shipped Blizzard_Settings.lua (read
    -- 2026-09-06). Only the six calls the options page makes are modelled, and
    -- what was registered is recorded in world.settings.
    world.settings = {
        categories = {},
        settings = {},
        dropdowns = {},
        sliders = {},
        checkboxes = {},
        opened = {},
    }
    local nextCategoryID = 0
    define("Settings", {
        VarType = { Boolean = "boolean", String = "string", Number = "number" },
        RegisterVerticalLayoutCategory = function(name)
            nextCategoryID = nextCategoryID + 1
            local id = nextCategoryID
            local category = {
                name = name,
                GetID = function()
                    return id
                end,
            }
            world.settings.categories[#world.settings.categories + 1] = category
            return category
        end,
        RegisterProxySetting = function(category, variable, variableType, name, default, getValue, setValue)
            local setting = {
                category = category,
                variable = variable,
                variableType = variableType,
                name = name,
                default = default,
                GetValue = getValue,
                SetValue = setValue,
            }
            world.settings.settings[variable] = setting
            return setting
        end,
        CreateControlTextContainer = function()
            local container = { data = {} }
            function container:Add(value, label, tooltipText)
                self.data[#self.data + 1] = { value = value, label = label, tooltip = tooltipText }
            end
            function container:GetData()
                return self.data
            end
            return container
        end,
        CreateDropdown = function(category, setting, options, tooltipText)
            local entry = { category = category, setting = setting, options = options, tooltip = tooltipText }
            world.settings.dropdowns[#world.settings.dropdowns + 1] = entry
            return entry
        end,
        RegisterAddOnCategory = function(category)
            category.registered = true
        end,
        OpenToCategory = function(categoryID)
            world.settings.opened[#world.settings.opened + 1] = categoryID
        end,
        -- CreateSliderOptions' `steps` is (maxValue - minValue) / rate, and its
        -- SetLabelFormatter takes a MinimalSliderWithSteppersMixin.Label value
        -- (Blizzard_Settings.lua:307, MinimalSlider.lua:40).
        CreateSliderOptions = function(minValue, maxValue, rate)
            local options = {
                minValue = minValue or 0,
                maxValue = maxValue or 1,
                steps = rate and ((maxValue - minValue) / rate) or 100,
            }
            function options:SetLabelFormatter(labelType, formatter)
                self.formatters = self.formatters or {}
                self.formatters[labelType] = formatter
            end
            return options
        end,
        CreateSlider = function(category, setting, options, tooltipText)
            local entry = { category = category, setting = setting, options = options, tooltip = tooltipText }
            world.settings.sliders[#world.settings.sliders + 1] = entry
            return entry
        end,
        CreateCheckbox = function(category, setting, tooltipText)
            local entry = { category = category, setting = setting, tooltip = tooltipText }
            world.settings.checkboxes[#world.settings.checkboxes + 1] = entry
            return entry
        end,
    })
    define("MinimalSliderWithSteppersMixin", {
        Label = { Left = 1, Right = 2, Top = 3, Min = 4, Max = 5 },
    })

    -- FrameXML constants (Blizzard_FrameXMLBase/Constants.lua via Ketho).
    define("INVSLOT_FIRST_EQUIPPED", 1)
    define("INVSLOT_LAST_EQUIPPED", 19)
    define("NUM_BAG_SLOTS", 4)
    define("NUM_TOTAL_EQUIPPED_BAG_SLOTS", 5)

    -- Enum.BagIndex as the 12.1.0 client enumerated it (transcript 2026-09-05,
    -- capture env); the other enums from Blizzard's docs via Ketho.
    define("Enum", {
        BagIndex = {
            Accountbanktab = -3,
            Characterbanktab = -2,
            Keyring = -1,
            Backpack = 0,
            Bag_1 = 1,
            Bag_2 = 2,
            Bag_3 = 3,
            Bag_4 = 4,
            ReagentBag = 5,
            CharacterBankTab_1 = 6,
            CharacterBankTab_2 = 7,
            CharacterBankTab_3 = 8,
            CharacterBankTab_4 = 9,
            CharacterBankTab_5 = 10,
            CharacterBankTab_6 = 11,
            AccountBankTab_1 = 12,
            AccountBankTab_2 = 13,
            AccountBankTab_3 = 14,
            AccountBankTab_4 = 15,
            AccountBankTab_5 = 16,
        },
        BankType = { Character = 0, Guild = 1, Account = 2 },
        -- Enum.WeeklyRewardChestThresholdType exactly as the 12.1.0 client
        -- enumerated it (transcript 2026-09-05, capture env): AlsoReceive and
        -- Concession were missing here until M3-3, and the vault's Concession
        -- row (type 5) is a real row in both committed transcripts.
        WeeklyRewardChestThresholdType = {
            None = 0,
            Activities = 1,
            RankedPvP = 2,
            Raid = 3,
            AlsoReceive = 4,
            Concession = 5,
            World = 6,
        },
        CachedRewardType = { None = 0, Item = 1, Currency = 2, Quest = 3 },
        -- The three the tooltip spike names, with the values Blizzard's own
        -- enum carries (Ketho's Annotations/Core/Data/Enum.lua:8654). The real
        -- enum has 28 members; a subset is modelled, never a member the client
        -- does not have. Item = 0, which is why nothing here tests it for truth.
        TooltipDataType = { Item = 0, Spell = 1, Unit = 2 },
        ItemQuality = { Poor = 0, Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 },
    })

    local libs = {
        ["AceDB-3.0"] = {
            New = function(_, svName, defaults)
                local db = deepcopy(defaults or {})
                db.sv = svName
                world.db = db
                return db
            end,
        },
    }
    define("LibStub", function(name, silent)
        local lib = libs[name]
        if not lib and not silent then
            error("stub: no library " .. tostring(name))
        end
        return lib
    end)

    define("C_AddOns", {
        GetNumAddOns = function()
            return #world.addons
        end,
        GetAddOnInfo = function(index)
            local a = world.addons[index]
            if not a then
                return nil
            end
            return a.name, a.title, a.notes, a.loadable ~= false, a.reason, "INSECURE"
        end,
        IsAddOnLoaded = function(indexOrName)
            for i, a in ipairs(world.addons) do
                if i == indexOrName or a.name == indexOrName then
                    return a.loaded, a.loaded
                end
            end
            return false, false
        end,
        GetAddOnMetadata = function(_, field)
            return world.metadata[field]
        end,
    })

    define("C_Secrets", {
        HasSecretRestrictions = function()
            return world.hasSecretRestrictions
        end,
    })

    define("GetInventoryItemLink", function(unit, slot)
        local e = unit == "player" and world.equipped[slot]
        return e and e.link or nil
    end)
    define("GetInventoryItemID", function(unit, slot)
        local e = unit == "player" and world.equipped[slot]
        return e and e.id or nil
    end)
    -- E-1a (WKE-605). Blizzard's own two halves of "which slot does this go
    -- in", both read under .luals/ on 2026-09-17 and modelled here, not
    -- invented: the packing constants are Blizzard_FrameXMLBase/Constants.lua
    -- :146-149, the unpacking is Blizzard_FrameXML/Shared/EquipmentManager.lua
    -- :1-29 line for line, and GetInventoryItemsForSlot's contract is
    -- Wiki.lua:5064-5067 (it FILLS `returnTable` with [packedLocation] = itemID
    -- for every bag or bank item that can be equipped in `slot`), the way
    -- PaperDollFrame.lua:2064-2066 calls it.
    -- The client's `bit` library (LuaJIT's, which is what Blizzard's own
    -- EquipmentManager.lua:7-21 calls). Lua 5.1 here has none, so the three
    -- operations those lines use are modelled arithmetically over the
    -- non-negative integers this packing is made of.
    define("bit", {
        band = function(a, b)
            local result, place = 0, 1
            while a > 0 and b > 0 do
                if a % 2 == 1 and b % 2 == 1 then
                    result = result + place
                end
                a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2
            end
            return result
        end,
        lshift = function(a, n)
            return a * (2 ^ n)
        end,
        rshift = function(a, n)
            return math.floor(a / (2 ^ n))
        end,
    })
    define("ITEM_INVENTORY_LOCATION_PLAYER", 0x00100000)
    define("ITEM_INVENTORY_LOCATION_BAGS", 0x00200000)
    define("ITEM_INVENTORY_LOCATION_BANK", 0x00400000)
    define("ITEM_INVENTORY_BAG_BIT_OFFSET", 8)
    define("EquipmentManager_GetLocationData", function(location)
        local data = {}
        if location < 0 then
            return data
        end
        data.isPlayer = bit.band(location, ITEM_INVENTORY_LOCATION_PLAYER) ~= 0
        data.isBank = bit.band(location, ITEM_INVENTORY_LOCATION_BANK) ~= 0
        data.isBags = bit.band(location, ITEM_INVENTORY_LOCATION_BAGS) ~= 0
        data.slot = location
        if data.isPlayer then
            data.slot = data.slot - ITEM_INVENTORY_LOCATION_PLAYER
        elseif data.isBank then
            data.slot = data.slot - ITEM_INVENTORY_LOCATION_BANK
        end
        if data.isBags then
            data.slot = data.slot - ITEM_INVENTORY_LOCATION_BAGS
            data.bag = bit.rshift(data.slot, ITEM_INVENTORY_BAG_BIT_OFFSET)
            data.slot = data.slot - bit.lshift(data.bag, ITEM_INVENTORY_BAG_BIT_OFFSET)
        end
        return data
    end)
    define("GetInventoryItemsForSlot", function(slot, returnTable)
        returnTable = returnTable or {}
        for bag, contents in pairs(world.bags) do
            for slotIndex, item in pairs(contents.items or {}) do
                local fits = false
                for _, candidate in ipairs(world.slotsForItem[item.link] or {}) do
                    if candidate == slot then
                        fits = true
                    end
                end
                if fits and bag >= 0 then
                    local packed = ITEM_INVENTORY_LOCATION_BAGS
                        + bit.lshift(bag, ITEM_INVENTORY_BAG_BIT_OFFSET)
                        + slotIndex
                    returnTable[packed] = item.id
                end
            end
        end
        return returnTable
    end)

    define("ItemLocation", {
        CreateFromEquipmentSlot = function(_, slot)
            return { equipmentSlotIndex = slot }
        end,
        -- M3-17 (WKE-574): the upgrade capture asks about bag items too, and
        -- Blizzard's own upgrade flyout builds its locations the same two ways.
        CreateFromBagAndSlot = function(_, bag, slot)
            return { bagID = bag, slotIndex = slot }
        end,
    })

    define("C_Item", {
        GetDetailedItemLevelInfo = function(link)
            local item = world.items[link]
            if not item then
                return nil
            end
            if item.detailed then
                return unpack(item.detailed, 1, item.detailed.n or 3)
            end
            return item.level, false, item.level
        end,
        GetItemInfo = function(link)
            local item = world.items[link]
            if not item or not item.info then
                return nil
            end
            -- 18 returns on 12.1.0 (transcript 2026-09-05); replayed tables carry n.
            return unpack(item.info, 1, item.info.n or #item.info)
        end,
        GetItemInfoInstant = function(link)
            local item = world.items[link]
            if not item or not item.instant then
                return nil
            end
            return unpack(item.instant, 1, 7)
        end,
        -- Blizzard's exported C_Item.GetItemLinkByGUID(itemGUID) -> itemLink?
        -- (ItemDocumentation.lua:286). TooltipUtil.GetDisplayedItem takes this
        -- branch for a tooltip whose data carries a GUID, which is how a bag
        -- hover reaches a hyperlink.
        GetItemLinkByGUID = function(guid)
            return world.itemLinksByGUID[guid]
        end,
        GetCurrentItemLevel = function(location)
            local e = world.equipped[location.equipmentSlotIndex]
            local item = e and world.items[e.link]
            return item and item.level or nil
        end,
        EquipItemByName = function(itemInfo, dstSlot)
            world.equipCalls[#world.equipCalls + 1] = { itemInfo, dstSlot }
        end,
        -- Blizzard's exported C_Item.RequestLoadItemDataByID(itemInfo): asks
        -- the client to load an item's data; answered by ITEM_DATA_LOAD_RESULT
        -- (itemID, success). Recorded, never answered here.
        RequestLoadItemDataByID = function(itemID)
            world.itemDataRequests[#world.itemDataRequests + 1] = itemID
        end,
        -- Blizzard's exported C_Item.GetItemSpecInfo(itemInfo) -> specTable
        -- (number[], MayReturnNothing; ItemDocumentation.lua:346-349). The
        -- list is world.itemSpecs' own, handed over as a fresh table.
        GetItemSpecInfo = function(itemInfo)
            local specs = world.itemSpecs and world.itemSpecs[itemInfo]
            if specs == nil then
                return nil
            end
            local copy = {}
            for index, id in ipairs(specs) do
                copy[index] = id
            end
            return copy
        end,
        -- Blizzard's exported C_Item.GetItemQualityColor(quality) -> r, g, b,
        -- hex. The values are world.qualityColors' placeholders.
        GetItemQualityColor = function(quality)
            local color = world.qualityColors[quality]
            if not color then
                return nil
            end
            return color.r, color.g, color.b, "|cffffffff"
        end,
    })

    -- ITEM_QUALITY_COLORS and the accessor Blizzard's own item buttons go
    -- through (ColorManager.GetColorDataForItemQuality, read under .luals/ on
    -- 2026-09-09: it returns the table's entry and nil for an unknown
    -- quality). Both read the same placeholders, so a test can take either
    -- one away and see the widget fall through to the next.
    define("ITEM_QUALITY_COLORS", world.qualityColors)
    define("ColorManager", {
        GetColorDataForItemQuality = function(quality)
            return world.qualityColors[quality]
        end,
    })

    -- CreateColor(r, g, b, a) -> colorRGBA (Blizzard_SharedXML/Color.lua:19-25,
    -- under .luals/). The four fields ColorRGBData and ColorRGBAData name (:3-10)
    -- and ColorMixin:GetRGBA (:44-49), and nothing else of the mixin (UX-5a).
    define("CreateColor", function(red, green, blue, alpha)
        return {
            r = red,
            g = green,
            b = blue,
            a = alpha,
            GetRGBA = function(self)
                return self.r, self.g, self.b, self.a
            end,
        }
    end)

    -- C_Texture.GetAtlasInfo(atlas) -> AtlasInfo, or nil for an atlas this
    -- client does not have. Two halves matter since V-5a (WKE-607): whether the
    -- client has it, and how big the art is - `width` and `height` are fields of
    -- Blizzard's own AtlasInfo (Ketho, TextureUtilsDocumentation.lua). An entry
    -- written as `true` answers a 16-square, which is what every atlas answered
    -- before sizes were asked for.
    define("C_Texture", {
        GetAtlasInfo = function(atlas)
            local entry = world.atlases[atlas]
            if not entry then
                return nil
            end
            if type(entry) ~= "table" then
                return { file = atlas, width = 16, height = 16 }
            end
            return { file = atlas, width = entry.width, height = entry.height }
        end,
    })

    -- The string Blizzard's own journal draws while an item's data is on its
    -- way (RETRIEVING_ITEM_INFO, a FrameXML global).
    define("RETRIEVING_ITEM_INFO", "Retrieving item information")

    define("C_Container", {
        GetContainerNumSlots = function(bag)
            local b = world.bags[bag]
            return b and b.numSlots or 0
        end,
        GetContainerNumFreeSlots = function(bag)
            local b = world.bags[bag]
            if not b then
                return 0, 0
            end
            local used = 0
            for _ in pairs(b.items or {}) do
                used = used + 1
            end
            return b.numSlots - used, 0
        end,
        GetContainerItemInfo = function(bag, slot)
            local b = world.bags[bag]
            local it = b and b.items and b.items[slot]
            return it and it.info and deepcopy(it.info) or nil
        end,
        GetContainerItemLink = function(bag, slot)
            local b = world.bags[bag]
            local it = b and b.items and b.items[slot]
            return it and it.link or nil
        end,
        GetContainerItemID = function(bag, slot)
            local b = world.bags[bag]
            local it = b and b.items and b.items[slot]
            return it and it.id or nil
        end,
        -- Blizzard's exported C_Container.PickupContainerItem(containerIndex,
        -- slotIndex) (ContainerDocumentation.lua:159-162): no return value, it
        -- puts that slot's item on the cursor. Here it records the call and
        -- picks up whatever the replayed bags hold in that slot - nothing, when
        -- the slot is empty - so a test can tell a pickup of the right copy
        -- from a pickup of nothing.
        PickupContainerItem = function(bag, slot)
            local b = world.bags[bag]
            local it = b and b.items and b.items[slot]
            world.pickupCalls[#world.pickupCalls + 1] = { bag, slot, it and it.link or nil }
            world.heldItem = it and { bag = bag, slot = slot, link = it.link } or nil
        end,
    })

    -- The two cursor globals, from Blizzard's exported GameCursorDocumentation
    -- (ClearCursor :2-3, EquipCursorItem(slot) :30-32). Neither returns
    -- anything. EquipCursorItem records what the cursor held and the slot it
    -- was sent to and empties the cursor; what the real client does when the
    -- equip is refused is not modelled, because nothing here can know it.
    define("ClearCursor", function()
        world.clearCursorCalls = world.clearCursorCalls + 1
        world.heldItem = nil
    end)
    define("EquipCursorItem", function(slot)
        world.equipCursorCalls[#world.equipCursorCalls + 1] = {
            slot = slot,
            bag = world.heldItem and world.heldItem.bag or nil,
            slotIndex = world.heldItem and world.heldItem.slot or nil,
            link = world.heldItem and world.heldItem.link or nil,
        }
        world.heldItem = nil
    end)

    -- `hooksecurefunc`, in both the shapes Blizzard's own FrameXML declares
    -- (Core/Global/FrameXMLUtil.lua): `hooksecurefunc(functionName, hook)` for
    -- a global and `hooksecurefunc(table, functionName, hook)` for a method.
    -- The hook runs AFTER the original with the same arguments and its return
    -- value is thrown away, which is the whole of the contract R-2's bag
    -- adapter is built on. Nothing about taint is modelled: headless there is
    -- none, and a stub that pretended otherwise would be a stub that lies.
    world.secureHooks = {}
    define("hooksecurefunc", function(a, b, c)
        local holder, name, hook
        if type(a) == "table" then
            holder, name, hook = a, b, c
        else
            holder, name, hook = _G, a, b
        end
        local original = holder[name]
        assert(type(original) == "function", "hooksecurefunc: no function " .. tostring(name))
        assert(type(hook) == "function", "hooksecurefunc: hook is not a function")
        world.secureHooks[#world.secureHooks + 1] = { holder = holder, name = name, hook = hook }
        holder[name] = function(...)
            local results = { original(...) }
            hook(...)
            return unpack(results)
        end
    end)

    -- Blizzard's container frames, only the three things R-2's Blizzard bag
    -- adapter touches, each read from
    -- `.luals/.../Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua`:
    --
    --   ContainerFrameMixin:UpdateItems()             line 1030
    --   BaseContainerFrameMixin:EnumerateValidItems() line 522, which returns
    --       `iterator, self, 0` over `container.Items` up to `GetBagSize()`
    --   ContainerFrameMixin:GetBagID()                line 759, `self:GetID()`
    --
    -- `UpdateItems` here does nothing but exist to be hooked: what the real one
    -- does to a button is Blizzard's business and no test of Lootpath's asks
    -- about it. Everything else the mixin declares is deliberately absent.
    local function containerIterator(container, index)
        index = index + 1
        if index <= container:GetBagSize() then
            return index, container.Items[index]
        end
    end
    define("ContainerFrameMixin", {
        UpdateItems = function() end,
        GetBagID = function(self)
            return self:GetID()
        end,
        GetBagSize = function(self)
            return self.size or 0
        end,
        SetBagSize = function(self, size)
            self.size = size
        end,
        EnumerateValidItems = function(self)
            return containerIterator, self, 0
        end,
    })

    world.containerFrames = {}

    -- One bag frame with `slots` item buttons, the way the client builds one:
    -- the frame's ID is the bag, each button's ID is the slot, and both answer
    -- through the mixin rather than through a field of their own.
    function world.newContainerFrame(bagID, slots)
        local frame = newFrame("Frame", world)
        for name, fn in pairs(ContainerFrameMixin) do
            frame[name] = fn
        end
        frame:SetID(bagID)
        frame:SetBagSize(slots)
        frame.Items = {}
        for slot = 1, slots do
            local button = newFrame("Button", world)
            button:SetID(slot)
            button.GetBagID = function()
                return bagID
            end
            frame.Items[slot] = button
        end
        frame:Show()
        world.containerFrames[#world.containerFrames + 1] = frame
        return frame
    end

    -- ContainerFrame.lua:386 walks the open frames through this global.
    define("ContainerFrameUtil_EnumerateContainerFrames", function()
        local index = 0
        return function()
            index = index + 1
            local frame = world.containerFrames[index]
            if frame then
                return index, frame
            end
        end
    end)

    -- Transcript 2026-09-05: Character and Account answer true only while the
    -- bank frame is open; Guild is false either way.
    define("C_Bank", {
        CanViewBank = function(bankType)
            return world.bankOpen and bankType ~= 1
        end,
        CanUseBank = function(bankType)
            return world.bankOpen and bankType ~= 1
        end,
        CanPurchaseBankTab = function()
            return false
        end,
        HasMaxBankTabs = function()
            return false
        end,
    })
    local bankFrame = newFrame("Frame", world)
    function bankFrame.IsShown()
        return world.bankOpen
    end
    define("BankFrame", bankFrame)

    -- C_WeeklyRewards. Only the nine calls Captures.lua's VAULT_FUNCTION_NAMES
    -- and Modules/Vault.lua's FUNCTION_NAMES list; `ClaimReward` and
    -- `SelectReward` are absent on purpose, so a test would fail rather than
    -- silently pass if anything ever reached for one.
    --
    -- M3-16 (WKE-557): `world.vault.interact` records what the capture asked
    -- for - `{ onUIInteract = n, closeInteraction = n }` - and
    -- `world.vault.answerOnInteract` is the client answering: when it is set,
    -- OnUIInteract installs those activities and links and fires
    -- WEEKLY_REWARDS_UPDATE after `world.vault.answerDelaySeconds`. Left nil,
    -- the update never fires and the capture times out, which is the other
    -- transcript the tests need.
    define("C_WeeklyRewards", {
        HasAvailableRewards = function()
            return world.vault.hasAvailable
        end,
        CanClaimRewards = function()
            return world.vault.canClaim
        end,
        AreRewardsForCurrentRewardPeriod = function()
            return world.vault.currentPeriod
        end,
        HasGeneratedRewards = function()
            return world.vault.generated
        end,
        GetActivities = function()
            return deepcopy(world.vault.activities)
        end,
        GetDifficultyIDForActivityTier = function(activityTierID)
            return world.vault.difficultyIDs[activityTierID]
        end,
        GetItemHyperlink = function(itemDBID)
            return world.vault.links[itemDBID]
        end,
        GetExampleRewardItemHyperlinks = function(id)
            local ex = world.vault.examples[id]
            if ex then
                return unpack(ex)
            end
            return nil
        end,
        OnUIInteract = function()
            world.vault.interact.onUIInteract = world.vault.interact.onUIInteract + 1
            local answer = world.vault.answerOnInteract
            if not answer then
                return
            end
            _G.C_Timer.After(world.vault.answerDelaySeconds or 0, function()
                world.vault.activities = answer.activities or world.vault.activities
                for dbid, link in pairs(answer.links or {}) do
                    world.vault.links[dbid] = link
                end
                for id, ex in pairs(answer.examples or {}) do
                    world.vault.examples[id] = ex
                end
                world.fireEvent("WEEKLY_REWARDS_UPDATE")
            end)
        end,
        CloseInteraction = function()
            world.vault.interact.closeInteraction = world.vault.interact.closeInteraction + 1
        end,
    })
    local vaultFrame = newFrame("Frame", world)
    function vaultFrame.IsShown()
        return world.vaultOpen
    end
    define("WeeklyRewardsFrame", vaultFrame)

    -- C_ItemUpgrade (M3-17, WKE-574). Only the seven reads and one setter
    -- Captures.lua's UPGRADE_FUNCTION_NAMES lists; `UpgradeItem`,
    -- `SetItemUpgradeFromCursorItem` and `CloseItemUpgrade` are absent on
    -- purpose, so a test would fail rather than silently pass if anything ever
    -- reached for one.
    --
    -- The window holds one item at a time, exactly as the client's does:
    -- `SetItemUpgradeFromLocation` resolves a location back to a link and every
    -- read answers for THAT link, so a capture that reads without setting, or
    -- that clears too early, gets nothing rather than the previous item's cost.
    -- `world.upgrade.answersWithEvent = false` is the client that never fires
    -- ITEM_UPGRADE_MASTER_SET_ITEM, which is the other transcript the tests
    -- need. Every field of every entry in `world.upgrade.items` is a
    -- PLACEHOLDER in Blizzard's documented shapes (ItemUpgradeDocumentation.lua
    -- ItemUpgradeItemInfo / ItemUpgradeLevelInfo / ItemUpgradeCurrencyCost):
    -- no `/lootpath capture upgrade` transcript exists yet, so no cost,
    -- currency ID or level here is claimed to be a real one.
    local function upgradeLinkAt(location)
        if type(location) ~= "table" then
            return nil
        end
        if location.equipmentSlotIndex then
            local e = world.equipped[location.equipmentSlotIndex]
            return e and e.link or nil
        end
        local b = world.bags[location.bagID]
        local it = b and b.items and b.items[location.slotIndex]
        return it and it.link or nil
    end
    define("C_ItemUpgrade", {
        CanUpgradeItem = function(location)
            local link = upgradeLinkAt(location)
            local entry = link and world.upgrade.items[link]
            world.upgrade.calls.canUpgrade = world.upgrade.calls.canUpgrade + 1
            return (entry and entry.canUpgrade) == true
        end,
        SetItemUpgradeFromLocation = function(location)
            local link = upgradeLinkAt(location)
            world.upgrade.calls.set = world.upgrade.calls.set + 1
            world.upgrade.setLinks[#world.upgrade.setLinks + 1] = link
            if world.upgrade.errorOnSet == link then
                error("the client refused this item")
            end
            world.upgrade.current = link
            if world.upgrade.answersWithEvent then
                _G.C_Timer.After(world.upgrade.eventDelaySeconds or 0, function()
                    world.fireEvent("ITEM_UPGRADE_MASTER_SET_ITEM")
                end)
            end
        end,
        ClearItemUpgrade = function()
            world.upgrade.calls.clear = world.upgrade.calls.clear + 1
            world.upgrade.current = nil
        end,
        GetItemHyperlink = function()
            return world.upgrade.current
        end,
        GetItemUpgradeItemInfo = function()
            local entry = world.upgrade.current and world.upgrade.items[world.upgrade.current]
            return entry and deepcopy(entry.info) or nil
        end,
        GetItemUpgradeCurrentLevel = function()
            local entry = world.upgrade.current and world.upgrade.items[world.upgrade.current]
            if not entry or not entry.currentLevel then
                return nil
            end
            return entry.currentLevel[1], entry.currentLevel[2]
        end,
        GetHighWatermarkForItem = function(itemInfo)
            local entry = world.upgrade.items[itemInfo]
            if not entry or not entry.highWatermark then
                return nil
            end
            return entry.highWatermark[1], entry.highWatermark[2]
        end,
    })
    local upgradeFrame = newFrame("Frame", world)
    function upgradeFrame.IsShown()
        return world.upgrade.frameOpen
    end
    define("ItemUpgradeFrame", upgradeFrame)

    -- C_CurrencyInfo. Only the three read-only calls Captures.lua and
    -- Modules/Currencies.lua name; the namespace's transfer calls are absent
    -- here on purpose, so a test would fail rather than silently pass if
    -- anything ever reached for one.
    define("C_CurrencyInfo", {
        GetCurrencyListSize = function()
            return #world.currencies
        end,
        GetCurrencyListInfo = function(index)
            local entry = world.currencies[index]
            if not entry then
                return nil
            end
            -- A copy of a secret table is not itself secret, so an entry the
            -- test registered as one is handed back as it stands. Everything
            -- else is copied, as C_WeeklyRewards.GetActivities is.
            if world.secrets[entry] then
                return entry
            end
            return deepcopy(entry)
        end,
        GetCurrencyInfo = function(currencyID)
            local hidden = world.currencyByID[currencyID]
            if hidden then
                if world.secrets[hidden] then
                    return hidden
                end
                return deepcopy(hidden)
            end
            for _, entry in ipairs(world.currencies) do
                if entry.currencyID == currencyID then
                    return deepcopy(entry)
                end
            end
            return nil
        end,
    })

    define("C_DateAndTime", {
        GetSecondsUntilWeeklyReset = function()
            return world.secondsUntilReset
        end,
    })

    define("C_Timer", {
        After = function(delay, fn)
            world.timers[#world.timers + 1] = { at = world.now + (tonumber(delay) or 0), fn = fn }
        end,
    })

    -- DifficultyUtil.ID, from Blizzard's shipped DifficultyUtil.lua (the
    -- annotated FrameXML source under .luals, lines 3-21), not the wiki.
    define("DifficultyUtil", {
        ID = {
            DungeonNormal = 1,
            DungeonHeroic = 2,
            DungeonChallenge = 8,
            DungeonMythic = 23,
            DungeonTimewalker = 24,
            PrimaryRaidNormal = 14,
            PrimaryRaidHeroic = 15,
            PrimaryRaidMythic = 16,
            PrimaryRaidLFR = 17,
        },
        -- V-5 (WKE-600): what Blizzard's own vault frame asks for a Raids row's
        -- unlocked text, at the level the client reported. It reads the same
        -- `world.difficultyNames` GetDifficultyInfo above does - one table, so
        -- a test that names a difficulty names it for both - and an empty one
        -- is a client that does not answer, which the panel has to survive.
        GetDifficultyName = function(difficultyID)
            return world.difficultyNames[difficultyID]
        end,
    })

    -- The Encounter Journal. Selecting an instance or a difficulty starts the
    -- client fetching loot: until it arrives EJ_IsLootListOutOfDate answers
    -- true and EJ_GetNumLoot answers 0, exactly the behaviour Blizzard's own
    -- journal codes around. world.journal.lootDelaySeconds decides how that
    -- resolves: nil = immediately, a number = after that many fake seconds and
    -- an EJ_LOOT_DATA_RECIEVED, false = never.
    local J = world.journal

    local function currentLoot()
        local byDifficulty = J.loot[J.selectedInstance]
        return (byDifficulty and byDifficulty[J.difficulty]) or {}
    end

    -- Stage two: once the list is current, the item data behind each row
    -- lands later and fires one EJ_LOOT_DATA_RECIEVED per row, exactly as the
    -- 2026-09-06 transcript showed (351 events across a 434 ms walk).
    local function startItemDataFetch(token)
        if J.itemDataDelaySeconds == nil then
            J.itemDataPending = false
            return
        end
        J.itemDataPending = true
        if J.itemDataDelaySeconds == false then
            return
        end
        _G.C_Timer.After(J.itemDataDelaySeconds, function()
            if J.fetchToken ~= token then
                return
            end
            J.itemDataPending = false
            for _, row in ipairs(currentLoot()) do
                world.fireEvent("EJ_LOOT_DATA_RECIEVED", row.itemID)
            end
        end)
    end

    -- Only the latest fetch resolves, so selecting an instance and then a
    -- difficulty produces one loot list and one event, not two.
    local function startLootFetch()
        J.fetchToken = (J.fetchToken or 0) + 1
        local token = J.fetchToken
        if J.lootDelaySeconds == nil then
            J.lootPending = false
            startItemDataFetch(token)
            return
        end
        J.lootPending = true
        J.itemDataPending = J.itemDataDelaySeconds ~= nil
        if J.lootDelaySeconds == false then
            return
        end
        _G.C_Timer.After(J.lootDelaySeconds, function()
            if J.fetchToken ~= token then
                return
            end
            J.lootPending = false
            local first = currentLoot()[1]
            world.fireEvent("EJ_LOOT_DATA_RECIEVED", first and first.itemID or nil)
            startItemDataFetch(token)
        end)
    end
    world.journal.startLootFetch = startLootFetch

    define("EJ_GetNumTiers", function()
        return J.numTiers
    end)
    define("EJ_GetCurrentTier", function()
        return J.currentTier
    end)
    define("EJ_GetTierInfo", function(index)
        local tier = J.tierInfo[index]
        if not tier then
            return nil
        end
        return tier[1], tier[2]
    end)
    define("EJ_SelectTier", function(index)
        J.currentTier = index
    end)
    define("EJ_GetInstanceByIndex", function(index, isRaid)
        local list = isRaid and J.instances.raids or J.instances.dungeons
        local instance = list[index]
        if not instance then
            return nil
        end
        -- Ketho's ordering: 1 instanceID, 2 name, 3 description, 4-10 art and
        -- flags, 11 mapID.
        local nothing = nil
        return instance.instanceID,
            instance.name,
            instance.description,
            nothing,
            nothing,
            nothing,
            nothing,
            nothing,
            nothing,
            nothing,
            instance.mapID
    end)
    -- EJ_GetInstanceInfo([journalInstanceID]) -> name, description, bgImage,
    -- buttonImage1, loreImage, buttonImage2, dungeonAreaMapID, link,
    -- shouldDisplayDifficulty, mapID, covenantID, isRaid. The ordering is
    -- Blizzard's own, read from its shipped Encounter Journal under .luals/
    -- rather than from the wiki: `name, _, _, icon = EJ_GetInstanceInfo(id)`
    -- takes the fourth return as the instance's button art
    -- (Blizzard_EncounterJournal.lua line 2413), and
    -- `instanceName, description, bgImage, _, loreImage, buttonImage, ...`
    -- (line 1211) fixes the three around it. The art values here are
    -- PLACEHOLDER file IDs like every other number in this file: what a test
    -- asserts is that the fourth return reached the walk, never which file it
    -- was. Raids answer as well as dungeons, and an instance this client does
    -- not know answers nil.
    define("EJ_GetInstanceInfo", function(journalInstanceID)
        local wanted = journalInstanceID or J.selectedInstance
        for _, list in pairs(J.instances) do
            for _, instance in ipairs(list) do
                if instance.instanceID == wanted then
                    return instance.name,
                        instance.description,
                        instance.bgImage,
                        instance.buttonImage1,
                        instance.loreImage,
                        instance.buttonImage2,
                        instance.dungeonAreaMapID,
                        instance.link,
                        instance.shouldDisplayDifficulty,
                        instance.mapID
                end
            end
        end
        return nil
    end)
    define("EJ_GetInstanceForMap", function(mapID)
        return J.instanceForMap[mapID]
    end)
    define("EJ_SelectInstance", function(journalInstanceID)
        J.selectedInstance = journalInstanceID
        J.selectCalls[#J.selectCalls + 1] = { instance = journalInstanceID }
        startLootFetch()
    end)
    define("EJ_InstanceIsRaid", function()
        for _, instance in ipairs(J.instances.raids) do
            if instance.instanceID == J.selectedInstance then
                return true
            end
        end
        return false
    end)
    define("EJ_GetDifficulty", function()
        return J.difficulty
    end)
    define("EJ_SetDifficulty", function(difficultyID)
        J.difficulty = difficultyID
        J.selectCalls[#J.selectCalls + 1] = { difficulty = difficultyID }
        startLootFetch()
    end)
    define("EJ_IsValidInstanceDifficulty", function(difficultyID)
        local valid = J.validDifficulty[J.selectedInstance]
        if not valid then
            return true
        end
        return valid[difficultyID] == true
    end)
    define("EJ_GetLootFilter", function()
        return J.lootFilter[1], J.lootFilter[2]
    end)
    define("EJ_SetLootFilter", function(classID, specID)
        J.lootFilter = { classID, specID }
        J.lootFilterCalls[#J.lootFilterCalls + 1] = { classID, specID }
    end)
    define("EJ_ResetLootFilter", function()
        J.lootFilter = { 0, 0 }
    end)
    -- Blizzard's loot button resolves a row's boss with this, by encounterID.
    define("EJ_GetEncounterInfo", function(encounterID)
        for _, list in pairs(J.encounters) do
            for _, encounter in ipairs(list) do
                if encounter.encounterID == encounterID then
                    return encounter.name, encounter.description, encounterID
                end
            end
        end
        return nil
    end)
    define("EJ_GetEncounterInfoByIndex", function(index, journalInstanceID)
        local encounters = J.encounters[journalInstanceID or J.selectedInstance] or {}
        local encounter = encounters[index]
        if not encounter then
            return nil
        end
        return encounter.name, encounter.description, encounter.encounterID
    end)
    define("EJ_GetNumLoot", function()
        if J.lootPending then
            return 0
        end
        return #currentLoot()
    end)
    define("EJ_IsLootListOutOfDate", function()
        return J.lootPending
    end)

    define("C_EncounterJournal", {
        GetLootInfoByIndex = function(index)
            if J.lootPending then
                return nil
            end
            local row = currentLoot()[index]
            if not row then
                return nil
            end
            if J.itemDataPending then
                -- The bare shape the transcript recorded for 369 of 613 rows.
                return {
                    itemID = row.itemID,
                    encounterID = row.encounterID,
                    displayAsPerPlayerLoot = false,
                    displayAsVeryRare = false,
                    displayAsExtremelyRare = false,
                }
            end
            return deepcopy(row)
        end,
        GetInstanceForGameMap = function(mapID)
            return J.instanceForGameMap[mapID]
        end,
        SetPreviewMythicPlusLevel = function(level)
            J.previewLevel = level
            J.previewLevelCalls[#J.previewLevelCalls + 1] = level
        end,
        InstanceHasLoot = function()
            return true
        end,
    })
    define("C_MythicPlus", {
        -- The keystone the character owns. Three reads, exactly as Blizzard's
        -- exported docs declare them (MythicPlusInfoDocumentation.lua:34, 38,
        -- 42): each returns one number and takes nothing. world.keystone = nil
        -- is a character holding no key, which is what the client answers with
        -- 0 / 0 / 0 on a fresh character.
        GetOwnedKeystoneLevel = function()
            return world.keystone and world.keystone.level or 0
        end,
        GetOwnedKeystoneChallengeMapID = function()
            return world.keystone and world.keystone.challengeMapID or 0
        end,
        GetOwnedKeystoneMapID = function()
            return world.keystone and world.keystone.mapID or 0
        end,
        GetCurrentSeason = function()
            return J.season
        end,
        GetCurrentSeasonValues = function()
            return J.season, J.season, J.season
        end,
        RequestMapInfo = function() end,
    })
    define("C_ChallengeMode", {
        GetMapTable = function()
            return deepcopy(J.mapTable)
        end,
        GetMapUIInfo = function(mapChallengeModeID)
            local info = J.mapUIInfo[mapChallengeModeID]
            if not info then
                return nil
            end
            return info[1], info[2], info[3], info[4], info[5], info[6]
        end,
    })

    return world
end

function Stub.uninstall()
    for name in pairs(installedNames) do
        _G[name] = saved[name]
    end
    installedNames = {}
    saved = {}
end

return Stub

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
-- Appearance-only setters: accepted and ignored, because a headless test has no
-- pixels to check them against.
local IGNORED_REGION_METHODS = {
    "SetJustifyH",
    "SetJustifyV",
    "SetFontObject",
    "SetFont",
    "SetNonSpaceWrap",
    "SetDrawLayer",
}

-- Appearance setters whose ARGUMENT is a contract, recorded rather than
-- ignored (M5-1, WKE-550). Which icon a row got, which colour its quality
-- border was tinted and whether a badge is at a downgrade's opacity are
-- decisions this addon makes and a test can hold it to; what they look like on
-- the owner's screen is still an in-game step. The real widgets have no
-- getters for these, so none is faked - the last arguments are left on the
-- region under names of the stub's own (`texture`, `atlas`, `vertexColor`,
-- `alpha`, `textColor`).
local function attachAppearance(r)
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
    function r:SetAtlas(value)
        self.atlas = value
        self.texture = nil
    end
    function r:GetAtlas()
        return self.atlas
    end
    function r:SetVertexColor(red, green, blue, alpha)
        self.vertexColor = { red, green, blue, alpha }
    end
    function r:SetAlpha(value)
        self.alpha = value
    end
    function r:GetAlpha()
        return self.alpha == nil and 1 or self.alpha
    end
    function r:SetTextColor(red, green, blue, alpha)
        self.textColor = { red, green, blue, alpha }
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
    function r:GetObjectType()
        return self.kind
    end
    function r:GetParent()
        return self.parent
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
    function r:SetAllPoints()
        self.points[#self.points + 1] = { "ALL" }
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
    -- WHICH texture a region was given is a decision the code makes - the spec
    -- icon or the class sheet, the class sheet at which corner - and not a
    -- pixel, so it is recorded like SetWordWrap rather than ignored. The real
    -- widget has no getter for any of the three; nothing here is faked beyond
    -- remembering what it was told (M5-2).
    function r:SetTexture(value)
        self.texture = value
    end
    function r:GetTexture()
        return self.texture
    end
    function r:SetAtlas(value)
        self.atlas = value
    end
    function r:SetTexCoord(...)
        self.texCoord = { ... }
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
    -- The frame's centre in UI coordinates. Nothing here lays anything out, so
    -- it is whatever a test set (used by the minimap drag, M5-2); 0, 0 unset.
    function r:GetCenter()
        local c = self.center
        if not c then
            return 0, 0
        end
        return c[1], c[2]
    end
    for _, name in ipairs(IGNORED_REGION_METHODS) do
        r[name] = function() end
    end
    attachAppearance(r)
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

    function box:Acquire(template)
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

    function box:ReleaseAll()
        for _, pool in pairs(self.pool) do
            for _, frame in ipairs(pool) do
                if frame.inUse then
                    frame.inUse = false
                    frame:Hide()
                    if self.view and self.view.frameResetter then
                        self.view.frameResetter(frame, frame.elementData)
                    end
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
        self:ReleaseAll()
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
                    local frame = self:Acquire(template)
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

    function box:SetDataProvider(dataProvider)
        self.dataProvider = dataProvider
        self:Layout()
    end
    function box:FlushDataProvider()
        self:SetDataProvider(newDataProvider({}))
    end
end

-- WowStyle1FilterDropdownTemplate over the 11.0 menu API. The generator is
-- handed the dropdown and a root description and calls CreateRadio /
-- CreateButton / CreateTitle / SetTag on it (DropdownButton.lua:237 SetupMenu,
-- :255 GenerateMenu; MenuUtil.lua:226 CreateRadio(text, isSelected,
-- setSelected, data)). What is modelled is which elements the generator asked
-- for and what each one does when it is picked, which is the whole contract
-- the panel depends on; the menu's pixels are the client's.
local function attachFilterDropdown(dropdown)
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
    end
    function dropdown:SetupMenu(generator)
        assert(type(generator) == "function", "SetupMenu: argument is not a function")
        self.menuGenerator = generator
        self:GenerateMenu()
    end
    function dropdown:SetDefaultText(text)
        self.defaultText = text
    end
    function dropdown:SetSelectionText(formatter)
        self.selectionTextFormatter = formatter
    end
    dropdown.IsMenuOpen = function()
        return false
    end
    -- Picking an option the way a player does: find the row by its text and
    -- run what the generator said it does. The real menu rebuilds its rows
    -- from the owner's state every time it opens, so the caller regenerates.
    function dropdown:SelectByText(text)
        for _, element in ipairs(self.menuElements) do
            if element.text == text then
                element:Select()
                return true
            end
        end
        return false
    end
end

local function attachTemplate(f, world, template)
    if type(template) ~= "string" then
        return
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
    -- WowScrollBoxList (Blizzard_SharedXML/Shared/Scroll/ScrollTemplates.xml
    -- line 4) and the filter dropdown, both M5-3's.
    if template:find("WowScrollBoxList", 1, true) then
        attachScrollBoxList(f, world)
    end
    if template:find("WowStyle1FilterDropdownTemplate", 1, true) then
        attachFilterDropdown(f)
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
    function f:CreateTexture()
        local tex = newRegion("Texture", self)
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

    if kind == "Button" or kind == "CheckButton" then
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
        f.SetNormalFontObject = function() end
        f.SetDisabledFontObject = function() end
        f.SetHighlightFontObject = function() end
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
        function f:Enter()
            local fn = self.scripts.OnEnter
            if fn then
                fn(self)
            end
        end
        function f:Leave()
            local fn = self.scripts.OnLeave
            if fn then
                fn(self)
            end
        end
    end

    -- DropdownButton, the 11.0 menu system (Blizzard_Menu/DropdownButton.lua
    -- and MenuTemplates.lua under .luals/, read 2026-09-09). What is modelled
    -- is the CONTRACT the panels use and nothing else: SetupMenu takes a
    -- generator of (dropdown, rootDescription); the root description takes a
    -- tag and radio entries of (text, isSelected, setSelected); the menu is
    -- generated immediately when the dropdown is already shown, which is the
    -- behaviour DropdownButtonMixin:SetupMenu documents. `Pick(index)` is the
    -- stub's own, and is a test clicking one entry.
    if kind == "DropdownButton" then
        f.menuEntries = {}
        function f:SetDefaultText(text)
            self.defaultText = text
        end
        function f:GetDefaultText()
            return self.defaultText
        end
        function f:GenerateMenu()
            if not self.menuGenerator then
                return
            end
            local root = { entries = {} }
            function root.SetTag(description, tag)
                description.tag = tag
            end
            function root.CreateRadio(description, text, isSelected, setSelected, data)
                local entry = {
                    kind = "radio",
                    text = text,
                    isSelected = isSelected,
                    setSelected = setSelected,
                    data = data,
                }
                description.entries[#description.entries + 1] = entry
                return entry
            end
            function root.CreateButton(description, text, callback, data)
                local entry = { kind = "button", text = text, callback = callback, data = data }
                description.entries[#description.entries + 1] = entry
                return entry
            end
            self.menuGenerator(self, root)
            self.menuDescription = root
            self.menuTag = root.tag
            self.menuEntries = root.entries
        end
        function f:SetupMenu(generator)
            assert(type(generator) == "function", "SetupMenu: argument is not a function")
            self.menuGenerator = generator
            if self:IsShown() then
                self:GenerateMenu()
            end
        end
        function f:Pick(index)
            self:GenerateMenu()
            local entry = self.menuEntries[index]
            if not entry then
                return false
            end
            if entry.setSelected then
                entry.setSelected(entry.data)
            elseif entry.callback then
                entry.callback(entry.data)
            end
            return true
        end
        function f:SelectedIndex()
            self:GenerateMenu()
            for index, entry in ipairs(self.menuEntries) do
                if entry.isSelected and entry.isSelected(entry.data) then
                    return index
                end
            end
            return nil
        end
    end

    if kind == "EditBox" then
        f.maxLetters = 0
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
        cursor = { 0, 0 },
        equipped = {}, -- [invSlot] = { link = , id = }
        bags = {}, -- [bagIndex] = { numSlots = , items = { [slot] = { info = , link = , id = } } }
        items = {}, -- [link] = { level = , info = {...}, instant = {...} }
        -- Every itemID C_Item.RequestLoadItemDataByID was asked for, in order.
        -- The stub never answers by itself: a test that wants the data to
        -- arrive registers the item and fires ITEM_DATA_LOAD_RESULT (or
        -- GET_ITEM_INFO_RECEIVED) itself, which is how "the client answered
        -- late" and "the client never answered" are both drivable (M3-12).
        itemDataRequests = {},
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
            ["evergreen-weeklyrewards-reward-selected"] = true,
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
        bankOpen = false,
        vaultOpen = false,
        reloads = 0,
        vault = { hasAvailable = false, canClaim = false, activities = {}, links = {}, examples = {} },
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
        return "Druid", "DRUID", 11
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
    define("GetSpecializationInfo", function(index)
        local spec = world.spec
        if not spec or index ~= spec.index then
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
    define("debugprofilestop", function()
        return os.clock() * 1000
    end)
    define("time", os.time)
    define("date", os.date)
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
    -- combat message back off it.
    local tooltip = newFrame("Frame", world)
    world.tooltip = tooltip
    tooltip.lines = {}
    function tooltip:SetOwner(owner, anchor)
        self.owner, self.anchor = owner, anchor
        self.lines = {}
    end
    function tooltip:SetText(text)
        self.lines = { tostring(text) }
    end
    function tooltip:AddLine(text)
        self.lines[#self.lines + 1] = tostring(text)
    end
    function tooltip:SetHyperlink(link)
        self.hyperlink = link
        self.itemID = nil
        self.lines = { tostring(link) }
    end
    -- What a row with an id and no link is shown by: QE Live names an item by
    -- id, so the tooltip has to take one.
    function tooltip:SetItemByID(itemID)
        self.itemID = itemID
        self.hyperlink = nil
        self.lines = { "item " .. tostring(itemID) }
    end
    function tooltip:ClearLines()
        self.lines = {}
    end
    function tooltip:Text()
        return table.concat(self.lines, "\n")
    end
    define("GameTooltip", tooltip)
    -- The shopping compare. A FrameXML global, not an exported API, so what is
    -- modelled is only that it was asked for and on whose behalf.
    world.compareCalls = {}
    define("GameTooltip_ShowCompareItem", function(self, anchorFrame)
        world.compareCalls[#world.compareCalls + 1] = { self, anchorFrame }
    end)

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
    define("ItemLocation", {
        CreateFromEquipmentSlot = function(_, slot)
            return { equipmentSlotIndex = slot }
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

    -- C_Texture.GetAtlasInfo(atlas) -> AtlasInfo, or nil for an atlas this
    -- client does not have. Only the "does it exist" half matters here.
    define("C_Texture", {
        GetAtlasInfo = function(atlas)
            if not world.atlases[atlas] then
                return nil
            end
            return { file = atlas, width = 16, height = 16 }
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
    })

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

    define("C_WeeklyRewards", {
        HasAvailableRewards = function()
            return world.vault.hasAvailable
        end,
        CanClaimRewards = function()
            return world.vault.canClaim
        end,
        GetActivities = function()
            return deepcopy(world.vault.activities)
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
    })
    local vaultFrame = newFrame("Frame", world)
    function vaultFrame.IsShown()
        return world.vaultOpen
    end
    define("WeeklyRewardsFrame", vaultFrame)

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
            PrimaryRaidNormal = 14,
            PrimaryRaidHeroic = 15,
            PrimaryRaidMythic = 16,
        },
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

-- FlexTip options window (/ftip) and its entry in the game's AddOns settings.
local _, FT = ...

local widgets = {}

local function AddHint(frame, text)
    if not text then return end
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(text, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local function PlayClick(on)
    if PlaySound and SOUNDKIT then
        PlaySound(on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end
end

local function IndexOf(choices, value)
    for i, choice in ipairs(choices) do
        if choice.value == value then return i end
    end
end

---------------------------------------------------------------------------
-- A simple top-to-bottom column layout
---------------------------------------------------------------------------
local Column = {}
Column.__index = Column

local function NewColumn(parent, x, y, width)
    return setmetatable({ parent = parent, x = x, y = y, width = width }, Column)
end

function Column:Place(region, height)
    region:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x, self.y)
    self.y = self.y - height
end

function Column:Header(text)
    self.y = self.y - 6
    local label = self.parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetText(text)
    self:Place(label, 16)
    local rule = self.parent:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(1, 0.82, 0, 0.3)
    rule:SetSize(self.width, 1)
    rule:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -3)
    self.y = self.y - 10
end

local function NewCheck(parent, label, hint, get, set)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    local text = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    text:SetText(label)
    cb:SetHitRectInsets(0, -(text:GetStringWidth() + 6), 0, 0)
    cb:SetScript("OnClick", function(self)
        local checked = self:GetChecked() and true or false
        PlayClick(checked)
        set(checked)
    end)
    cb.Refresh = function(self) self:SetChecked(get()) end
    AddHint(cb, hint)
    widgets[#widgets + 1] = cb
    return cb
end

local function RowAccessors(row)
    return function() return FT.db.rows[row] end,
        function(value) FT:SetRow(row, value) end
end

function Column:Check(key, label, hint, get, set)
    get = get or function() return FT.db[key] end
    set = set or function(value) FT:Set(key, value) end
    local cb = NewCheck(self.parent, label, hint, get, set)
    self:Place(cb, 26)
    return cb
end

-- A checkbox for one part of what unit tooltips show.
function Column:RowCheck(row, label, hint)
    local get, set = RowAccessors(row)
    return self:Check(nil, label, hint, get, set)
end

-- Two row checkboxes side by side; `second` is optional.
function Column:RowPair(first, second)
    for index, spec in ipairs({ first, second }) do
        local get, set = RowAccessors(spec.row)
        local cb = NewCheck(self.parent, spec.label, spec.hint, get, set)
        cb:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x + (index - 1) * (self.width / 2), self.y)
    end
    self.y = self.y - 26
end

function Column:SubHeader(text)
    self.y = self.y - 4
    local label = self.parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    label:SetText(text)
    self:Place(label, 16)
end

function Column:Note(text)
    local note = self.parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    note:SetWidth(self.width)
    note:SetJustifyH("LEFT")
    note:SetText(text)
    self:Place(note, 30)
end

function Column:Slider(key, label, step, format, hint)
    local range = FT.RANGES[key]
    local holder = CreateFrame("Frame", nil, self.parent)
    holder:SetSize(self.width, 40)

    local title = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    title:SetPoint("TOPLEFT", 2, 0)
    title:SetText(label)
    local valueText = holder:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    valueText:SetPoint("TOPRIGHT", -2, 0)

    local slider = CreateFrame("Slider", nil, holder, "BackdropTemplate")
    slider:SetOrientation("HORIZONTAL")
    slider:SetPoint("TOPLEFT", 0, -16)
    slider:SetPoint("TOPRIGHT", 0, -16)
    slider:SetHeight(17)
    slider:SetBackdrop({
        bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
        edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 3, right = 3, top = 6, bottom = 6 },
    })
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    thumb:SetSize(32, 32)
    slider:SetThumbTexture(thumb)
    slider:SetMinMaxValues(range[1], range[2])
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:EnableMouseWheel(true)

    local refreshing = false
    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value / step + 0.5) * step
        valueText:SetText(format(value))
        if not refreshing then FT:Set(key, value) end
    end)
    slider:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(self:GetValue() + delta * step)
    end)

    holder.Refresh = function()
        refreshing = true
        slider:SetValue(FT.db[key])
        valueText:SetText(format(FT.db[key]))
        refreshing = false
    end
    AddHint(slider, hint)
    self:Place(holder, 46)
    widgets[#widgets + 1] = holder
    return holder
end

-- A button that cycles through a list of choices (right-click goes back).
function Column:Cycle(key, label, choices, hint)
    local holder = CreateFrame("Frame", nil, self.parent)
    holder:SetSize(self.width, 40)

    local title = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    title:SetPoint("TOPLEFT", 2, 0)
    title:SetText(label)

    local button = CreateFrame("Button", nil, holder, "UIPanelButtonTemplate")
    button:SetPoint("TOPLEFT", 0, -15)
    button:SetSize(self.width, 22)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", function(_, mouseButton)
        local index = (IndexOf(choices, FT.db[key]) or 1) + (mouseButton == "RightButton" and -1 or 1)
        if index > #choices then index = 1 elseif index < 1 then index = #choices end
        PlayClick(true)
        FT:Set(key, choices[index].value)
    end)

    holder.Refresh = function()
        local index = IndexOf(choices, FT.db[key])
        button:SetText("<  " .. (index and choices[index].text or "?") .. "  >")
    end
    AddHint(button, (hint and (hint .. "\n\n") or "") .. "|cffaaaaaaLeft-click for the next option, right-click for the previous one.|r")
    self:Place(holder, 44)
    widgets[#widgets + 1] = holder
    return holder
end

function Column:Buttons(specs)
    local gap = 8
    local width = (self.width - gap * (#specs - 1)) / #specs
    local previous
    for _, spec in ipairs(specs) do
        local button = CreateFrame("Button", nil, self.parent, "UIPanelButtonTemplate")
        button:SetSize(width, 22)
        button:SetText(spec.text)
        button:SetScript("OnClick", spec.onClick)
        if spec.refresh then
            button.Refresh = spec.refresh
            widgets[#widgets + 1] = button
        end
        AddHint(button, spec.hint)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", gap, 0)
        else
            button:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x, self.y)
        end
        previous = button
    end
    self.y = self.y - 30
end

---------------------------------------------------------------------------
-- Value formats
---------------------------------------------------------------------------
local function FormatScale(v) return string.format("%.2fx", v) end
local function FormatInt(v) return string.format("%d", v) end
local function FormatOffset(v) return string.format("%+d", v) end
local function FormatAlpha(v)
    if v >= 0.995 then return "Default" end
    return string.format("%d%%", v * 100 + 0.5)
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
StaticPopupDialogs["FLEXTIP_RESET_ALL"] = {
    text = "Reset all FlexTip settings to their defaults?",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function() FT:ResetAll() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function FT:CreateOptions()
    if self.optionsFrame then return self.optionsFrame end

    local f = CreateFrame("Frame", "FlexTipOptionsFrame", UIParent, "BackdropTemplate")
    f:SetSize(900, 580)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    f:Hide()
    tinsert(UISpecialFrames, "FlexTipOptionsFrame") -- close with Escape

    local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -20)
    title:SetText("FlexTip")
    local subtitle = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -4)
    subtitle:SetText("v" .. FT.version .. "  -  type /ftip help for chat commands")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    -- Left column: position and combat
    local left = NewColumn(f, 28, -58, 260)
    left:Header("Position")
    left:Buttons({
        {
            text = "Unlock anchor",
            hint = "Show the FlexTip anchor so you can drag it where you want tooltips to appear.",
            onClick = function() FT:ToggleLock() end,
            refresh = function(self) self:SetText(FT.db.locked and "Unlock anchor" or "Lock anchor") end,
        },
        {
            text = "Reset position",
            hint = "Move the anchor back to the bottom right of the screen.",
            onClick = function() FT:ResetPosition() end,
        },
    })
    left:Cycle("worldAnchor", "World tooltips (units, objects)", FT.ANCHOR_MODES,
        "Where tooltips appear when you hover over players, NPCs and objects in the world.")
    left:Cycle("frameAnchor", "UI tooltips (unit frames, action bars)", FT.ANCHOR_MODES,
        "Where tooltips appear for unit frames, action buttons and other UI that uses the default tooltip spot.")
    left:Cycle("anchorPoint", "Tooltip corner pinned to the anchor", FT.POINTS,
        "Which corner of the tooltip sits on the matching corner of the anchor. The tooltip grows away from it.\n\nBottom right grows up and to the left, like Blizzard's default.")
    left:Cycle("cursorPoint", "Tooltip corner pinned to the cursor", FT.POINTS,
        "Used when a tooltip follows the mouse cursor.")
    left:Slider("cursorX", "Cursor offset, horizontal", 1, FormatOffset)
    left:Slider("cursorY", "Cursor offset, vertical", 1, FormatOffset)
    left:Header("Combat")
    left:Cycle("hideInCombat", "Hide tooltips in combat", FT.COMBAT_MODES,
        "World tooltips only: hide tooltips for units and objects in the world but keep action bar and unit frame tooltips.")

    -- Middle column: size, collapse and appearance
    local right = NewColumn(f, 320, -58, 260)
    right:Header("Size")
    right:Slider("scale", "Scale", 0.05, FormatScale,
        "You can also scale with the mouse wheel or the corner grip while the anchor is unlocked.")
    right:Header("Collapse")
    right:Check("collapsed", "Collapse unit tooltips",
        "Show only the first rows of player and NPC tooltips.\n\nTip: bind a key under Options > Keybindings > AddOns > FlexTip to toggle this quickly.")
    right:Slider("collapseLines", "Rows shown when collapsed", 1, FormatInt,
        "Counts only rows you haven't hidden in the Rows section.")
    right:Check("collapseKeepsQuests", "Always show quest progress",
        "Quest rows (from Questie or the game) stay visible when collapsed and don't count toward the row limit. Untick them under Quests to hide them anyway.")
    right:Cycle("expandModifier", "Hold to show the full tooltip", FT.MODIFIERS,
        "While you hold this key, collapsed tooltips expand and hidden rows come back.")
    right:Header("Appearance")
    right:Check("classColorName", "Class-colored player names")
    right:Check("classColorBorder", "Class-colored border for players")
    right:Check("hideHealthBar", "Hide the health bar")
    right:Slider("bgAlpha", "Background opacity", 0.05, FormatAlpha,
        "'Default' leaves Blizzard's background untouched.")

    -- Right column: what player and NPC tooltips show
    local rows = NewColumn(f, 612, -58, 260)
    rows:Header("What tooltips show")
    rows:Note("Untick anything you don't want to see. The name always shows.")
    rows:SubHeader("Name")
    rows:RowPair({ row = "realm", label = "Realm", hint = "The realm after the name of players from other realms." },
        { row = "playerTitle", label = "Title", hint = "Titles in the name, like 'Sergeant' or 'the Patient'." })
    rows:SubHeader("Guild")
    rows:RowPair({ row = "guild", label = "Guild", hint = "The whole guild row." },
        { row = "guildRank", label = "Rank", hint = "The guild rank, when it's shown next to the guild name." })
    rows:SubHeader("Level row")
    rows:RowPair({ row = "level", label = "Level" },
        { row = "race", label = "Race / type", hint = "The race of players, or the creature type of NPCs, like Beast or Humanoid." })
    rows:SubHeader("More rows")
    rows:RowPair({ row = "class", label = "Class", hint = "The class row. If the class is on the level row, it's removed from there." },
        { row = "faction", label = "Faction", hint = "Alliance or Horde." })
    rows:RowPair({ row = "pvp", label = "PvP" },
        { row = "title", label = "NPC title", hint = "The row under an NPC's name, like <Flight Master>." })
    rows:SubHeader("Quests")
    rows:RowCheck("questGivers", "Quests to pick up or turn in",
        "Questie's rows for quests this NPC starts or ends.")
    rows:RowCheck("quest", "Quest objectives and progress",
        "Quest titles and objective progress, from Questie or from the game itself.")
    rows:SubHeader("Other")
    rows:RowCheck("other", "Rows from other addons",
        "Rows added by other addons, and anything else FlexTip doesn't recognize.")
    rows:Check("showTarget", "Add a 'Target:' row",
        "Shows who the unit is targeting, or >> You << when it's you. Leave this off if another addon already adds one.")

    local preview = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    preview:SetSize(150, 24)
    preview:SetPoint("BOTTOMLEFT", 28, 22)
    preview:SetText("Preview")
    preview:SetScript("OnClick", function() FT:ShowPreview() end)
    AddHint(preview, "Show your own tooltip at the anchor with the current settings.")

    local reset = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    reset:SetSize(150, 24)
    reset:SetPoint("BOTTOMRIGHT", -28, 22)
    reset:SetText("Reset all settings")
    reset:SetScript("OnClick", function() StaticPopup_Show("FLEXTIP_RESET_ALL") end)

    f:SetScript("OnShow", function() FT:RefreshOptions() end)
    self.optionsFrame = f
    return f
end

function FT:RefreshOptions()
    if not (self.optionsFrame and self.optionsFrame:IsShown()) then return end
    for _, widget in ipairs(widgets) do
        widget:Refresh()
    end
end

function FT:ToggleOptions()
    local f = self:CreateOptions()
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
    end
end

---------------------------------------------------------------------------
-- Entry under Options > AddOns that opens the window
---------------------------------------------------------------------------
function FT:RegisterSettingsPanel()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
        return
    end
    local panel = CreateFrame("Frame")
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("FlexTip")
    local text = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    text:SetText("Move, resize and collapse the game tooltip.")
    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetSize(200, 26)
    button:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -16)
    button:SetText("Open FlexTip options")
    button:SetScript("OnClick", function()
        local f = FT:CreateOptions()
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:Show()
    end)
    local category = Settings.RegisterCanvasLayoutCategory(panel, "FlexTip")
    Settings.RegisterAddOnCategory(category)
    self.settingsCategory = category
end

-- FlexTip tooltip logic: anchoring, scale, rows, collapsing and appearance.
local _, FT = ...

local GameTooltip = GameTooltip
local UIParent = UIParent
local issecretvalue = issecretvalue or function() return false end

-- State for the tooltip currently on screen. It lives in our own table and is
-- never written onto GameTooltip: writing fields onto Blizzard frames spreads
-- taint, which on Mainline clients can break Blizzard's own tooltip code.
local state = {
    category = nil,    -- "world" or "frame" when Blizzard used the default anchor
    onMover = false,   -- anchored to the FlexTip anchor
    follow = false,    -- following the cursor
    isUnit = false,    -- showing a unit
    pending = false,   -- unit rows still need to be captured
    unit = nil,        -- unit token of the tooltip
    info = nil,        -- guild/class/faction of the unit, used to recognize rows
    targetLine = nil,  -- index of the "Target:" row we added
    questTexts = nil,  -- texts of the game's own quest rows for this unit
    classColor = nil,  -- class color of the unit, if it is a player
    numLines = 0,      -- number of lines captured in `snapshot`
    packed = 0,        -- number of visible rows while some are hidden, else 0
    orig = nil,        -- Blizzard's border/background colors before we tinted them
}
local snapshot = {} -- [line] = original text, colors and row kind of each line
local written = {}  -- [line] = which snapshot entry that line shows now (0 = blank)
local visible = {}  -- scratch list of the snapshot entries to show, in order
local questieLines = {} -- [line] = true for lines that Questie added
FT.state = state

local lastError
local function SafeCall(func, ...)
    local ok, err = pcall(func, ...)
    if not ok and FT.db and FT.db.debug and err ~= lastError then
        lastError = err
        FT:Print("|cffff6060" .. tostring(err) .. "|r")
    end
    return ok
end
FT.SafeCall = SafeCall

---------------------------------------------------------------------------
-- Anchoring
---------------------------------------------------------------------------
local function AnchorToMover(tip)
    local mover = FT.mover
    if not mover then return end
    local point = FT.db.anchorPoint
    tip:ClearAllPoints()
    tip:SetPoint(point, mover, point, 0, 0)
    state.onMover = true
end
FT.AnchorToMover = AnchorToMover

local lastX, lastY
local function AnchorToCursor(tip)
    local x, y = GetCursorPosition()
    if x == lastX and y == lastY then return end
    lastX, lastY = x, y
    local scale = tip:GetEffectiveScale()
    tip:ClearAllPoints()
    tip:SetPoint(FT.db.cursorPoint, UIParent, "BOTTOMLEFT",
        x / scale + FT.db.cursorX, y / scale + FT.db.cursorY)
end

-- Blizzard calls GameTooltip_SetDefaultAnchor for world units/objects (with
-- UIParent as the parent) and for most UI frames (unit frames, action buttons).
local function OnSetDefaultAnchor(tip, parent)
    if tip ~= GameTooltip then return end
    local world = parent == nil or parent == UIParent or parent == WorldFrame
    state.category = world and "world" or "frame"
    local mode = world and FT.db.worldAnchor or FT.db.frameAnchor
    if mode == "MOVER" then
        AnchorToMover(tip)
    elseif mode == "CURSOR" then
        state.follow = true
        lastX, lastY = nil, nil
        AnchorToCursor(tip)
    end
end

---------------------------------------------------------------------------
-- Scale
---------------------------------------------------------------------------
-- Comparison tooltips sit next to GameTooltip, so they get the same scale.
local SCALED = { "GameTooltip", "ShoppingTooltip1", "ShoppingTooltip2" }

function FT:ApplyScale()
    local scale = self.db.scale
    for _, name in ipairs(SCALED) do
        local tip = _G[name]
        if tip and tip.SetScale and math.abs(tip:GetScale() - scale) > 0.001 then
            tip:SetScale(scale)
        end
    end
    lastX, lastY = nil, nil
end

---------------------------------------------------------------------------
-- Appearance: border and background colors
---------------------------------------------------------------------------
local function GetNineSlice(tip)
    local ns = tip.NineSlice
    if ns and ns.SetCenterColor and ns.SetBorderColor then return ns end
end

local function SaveOriginalColors(ns)
    local orig = {}
    if ns.Center then
        orig.cr, orig.cg, orig.cb, orig.ca = ns.Center:GetVertexColor()
    end
    if ns.TopLeftCorner then
        orig.br, orig.bg, orig.bb, orig.ba = ns.TopLeftCorner:GetVertexColor()
    end
    state.orig = orig
end

local function RestoreColors(tip)
    local orig = state.orig
    if not orig then return end
    state.orig = nil
    local ns = GetNineSlice(tip)
    if not ns then return end
    if orig.cr then ns:SetCenterColor(orig.cr, orig.cg, orig.cb, orig.ca) end
    if orig.br then ns:SetBorderColor(orig.br, orig.bg, orig.bb, orig.ba) end
end

function FT:ApplyAppearance(tip)
    local ns = GetNineSlice(tip)
    if not ns then return end
    local border = self.db.classColorBorder and state.classColor
    local alpha = self.db.bgAlpha < 0.995 and self.db.bgAlpha
    if not border and not alpha then
        RestoreColors(tip)
        return
    end
    if not state.orig then SaveOriginalColors(ns) end
    local orig = state.orig
    if border then
        ns:SetBorderColor(border.r, border.g, border.b, 1)
    elseif orig.br then
        ns:SetBorderColor(orig.br, orig.bg, orig.bb, orig.ba)
    end
    if alpha then
        ns:SetCenterColor(orig.cr or 0.09, orig.cg or 0.09, orig.cb or 0.19, alpha)
    elseif orig.cr then
        ns:SetCenterColor(orig.cr, orig.cg, orig.cb, orig.ca)
    end
end

---------------------------------------------------------------------------
-- Health bar
---------------------------------------------------------------------------
local function GetStatusBar()
    return GameTooltip.StatusBar or _G.GameTooltipStatusBar
end

function FT:ApplyHealthBar()
    local bar = GetStatusBar()
    if bar and self.db.hideHealthBar and bar:IsShown() then bar:Hide() end
end

---------------------------------------------------------------------------
-- Unit decorations: class colors and the unit's target
---------------------------------------------------------------------------
local function ClassColor(unit)
    if not UnitIsPlayer(unit) then return nil end
    local _, class = UnitClass(unit)
    if not class or issecretvalue(class) then return nil end
    local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
    return colors and colors[class]
end

local function ColorCode(r, g, b)
    return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end

function FT:AddTargetLine(tip, unit)
    local target = unit .. "target"
    if not UnitExists(target) then return end
    local label = "|cffffd100" .. (TARGET or "Target") .. ":|r "
    if UnitIsUnit(target, "player") then
        tip:AddLine(label .. "|cffff4040>> You <<|r")
        return
    end
    local name = UnitName(target)
    if not name or issecretvalue(name) then return end
    local r, g, b = 1, 1, 1
    local color = ClassColor(target)
    if color then
        r, g, b = color.r, color.g, color.b
    else
        local reaction = UnitReaction(target, "player")
        local rc = reaction and FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
        if rc then r, g, b = rc.r, rc.g, rc.b end
    end
    tip:AddLine(label .. ColorCode(r, g, b) .. name .. "|r")
end

function FT:DecorateUnit(tip)
    local _, unit = tip:GetUnit()
    if issecretvalue(unit) then unit = nil end
    if not unit and UnitExists("mouseover") then unit = "mouseover" end
    state.unit = unit
    if not unit then return end

    local color = ClassColor(unit)
    state.classColor = color
    if color and self.db.classColorName then
        local nameLine = _G.GameTooltipTextLeft1
        if nameLine then nameLine:SetTextColor(color.r, color.g, color.b) end
    end
    if self.db.showTarget then
        local before = tip:NumLines()
        self:AddTargetLine(tip, unit)
        if tip:NumLines() > before then state.targetLine = tip:NumLines() end
    end
    self:ApplyAppearance(tip)
end

---------------------------------------------------------------------------
-- Rows: hiding chosen rows and collapsing
--
-- On the first frame a unit tooltip is up (after every addon has added its
-- lines) we snapshot each line: its text, colors and what kind of row it is.
-- Then we write back only the rows that should show, packed to the top, and
-- blank the rest. Packing instead of blanking rows in place leaves no gaps.
-- Holding the "full tooltip" key writes every row back.
---------------------------------------------------------------------------
local function GetLine(i)
    return _G["GameTooltipTextLeft" .. i], _G["GameTooltipTextRight" .. i]
end

local function StripCodes(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:]*:", ""):gsub("|r", "")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function EscapePattern(text)
    return (text:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

-- The level row starts with the localized "Level %s" text (or ends with it in
-- languages that put the number first).
local levelPrefix, levelSuffix
local function IsLevelRow(text)
    if not levelPrefix then
        local fmt = TOOLTIP_UNIT_LEVEL or "Level %s"
        local before, after = fmt:match("^(.-)%%[sd](.*)$")
        levelPrefix = before and EscapePattern(before) or ""
        levelSuffix = after or ""
        if levelPrefix == "" and levelSuffix == "" then
            levelPrefix = EscapePattern((LEVEL or "Level") .. " ")
        end
    end
    if levelPrefix ~= "" then return text:find("^" .. levelPrefix) ~= nil end
    return text:find(levelSuffix, 1, true) ~= nil
end

local function GatherUnitInfo(unit)
    local info = {}
    if not (unit and UnitExists(unit)) then return info end
    if UnitIsPlayer(unit) then
        info.player = true
        local guild = GetGuildInfo(unit)
        if guild and not issecretvalue(guild) and guild ~= "" then info.guild = guild end
        local className = UnitClass(unit)
        if className and not issecretvalue(className) then info.class = className end
    else
        info.npc = true
    end
    local _, faction = UnitFactionGroup(unit)
    if faction and not issecretvalue(faction) then info.faction = faction end
    info.known = true
    return info
end

-- Row kinds: name, target, quest, guild, level, class, faction, pvp, title, other.
-- "unknown" rows (secret text, or no unit to compare with) always show.
local function Classify(i, text)
    if i == 1 then return "name" end
    if i == state.targetLine then return "target" end
    -- Questie's rows are known by who added them, so this works for secret text too.
    if questieLines[i] then return "quest" end
    if issecretvalue(text) then return "unknown" end
    local info = state.info or {}
    if text == nil then return info.known and "other" or "unknown" end
    text = StripCodes(text)
    if state.questTexts then
        for _, questText in ipairs(state.questTexts) do
            if text:find(questText, 1, true) then return "quest" end
        end
    end
    if info.guild and text:find(info.guild, 1, true) then return "guild" end
    if IsLevelRow(text) then return "level" end
    if info.class and (text == info.class or text:sub(-#info.class - 1) == " " .. info.class) then
        return "class"
    end
    if text == info.faction or text == FACTION_ALLIANCE or text == FACTION_HORDE then return "faction" end
    if text == PVP then return "pvp" end
    if info.npc and i == 2 then return "title" end
    return info.known and "other" or "unknown"
end

local function CaptureLine(i)
    local left, right = GetLine(i)
    local entry = snapshot[i] or {}
    snapshot[i] = entry
    entry.left = left and left:GetText()
    if left then
        entry.lr, entry.lg, entry.lb = left:GetTextColor()
        -- Questie's objective rows wrap; keep that when the row moves.
        entry.wrap = left.CanWordWrap and left:CanWordWrap()
    else
        entry.lr, entry.wrap = nil, nil
    end
    if right then
        entry.right = right:GetText()
        entry.rr, entry.rg, entry.rb = right:GetTextColor()
        entry.rshown = right:IsShown()
    else
        entry.right, entry.rr, entry.rshown = nil, nil, false
    end
    local ok, kind = pcall(Classify, i, entry.left)
    entry.kind = ok and kind or "unknown"
    written[i] = i
end

local function WriteLine(j, entry)
    local left, right = GetLine(j)
    if not left then return end
    if entry.wrap ~= nil and left.SetWordWrap then left:SetWordWrap(entry.wrap) end
    left:SetText(entry.left)
    if entry.lr then left:SetTextColor(entry.lr, entry.lg, entry.lb) end
    if right then
        right:SetText(entry.right)
        if entry.rr then right:SetTextColor(entry.rr, entry.rg, entry.rb) end
        if entry.rshown then right:Show() else right:Hide() end
    end
end

local function BlankLine(j)
    local left, right = GetLine(j)
    if left then left:SetText(nil) end
    if right then
        right:SetText(nil)
        right:Hide()
    end
end

-- Ask the game to recompute the tooltip's size. Calling Show() on a tooltip
-- that is already visible only re-measures it; it does not run OnShow. We skip
-- it while a world tooltip is fading out so we never stop the fade.
local function Relayout(tip)
    if tip:IsShown() and tip:GetAlpha() >= 0.99 then tip:Show() end
end

-- Some clients still reserve a little room for blanked lines; trim the tooltip
-- to end just below the last visible row. The width is left to the game, which
-- measures the rows that still have text (and knows about wrapped rows).
local function FitToRows(tip, count)
    local first = GetLine(1)
    local last = GetLine(count)
    if not (first and last) then return end
    local top, firstTop, lastBottom = tip:GetTop(), first:GetTop(), last:GetBottom()
    if not (top and firstTop and lastBottom) then return end
    local height = (top - lastBottom) + (top - firstTop)
    if tip:GetHeight() - height > 1 then tip:SetHeight(height) end
end

local function FullTooltipKeyDown()
    local key = FT.db.expandModifier
    if key == "SHIFT" then return IsShiftKeyDown() end
    if key == "CTRL" then return IsControlKeyDown() end
    if key == "ALT" then return IsAltKeyDown() end
    return false
end

local function RowShown(kind)
    local shown = FT.db.rows[kind]
    if shown == nil then return true end -- name, target and unknown rows
    return shown
end

local function SafeUnitInfo(unit)
    local ok, info = pcall(GatherUnitInfo, unit)
    return ok and info or {}
end

-- Runs every frame while a unit tooltip is shown, so it picks up lines other
-- addons add later, setting changes, and the full-tooltip key right away.
function FT:UpdateRows(tip)
    local n = tip:NumLines()
    if state.pending then
        state.pending = false
        state.info = SafeUnitInfo(state.unit)
        for i = 1, n do CaptureLine(i) end
        state.numLines = n
    elseif n > state.numLines then
        for i = state.numLines + 1, n do CaptureLine(i) end
        state.numLines = n
    elseif n < state.numLines then
        state.numLines = n
    end

    local full = FullTooltipKeyDown()
    local limit = (self.db.collapsed and not full) and self.db.collapseLines or n
    local keepQuests = self.db.collapseKeepsQuests
    local count, counted = 0, 0
    for i = 1, n do
        local kind = snapshot[i].kind
        if full or RowShown(kind) then
            -- Quest rows can stay visible without using up the collapsed row limit.
            local free = keepQuests and kind == "quest"
            if free or counted < limit then
                if not free then counted = counted + 1 end
                count = count + 1
                visible[count] = i
            end
        end
    end

    local changed = false
    for j = 1, n do
        local want = j <= count and visible[j] or 0
        if written[j] ~= want then
            if want == 0 then BlankLine(j) else WriteLine(j, snapshot[want]) end
            written[j] = want
            changed = true
        end
    end
    if changed then Relayout(tip) end
    state.packed = count < n and count or 0
    if state.packed > 0 then FitToRows(tip, count) end
end

---------------------------------------------------------------------------
-- Hide in combat
---------------------------------------------------------------------------
local function ShouldHideInCombat(inCombat)
    local mode = FT.db.hideInCombat
    if mode == "NEVER" then return false end
    if not (inCombat or InCombatLockdown()) then return false end
    if mode == "ALL" then return true end
    return state.category == "world"
end

function FT:OnEnterCombat()
    if GameTooltip:IsShown() and ShouldHideInCombat(true) then
        GameTooltip:Hide()
    end
end

---------------------------------------------------------------------------
-- Quest rows: the game's own (from the tooltip data) and Questie's
---------------------------------------------------------------------------
local function IsSecretTable(value)
    return issecretvalue(value) or (issecrettable ~= nil and issecrettable(value))
end

-- Texts of the QuestTitle/QuestObjective/QuestPlayer rows in the unit's
-- tooltip data. Secret entries are skipped.
local function CollectQuestTexts(data)
    local lineTypes = Enum and Enum.TooltipDataLineType
    if not lineTypes or IsSecretTable(data) or type(data) ~= "table" then return nil end
    local lines = data.lines
    if IsSecretTable(lines) or type(lines) ~= "table" then return nil end
    local questTypes = {}
    for _, name in ipairs({ "QuestTitle", "QuestObjective", "QuestPlayer" }) do
        if lineTypes[name] then questTypes[lineTypes[name]] = true end
    end
    local texts = {}
    for _, line in ipairs(lines) do
        if not IsSecretTable(line) and type(line) == "table" then
            local lineType, text = line.type, line.leftText
            if not issecretvalue(lineType) and questTypes[lineType]
                and not issecretvalue(text) and type(text) == "string" and text ~= "" then
                texts[#texts + 1] = StripCodes(text)
            end
        end
    end
    return #texts > 0 and texts or nil
end

-- True when the code that called GameTooltip:AddLine lives in Questie's folder.
local function CalledFromQuestie()
    local stack = debugstack(2, 6, 0)
    if type(stack) ~= "string" then return false end
    for frame in stack:gmatch("[^\n]+") do
        if not frame:find("[C]", 1, true) and not frame:find("[/\\]FlexTip[/\\]") then
            return frame:find("[/\\]Questie[/\\]") ~= nil
        end
    end
    return false
end

local function OnAddLine(tip)
    if tip == GameTooltip and CalledFromQuestie() then
        questieLines[tip:NumLines()] = true
    end
end

local function ResetLineSources()
    for i in pairs(questieLines) do questieLines[i] = nil end
end

local function IsLoaded(addon)
    if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(addon) end
    return IsAddOnLoaded ~= nil and IsAddOnLoaded(addon)
end

---------------------------------------------------------------------------
-- Tooltip hooks
---------------------------------------------------------------------------
local function EndUnit()
    state.isUnit = false
    state.pending = false
    state.unit = nil
    state.info = nil
    state.targetLine = nil
    state.questTexts = nil
    state.classColor = nil
    state.numLines = 0
    state.packed = 0
end

local function OnSetOwner(tip)
    EndUnit()
    ResetLineSources()
    state.category = nil
    state.onMover = false
    state.follow = false
    if tip:IsShown() then SafeCall(FT.ApplyAppearance, FT, tip) end
end

local function OnShow(tip)
    if ShouldHideInCombat() then
        tip:Hide()
        return
    end
    if math.abs(tip:GetScale() - FT.db.scale) > 0.001 then FT:ApplyScale() end
    SafeCall(FT.ApplyAppearance, FT, tip)
end

local function OnHide(tip)
    EndUnit()
    ResetLineSources()
    RestoreColors(tip)
    state.category = nil
    state.onMover = false
    state.follow = false
end

local function OnCleared(tip)
    EndUnit()
    ResetLineSources()
    if tip:IsShown() then SafeCall(FT.ApplyAppearance, FT, tip) end
end

local function OnUpdate(tip)
    if state.follow then AnchorToCursor(tip) end
    if state.isUnit then SafeCall(FT.UpdateRows, FT, tip) end
end

local function OnTooltipSetUnit(tip, data)
    if tip ~= GameTooltip then return end
    EndUnit()
    state.isUnit = true
    local ok, questTexts = pcall(CollectQuestTexts, data)
    state.questTexts = ok and questTexts or nil
    SafeCall(FT.DecorateUnit, FT, tip)
    -- Rows are captured on the next OnUpdate, after other addons have added
    -- or changed lines in their own hooks.
    state.pending = true
end

function FT:SetupTooltipHooks()
    if self.hooked then return end
    self.hooked = true

    hooksecurefunc("GameTooltip_SetDefaultAnchor", OnSetDefaultAnchor)
    hooksecurefunc(GameTooltip, "SetOwner", OnSetOwner)
    GameTooltip:HookScript("OnShow", OnShow)
    GameTooltip:HookScript("OnHide", OnHide)
    GameTooltip:HookScript("OnUpdate", OnUpdate)
    if GameTooltip:HasScript("OnTooltipCleared") then
        GameTooltip:HookScript("OnTooltipCleared", OnCleared)
    end

    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnTooltipSetUnit)
    elseif GameTooltip:HasScript("OnTooltipSetUnit") then
        GameTooltip:HookScript("OnTooltipSetUnit", OnTooltipSetUnit)
    end

    -- With Questie, note which lines it adds so they count as quest rows.
    if IsLoaded("Questie") and debugstack then
        hooksecurefunc(GameTooltip, "AddLine", OnAddLine)
        hooksecurefunc(GameTooltip, "AddDoubleLine", OnAddLine)
        self.questie = true
    end

    local bar = GetStatusBar()
    if bar then
        bar:HookScript("OnShow", function(self)
            if FT.db.hideHealthBar then self:Hide() end
        end)
    end
end

---------------------------------------------------------------------------
-- Live updates and preview
---------------------------------------------------------------------------
-- Apply changed settings to a tooltip that is already on screen.
function FT:RefreshShownTooltip()
    local tip = GameTooltip
    lastX, lastY = nil, nil
    if not tip:IsShown() then return end
    if state.onMover then AnchorToMover(tip) end
    SafeCall(self.ApplyAppearance, self, tip)
    -- Row and collapse changes are picked up by OnUpdate on the next frame.
end

-- Show your own character's tooltip at the anchor, to try settings out.
function FT:ShowPreview()
    if InCombatLockdown() then
        self:Print("the preview is not available in combat.")
        return
    end
    if not self.mover then return end
    local tip = GameTooltip
    local owner = UIParent
    if self.mover:IsShown() then
        owner = self.mover
    elseif self.optionsFrame and self.optionsFrame:IsShown() then
        owner = self.optionsFrame
    end
    tip:SetOwner(owner, "ANCHOR_NONE")
    AnchorToMover(tip)
    tip:SetUnit("player")
    tip:Show()
end

function FT:HidePreview()
    local tip = GameTooltip
    if self.mover and tip:IsShown() and tip:IsOwned(self.mover) then tip:Hide() end
end

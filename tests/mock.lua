-- Minimal mock of the WoW API, just enough to run FlexTip outside the game (Lua 5.1).
local M = {}
M.unknown = {}
M.printed = {}

local function noop() end

---------------------------------------------------------------------------
-- Regions
---------------------------------------------------------------------------
local Region = {}
local regionMT = {
    __index = function(t, k)
        local cls = rawget(t, "__class")
        if cls and cls[k] ~= nil then return cls[k] end
        local v = Region[k]
        if v ~= nil then return v end
        if type(k) == "string" and k:match("^[A-Z]") then
            M.unknown[(rawget(t, "__type") or "?") .. ":" .. k] = true
            return noop
        end
        return nil
    end,
}

local function NewRegion(kind, name, parent, class)
    local r = setmetatable({
        __type = kind, __name = name, __parent = parent, __class = class,
        __points = {}, __w = 0, __h = 0, __shown = true, __scripts = {}, __scale = 1, __alpha = 1,
    }, regionMT)
    if name then _G[name] = r end
    return r
end

function Region:GetName() return self.__name end
function Region:GetParent() return self.__parent end
function Region:SetParent(p) self.__parent = p end
function Region:SetSize(w, h) self.__w, self.__h = w, h end
function Region:SetWidth(w) self.__w = w end
function Region:SetHeight(h) self.__h = h end
function Region:GetWidth() return self.__w end
function Region:GetHeight() return self.__h end
function Region:GetSize() return self.__w, self.__h end
function Region:ClearAllPoints() self.__points = {} end
function Region:SetPoint(point, rel, relPoint, x, y)
    if type(rel) == "number" then rel, relPoint, x, y = nil, nil, rel, relPoint end
    if type(rel) == "string" then rel = _G[rel] end
    rel = rel or self.__parent or _G.UIParent
    relPoint = relPoint or point
    for i, p in ipairs(self.__points) do
        if p[1] == point then table.remove(self.__points, i) break end
    end
    table.insert(self.__points, { point, rel, relPoint, x or 0, y or 0 })
end
function Region:GetPoint(i)
    local p = self.__points[i or 1]
    if p then return p[1], p[2], p[3], p[4], p[5] end
end
function Region:GetNumPoints() return #self.__points end
local function frac(point)
    local fx = point:find("LEFT") and 0 or point:find("RIGHT") and 1 or 0.5
    local fy = point:find("BOTTOM") and 0 or point:find("TOP") and 1 or 0.5
    return fx, fy
end
M.frac = frac
function Region:GetEffectiveScale()
    local s = self.__scale
    local p = self.__parent
    while p do s = s * p.__scale; p = p.__parent end
    return s
end
-- Rect in this region's own coordinate space (single-anchor only).
function Region:GetRect()
    if self == _G.UIParent then return 0, 0, self.__w, self.__h end
    local p = self.__points[1]
    if not p then return nil end
    local rel = p[2]
    local rl, rb, rw, rh = rel:GetRect()
    if not rl then return nil end
    local conv = rel:GetEffectiveScale() / self:GetEffectiveScale()
    local fx, fy = frac(p[3])
    local ax = (rl + rw * fx) * conv + p[4]
    local ay = (rb + rh * fy) * conv + p[5]
    local sx, sy = frac(p[1])
    local w, h = self:GetWidth(), self:GetHeight()
    return ax - w * sx, ay - h * sy, w, h
end
function Region:GetLeft() local l = self:GetRect(); return l end
function Region:GetBottom() local _, b = self:GetRect(); return b end
function Region:GetTop() local _, b, _, h = self:GetRect(); return b and b + h end
function Region:GetRight() local l, _, w = self:GetRect(); return l and l + w end
function Region:Show()
    local was = self.__shown
    self.__shown = true
    if not was then self:RunScript("OnShow") end
end
function Region:Hide()
    local was = self.__shown
    self.__shown = false
    if was then self:RunScript("OnHide") end
end
function Region:SetShown(v) if v then self:Show() else self:Hide() end end
function Region:IsShown() return self.__shown end
function Region:IsVisible()
    local r = self
    while r do if not r.__shown then return false end r = r.__parent end
    return true
end
function Region:SetScale(s) self.__scale = s end
function Region:GetScale() return self.__scale end
function Region:SetAlpha(a) self.__alpha = a end
function Region:GetAlpha() return self.__alpha end
function Region:SetScript(name, fn) self.__scripts[name] = fn and { fn } or nil end
function Region:GetScript(name) local s = self.__scripts[name]; return s and s[1] end
function Region:HookScript(name, fn)
    if not self:HasScript(name) then error("no script " .. name .. " on " .. tostring(self.__type)) end
    local s = self.__scripts[name] or {}
    if #s == 0 then s[1] = false end
    table.insert(s, fn)
    self.__scripts[name] = s
end
local SCRIPTS = { OnShow = 1, OnHide = 1, OnUpdate = 1, OnEnter = 1, OnLeave = 1, OnMouseDown = 1, OnMouseUp = 1,
    OnMouseWheel = 1, OnDragStart = 1, OnDragStop = 1, OnEvent = 1, OnClick = 1, OnValueChanged = 1 }
function Region:HasScript(name)
    if self.__type == "GameTooltip" and (name == "OnTooltipCleared" or name == "OnTooltipSetUnit") then
        return name == "OnTooltipCleared"
    end
    return SCRIPTS[name] ~= nil
end
function Region:RunScript(name, ...)
    local s = self.__scripts[name]
    if not s then return end
    for _, fn in ipairs(s) do if fn then fn(self, ...) end end
end
function Region:CreateFontString(name, layer, template)
    local fs = NewRegion("FontString", name, self)
    fs.__text = nil
    fs.__color = { 1, 1, 1, 1 }
    return fs
end
function Region:CreateTexture(name)
    local t = NewRegion("Texture", name, self)
    t.__vc = { 1, 1, 1, 1 }
    return t
end
-- FontString
function Region:SetText(t)
    if t ~= nil and type(t) ~= "string" and type(t) ~= "number" then error("bad SetText arg " .. type(t)) end
    self.__text = t
    if self.__type == "Button" or self.__type == "FontString" then
        local s = t and tostring(t) or ""
        self.__sw = #s * 6
        if self.__type == "FontString" then self.__h = (t and t ~= "") and 12 or 0 end
    end
end
function Region:SetFormattedText(fmt, ...) self:SetText(string.format(fmt, ...)) end
function Region:GetText() return self.__text end
function Region:GetStringWidth() return self.__sw or 0 end
function Region:SetTextColor(r, g, b, a) self.__color = { r, g, b, a or 1 } end
function Region:SetWordWrap(w) self.__wrap = w and true or false end
function Region:CanWordWrap() return self.__wrap or false end
function Region:GetTextColor() return unpack(self.__color) end
-- Texture
function Region:SetVertexColor(r, g, b, a) self.__vc = { r, g, b, a or 1 } end
function Region:GetVertexColor() return unpack(self.__vc or { 1, 1, 1, 1 }) end
function Region:SetTexture(t) self.__tex = t end
function Region:SetColorTexture(r, g, b, a) self.__vc = { r, g, b, a } end
function Region:SetTexCoord(...) self.__tc = { ... } end
-- Frame
function Region:RegisterEvent(e) M.events[e] = M.events[e] or {}; M.events[e][self] = true end
function Region:UnregisterEvent(e) if M.events[e] then M.events[e][self] = nil end end
function Region:StartMoving() self.__moving = true end
function Region:StopMovingOrSizing() self.__moving = false end
function Region:IsOwned(o) return self.__owner == o end
function Region:SetBackdropColor(...) self.__bdc = { ... } end
function Region:SetBackdropBorderColor(...) self.__bdbc = { ... } end
-- Button
function Region:SetNormalTexture(t) self.__normal = self:CreateTexture(); self.__normal:SetTexture(t) end
function Region:SetPushedTexture(t) self.__pushed = self:CreateTexture(); self.__pushed:SetTexture(t) end
function Region:SetHighlightTexture(t) self.__hl = self:CreateTexture(); self.__hl:SetTexture(t) end
function Region:GetNormalTexture() return self.__normal end
function Region:GetPushedTexture() return self.__pushed end
function Region:GetHighlightTexture() return self.__hl end
function Region:Click(button) self:RunScript("OnClick", button or "LeftButton") end
-- CheckButton
function Region:SetChecked(v) self.__checked = v and true or false end
function Region:GetChecked() return self.__checked end
-- Slider
function Region:SetMinMaxValues(a, b) self.__min, self.__max = a, b end
function Region:SetValue(v)
    v = math.max(self.__min or v, math.min(self.__max or v, v))
    if self.__value ~= v then
        self.__value = v
        self:RunScript("OnValueChanged", v, false)
    end
end
function Region:GetValue() return self.__value or 0 end

---------------------------------------------------------------------------
-- Globals
---------------------------------------------------------------------------
M.events = {}
function M.FireEvent(event, ...)
    for frame in pairs(M.events[event] or {}) do frame:RunScript("OnEvent", event, ...) end
end

_G.UIParent = NewRegion("Frame", "UIParent", nil)
UIParent:SetSize(1920, 1080)
_G.WorldFrame = NewRegion("Frame", "WorldFrame", nil)
_G.UISpecialFrames = {}
_G.tinsert = table.insert
_G.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
_G.strsplit = function(sep, s, limit)
    local out = {}
    local start = 1
    while true do
        if limit and #out == limit - 1 then table.insert(out, s:sub(start)) break end
        local i = s:find(sep, start, true)
        if not i then table.insert(out, s:sub(start)) break end
        table.insert(out, s:sub(start, i - 1))
        start = i + 1
    end
    return unpack(out)
end
_G.print = function(...)
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
    table.insert(M.printed, table.concat(t, " "))
end
_G.SlashCmdList = {}
_G.StaticPopupDialogs = {}
_G.StaticPopup_Show = function(name) M.popup = name end
_G.SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 1, IG_MAINMENU_OPTION_CHECKBOX_OFF = 2 }
_G.PlaySound = noop
_G.YES, _G.NO, _G.TARGET = "Yes", "No", "Target"
_G.RAID_CLASS_COLORS = { PALADIN = { r = 0.96, g = 0.55, b = 0.73 }, MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
_G.FACTION_BAR_COLORS = { [2] = { r = 0.9, g = 0.2, b = 0.1 }, [5] = { r = 0, g = 0.6, b = 0.1 } }
_G.Enum = {
    TooltipDataType = { Unit = 2 },
    TooltipDataLineType = { None = 0, UnitName = 2, QuestObjective = 8, QuestTitle = 17, QuestPlayer = 18 },
}
M.postCalls = {}
M.linePreCalls = {}
_G.TooltipDataProcessor = {
    AddTooltipPostCall = function(kind, fn) table.insert(M.postCalls, { kind, fn }) end,
    AddLinePreCall = function(lineType, fn)
        M.linePreCalls[lineType] = M.linePreCalls[lineType] or {}
        table.insert(M.linePreCalls[lineType], fn)
    end,
}
M.loaded = {}
_G.C_AddOns = {
    GetAddOnMetadata = function(_, key) return key == "Version" and "1.0.0" or nil end,
    IsAddOnLoaded = function(name) return M.loaded[name] == true end,
}
-- debugstack reports whoever the test says is calling (M.stack), else Blizzard code.
M.BLIZZARD_STACK = "Interface/AddOns/FlexTip/Tooltip.lua:500: in function <Interface/AddOns/FlexTip/Tooltip.lua:498>\n"
    .. "[C]: in function `AddLine'\n"
    .. "[string \"@Interface/AddOns/Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua\"]:120: in function `ProcessLine'"
_G.debugstack = function() return M.stack or M.BLIZZARD_STACK end
M.categories = {}
_G.Settings = {
    RegisterCanvasLayoutCategory = function(panel, name) return { panel = panel, name = name } end,
    RegisterAddOnCategory = function(cat) table.insert(M.categories, cat) end,
}

M.combat = false
M.shift = false
M.secret = {}
M.cursor = { 500, 400 }
_G.InCombatLockdown = function() return M.combat end
_G.IsShiftKeyDown = function() return M.shift end
_G.IsControlKeyDown = function() return false end
_G.IsAltKeyDown = function() return false end
_G.GetCursorPosition = function() return M.cursor[1], M.cursor[2] end
_G.issecretvalue = function(v) return v ~= nil and M.secret[v] == true end

M.units = {
    mouseover = { name = "Sulemac Hearthcast", class = "PALADIN", classLocal = "Paladin", player = true,
        guild = "Misär", rank = "Initiate", race = "Human", level = 22, faction = "Alliance" },
    mouseovertarget = { name = "Cowboy", class = "MAGE", classLocal = "Mage", player = true, level = 20, race = "Gnome", faction = "Alliance" },
    player = { name = "Me", class = "MAGE", classLocal = "Mage", player = true, level = 30, race = "Gnome", faction = "Alliance", pvp = true },
}
_G.PVP, _G.FACTION_ALLIANCE, _G.FACTION_HORDE = "PvP", "Alliance", "Horde"
_G.TOOLTIP_UNIT_LEVEL, _G.LEVEL = "Level %s", "Level"
_G.GetGuildInfo = function(u) local d = M.units[u]; if d and d.guild then return d.guild, d.rank, 1 end end
_G.UnitFactionGroup = function(u) local d = M.units[u]; if d and d.faction then return d.faction, d.faction end end
_G.UnitExists = function(u) return M.units[u] ~= nil end
_G.UnitIsPlayer = function(u) return M.units[u] and M.units[u].player end
_G.UnitClass = function(u) local d = M.units[u]; if d then return d.classLocal or d.class, d.class end end
_G.UnitName = function(u) local d = M.units[u]; if d then return d.name, d.realm end end
_G.UnitRace = function(u) local d = M.units[u]; if d and d.player then return d.race, d.race end end
_G.UnitCreatureType = function(u) local d = M.units[u]; return d and d.creatureType end
_G.UnitPVPName = function(u) local d = M.units[u]; return d and (d.pvpName or d.name) end
_G.FOREIGN_SERVER_LABEL = " (*)"
_G.UnitIsUnit = function(a, b) return a == b end
_G.UnitReaction = function() return 5 end

local hooks = {}
_G.hooksecurefunc = function(a, b, c)
    if type(a) == "table" then
        local orig = a[b]
        assert(type(orig) == "function", "hooksecurefunc: no method " .. tostring(b))
        rawset(a, b, function(...) local r = { orig(...) }; c(...); return unpack(r) end)
    else
        local orig = _G[a]
        assert(type(orig) == "function", "hooksecurefunc: no global " .. tostring(a))
        _G[a] = function(...) local r = { orig(...) }; b(...); return unpack(r) end
    end
end

_G.CreateFrame = function(kind, name, parent, template)
    local f = NewRegion(kind, name, parent or nil)
    if parent == nil and kind ~= "GameTooltip" then f.__parent = nil end
    if template and template:find("BackdropTemplate") then
        f.SetBackdrop = function(self, bd) self.__backdrop = bd end
    end
    if kind == "Slider" then
        f.SetThumbTexture = function(self, t) self.__thumb = t end
    end
    return f
end

---------------------------------------------------------------------------
-- GameTooltip
---------------------------------------------------------------------------
local TipClass = {}
local tip = NewRegion("GameTooltip", "GameTooltip", UIParent, TipClass)
tip.__shown = false
tip.__lines = 0
tip.__scripts = {}
tip.NineSlice = {
    Center = UIParent:CreateTexture(), TopLeftCorner = UIParent:CreateTexture(),
}
tip.NineSlice.Center:SetVertexColor(0.09, 0.09, 0.19, 1)
function tip.NineSlice:SetCenterColor(r, g, b, a) self.Center:SetVertexColor(r, g, b, a) end
function tip.NineSlice:SetBorderColor(r, g, b, a) self.TopLeftCorner:SetVertexColor(r, g, b, a) end
local bar = NewRegion("StatusBar", "GameTooltipStatusBar", tip)
bar.__shown = false
tip.StatusBar = bar
NewRegion("GameTooltip", "ShoppingTooltip1", UIParent)
NewRegion("GameTooltip", "ShoppingTooltip2", UIParent)

local function EnsureLine(i)
    local l = _G["GameTooltipTextLeft" .. i]
    if not l then
        l = tip:CreateFontString("GameTooltipTextLeft" .. i)
        local r = tip:CreateFontString("GameTooltipTextRight" .. i)
        r.__shown = false
        if i == 1 then l:SetPoint("TOPLEFT", tip, "TOPLEFT", 10, -10)
        else l:SetPoint("TOPLEFT", _G["GameTooltipTextLeft" .. (i - 1)], "BOTTOMLEFT", 0, -2) end
        r:SetPoint("RIGHT", l, "LEFT", 200, 0)
    end
    return l, _G["GameTooltipTextRight" .. i]
end
function TipClass:NumLines() return self.__lines end
function TipClass:ClearLines()
    for i = 1, self.__lines do
        local l, r = EnsureLine(i)
        l:SetText(nil); r:SetText(nil); r.__shown = false
    end
    self.__lines = 0
    self:RunScript("OnTooltipCleared")
end
function TipClass:AddLine(text, r, g, b, wrap)
    self.__lines = self.__lines + 1
    local l = EnsureLine(self.__lines)
    l:SetText(text)
    l:SetTextColor(r or 1, g or 0.82, b or 0)
    l:SetWordWrap(wrap)
end
function TipClass:AddDoubleLine(a, b2)
    self:AddLine(a)
    local _, r = EnsureLine(self.__lines)
    r:SetText(b2); r.__shown = true
end
function TipClass:SetText(text, r, g, b) self:ClearLines(); self:AddLine(text, r, g, b) end
-- Our model of the C++ layout: blank lines still take 2px spacing (worst case).
function TipClass:Layout()
    local h, w = 20, 0
    for i = 1, self.__lines do
        local l, r = EnsureLine(i)
        h = h + l:GetHeight() + (i > 1 and 2 or 0)
        local lw = l:GetStringWidth() + (r.__shown and r:GetText() and (20 + r:GetStringWidth()) or 0)
        w = math.max(w, lw)
    end
    self.__w, self.__h = w + 20, h
end
function TipClass:Show()
    self:Layout()
    Region.Show(self)
end
function TipClass:SetOwner(owner, anchor)
    if self.__shown then self:Hide() end
    self:ClearLines()
    self.__owner = owner
    self.__unit = nil
    self:ClearAllPoints()
end
function TipClass:GetUnit()
    if self.__unit then return M.units[self.__unit].name, self.__unit end
end
function TipClass:SetUnit(unit)
    self:ClearLines()
    self.__unit = unit
    local d = M.units[unit]
    local T = Enum.TooltipDataLineType
    -- The unit's tooltip data, like the game builds it: one entry per row.
    local lines = { { type = T.UnitName, leftText = d.nameLine or d.name, r = 0.25, g = 0.5, b = 1 } }
    if d.guild then lines[#lines + 1] = { type = T.None, leftText = d.guild .. " - " .. d.rank, r = 0.5, g = 0.5, b = 1 } end
    if d.title then lines[#lines + 1] = { type = T.None, leftText = "<" .. d.title .. ">" } end
    local kind = d.race or d.creatureType
    lines[#lines + 1] = { type = T.None, leftText = d.levelLine or ("Level " .. (d.level or "??") .. (kind and (" " .. kind) or "")) }
    if d.player and d.classLocal and not d.noClassLine then lines[#lines + 1] = { type = T.None, leftText = "|cfff48cba" .. d.classLocal .. "|r" } end
    if d.faction then lines[#lines + 1] = { type = T.None, leftText = d.faction } end
    if d.pvp then lines[#lines + 1] = { type = T.None, leftText = "PvP" } end
    for _, q in ipairs(d.quests or {}) do
        lines[#lines + 1] = { type = T[q.type], leftText = q.text, id = q.id, prefix = q.type == "QuestObjective" and " - " or "" }
    end
    local data = { type = Enum.TooltipDataType.Unit, guid = "Creature-0-0-0-0-1-0", lines = lines }
    self.processingInfo = { tooltipData = data }
    for _, line in ipairs(lines) do
        local consumed = false
        for _, fn in ipairs(M.linePreCalls[line.type] or {}) do
            if fn(self, line) then consumed = true end
        end
        if not consumed then self:AddLine((line.prefix or "") .. line.leftText, line.r or 1, line.g or 1, line.b or 1) end
    end
    self.processingInfo = nil
    bar:Show()
    for _, pc in ipairs(M.postCalls) do pc[2](self, data) end
end
_G.GameTooltip_SetDefaultAnchor = function(t, parent)
    t:SetOwner(parent, "ANCHOR_NONE")
    t:ClearAllPoints()
    t:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -13, 64)
end

function M.Frame(n)
    for _ = 1, (n or 1) do
        tip:RunScript("OnUpdate", 0.016)
    end
end

return M

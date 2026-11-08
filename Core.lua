-- FlexTip core: saved settings, slash commands, key bindings and events.
local ADDON_NAME, FT = ...
_G.FlexTip = FT

local GetMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
FT.version = (GetMetadata and GetMetadata(ADDON_NAME, "Version")) or "1.1.0"

---------------------------------------------------------------------------
-- Choices and ranges (shared by validation and the options window)
---------------------------------------------------------------------------
FT.ANCHOR_MODES = {
    { value = "MOVER", text = "FlexTip anchor" },
    { value = "CURSOR", text = "Mouse cursor" },
    { value = "DEFAULT", text = "Blizzard default" },
}

FT.POINTS = {
    { value = "TOPLEFT", text = "Top left" },
    { value = "TOP", text = "Top" },
    { value = "TOPRIGHT", text = "Top right" },
    { value = "LEFT", text = "Left" },
    { value = "CENTER", text = "Center" },
    { value = "RIGHT", text = "Right" },
    { value = "BOTTOMLEFT", text = "Bottom left" },
    { value = "BOTTOM", text = "Bottom" },
    { value = "BOTTOMRIGHT", text = "Bottom right" },
}

FT.MODIFIERS = {
    { value = "SHIFT", text = "Shift" },
    { value = "CTRL", text = "Ctrl" },
    { value = "ALT", text = "Alt" },
    { value = "NONE", text = "None" },
}

FT.COMBAT_MODES = {
    { value = "NEVER", text = "Never" },
    { value = "WORLD", text = "World tooltips only" },
    { value = "ALL", text = "All tooltips" },
}

local CHOICES = {
    worldAnchor = FT.ANCHOR_MODES,
    frameAnchor = FT.ANCHOR_MODES,
    anchorPoint = FT.POINTS,
    cursorPoint = FT.POINTS,
    expandModifier = FT.MODIFIERS,
    hideInCombat = FT.COMBAT_MODES,
}

local RANGES = {
    scale = { 0.5, 2, 0.01 },
    collapseLines = { 1, 6, 1 },
    cursorX = { -100, 100, 1 },
    cursorY = { -100, 100, 1 },
    bgAlpha = { 0, 1, 0.01 },
}
FT.RANGES = RANGES

FT.defaults = {
    locked = true,
    moverPos = { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -95, y = 110 },
    worldAnchor = "MOVER",       -- tooltips for units/objects in the 3D world
    frameAnchor = "MOVER",       -- tooltips for unit frames, action buttons, ...
    anchorPoint = "BOTTOMRIGHT", -- tooltip corner pinned to the same corner of the anchor
    cursorPoint = "BOTTOMLEFT",  -- tooltip corner pinned to the cursor
    cursorX = 16,
    cursorY = 16,
    scale = 1,
    collapsed = false,
    collapseLines = 1,
    expandModifier = "SHIFT",
    classColorName = true,
    classColorBorder = false,
    hideHealthBar = false,
    showTarget = false,
    -- Rows on player/NPC tooltips (the name always shows).
    rows = { guild = true, level = true, class = true, faction = true, pvp = true, title = true, other = true },
    bgAlpha = 1,                 -- 1 = leave Blizzard's background alone
    hideInCombat = "NEVER",
    debug = false,
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
function FT:Print(msg)
    print("|cff4fc3f7FlexTip|r: " .. tostring(msg))
end

local function ShallowCopy(t)
    local copy = {}
    for k, v in pairs(t) do copy[k] = v end
    return copy
end

local function IsChoice(list, value)
    for _, choice in ipairs(list) do
        if choice.value == value then return true end
    end
    return false
end
FT.IsChoice = IsChoice

local function Round(value, step)
    value = math.floor(value / step + 0.5) * step
    return tonumber(string.format("%.2f", value))
end

local function Sanitize(key, value)
    local default = FT.defaults[key]
    if CHOICES[key] then
        if IsChoice(CHOICES[key], value) then return value end
        return default
    elseif RANGES[key] then
        value = tonumber(value)
        if not value then return default end
        local range = RANGES[key]
        return Round(math.min(range[2], math.max(range[1], value)), range[3])
    elseif type(default) == "boolean" then
        return value and true or false
    end
    return value
end

local function ValidPosition(pos)
    return type(pos) == "table"
        and IsChoice(FT.POINTS, pos.point)
        and IsChoice(FT.POINTS, pos.relPoint)
        and type(pos.x) == "number"
        and type(pos.y) == "number"
end

---------------------------------------------------------------------------
-- Saved settings
---------------------------------------------------------------------------
function FT:InitDB()
    if type(FlexTipDB) ~= "table" then FlexTipDB = {} end
    local db = FlexTipDB
    for key, default in pairs(self.defaults) do
        if type(default) == "table" then
            if type(db[key]) ~= "table" then db[key] = ShallowCopy(default) end
            for k, v in pairs(default) do
                if db[key][k] == nil then
                    db[key][k] = v
                elseif type(v) == "boolean" then
                    db[key][k] = db[key][k] and true or false
                end
            end
        elseif db[key] == nil then
            db[key] = default
        else
            db[key] = Sanitize(key, db[key])
        end
    end
    if not ValidPosition(db.moverPos) then
        db.moverPos = ShallowCopy(self.defaults.moverPos)
    end
    self.db = db
end

-- Change one setting and apply it everywhere.
function FT:Set(key, value)
    value = Sanitize(key, value)
    if self.db[key] == value then
        self:RefreshOptions()
        return
    end
    self.db[key] = value
    if key == "anchorPoint" then
        -- Keep the anchor where it is on screen, but measure it from the new corner.
        self:SaveMoverPosition()
    end
    self:ApplyAll()
end

-- Re-apply every setting (cheap and idempotent).
function FT:ApplyAll()
    if not self.ready then return end
    self:ApplyScale()
    self:UpdateMover()
    self:ApplyHealthBar()
    self:RefreshShownTooltip()
    self:RefreshOptions()
end

-- Show or hide one kind of row on unit tooltips.
function FT:SetRow(row, shown)
    if self.db.rows[row] == nil then return end
    self.db.rows[row] = shown and true or false
    self:ApplyAll()
end

function FT:SetScale(value)
    self:Set("scale", value)
end

function FT:SetLocked(locked)
    self:Set("locked", locked)
    if not locked then
        self:Print("anchor unlocked. Drag it to move, use the mouse wheel or corner grip to scale, right-click to lock.")
    end
end

function FT:ToggleLock()
    self:SetLocked(not self.db.locked)
end

function FT:ToggleCollapse()
    self:Set("collapsed", not self.db.collapsed)
    if self.db.collapsed then
        local key = self.db.expandModifier
        local hint = key ~= "NONE" and (" Hold " .. key:sub(1, 1) .. key:sub(2):lower() .. " to expand.") or ""
        self:Print("unit tooltips collapsed." .. hint)
    else
        self:Print("unit tooltips expanded.")
    end
end

function FT:ResetPosition()
    self.db.moverPos = ShallowCopy(self.defaults.moverPos)
    self:ApplyAll()
    self:Print("anchor position reset.")
end

function FT:ResetAll()
    for key in pairs(self.db) do self.db[key] = nil end
    self:InitDB()
    self:ApplyAll()
    self:Print("all settings reset to defaults.")
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local HELP = {
    "|cffffd100/ftip|r - open or close the options window",
    "|cffffd100/ftip unlock|r, |cffffd100/ftip lock|r - show or hide the draggable anchor",
    "|cffffd100/ftip reset|r - move the anchor back to its default spot",
    "|cffffd100/ftip collapse|r - toggle collapsed unit tooltips",
    "|cffffd100/ftip scale 1.2|r - set the tooltip scale (0.5 to 2)",
    "|cffffd100/ftip preview|r - show a sample tooltip at the anchor",
    "|cffffd100/ftip resetall|r - reset every setting",
}

SLASH_FLEXTIP1 = "/flextip"
SLASH_FLEXTIP2 = "/ftip"
SlashCmdList.FLEXTIP = function(msg)
    local cmd, arg = strsplit(" ", strtrim(msg or ""):lower(), 2)
    if cmd == "" then
        FT:ToggleOptions()
    elseif cmd == "unlock" or cmd == "move" then
        FT:SetLocked(false)
    elseif cmd == "lock" then
        FT:SetLocked(true)
    elseif cmd == "reset" then
        FT:ResetPosition()
    elseif cmd == "collapse" then
        FT:ToggleCollapse()
    elseif cmd == "scale" then
        local value = tonumber(arg)
        if value then
            FT:SetScale(value)
            FT:Print(string.format("scale set to %.2f.", FT.db.scale))
        else
            FT:Print("usage: /ftip scale 1.2")
        end
    elseif cmd == "preview" then
        FT:ShowPreview()
    elseif cmd == "resetall" then
        FT:ResetAll()
    elseif cmd == "debug" then
        FT.db.debug = not FT.db.debug
        FT:Print("debug messages " .. (FT.db.debug and "on." or "off."))
    else
        FT:Print("commands:")
        for _, line in ipairs(HELP) do print("  " .. line) end
    end
end

---------------------------------------------------------------------------
-- Key bindings and the minimap addon compartment
---------------------------------------------------------------------------
BINDING_HEADER_FLEXTIP = "FlexTip"
BINDING_NAME_FLEXTIP_TOGGLECOLLAPSE = "Collapse / expand unit tooltips"
BINDING_NAME_FLEXTIP_TOGGLELOCK = "Lock / unlock the tooltip anchor"
BINDING_NAME_FLEXTIP_OPTIONS = "Open FlexTip options"

function FlexTip_ToggleCollapse() FT:ToggleCollapse() end
function FlexTip_ToggleLock() FT:ToggleLock() end
function FlexTip_ToggleOptions() FT:ToggleOptions() end
function FlexTip_OnAddonCompartmentClick() FT:ToggleOptions() end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            FT:InitDB()
            self:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "PLAYER_LOGIN" then
        if not FT.db then FT:InitDB() end
        FT:CreateMover()
        FT:SetupTooltipHooks()
        FT:RegisterSettingsPanel()
        FT.ready = true
        FT:ApplyAll()
        self:RegisterEvent("PLAYER_REGEN_DISABLED")
    elseif event == "PLAYER_REGEN_DISABLED" then
        FT:OnEnterCombat()
    end
end)

-- Row filtering: hiding guild/level/class/faction/PvP/title/other rows, packing, collapse.
-- Run from the repository root: lua5.1 tests/test_rows.lua tests .
package.path = arg[1] .. "/?.lua;" .. package.path
local M = require("mock")
local ns = {}
for _, file in ipairs({ "Core.lua", "Tooltip.lua", "Mover.lua", "Options.lua" }) do assert(loadfile(arg[2] .. "/" .. file))("FlexTip", ns) end
local FT, tip = ns, GameTooltip
local passed, failed = 0, 0
local function check(cond, msg)
    if cond then passed = passed + 1 else failed = failed + 1; io.write("FAIL: ", msg, "\n") end
end
local function rows()
    local t = {}
    for i = 1, tip:NumLines() do
        local text = _G["GameTooltipTextLeft" .. i]:GetText()
        if text then t[#t + 1] = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") end
    end
    return table.concat(t, " / ")
end
local function hover(unit, parent)
    GameTooltip_SetDefaultAnchor(tip, parent or UIParent)
    tip:SetUnit(unit or "mouseover")
    tip:Show()
    M.Frame(1)
end

-- Old saved settings without `rows` get the new defaults
FlexTipDB = { scale = 1.2, rows = { guild = false } }
M.FireEvent("ADDON_LOADED", "FlexTip"); M.FireEvent("PLAYER_LOGIN")
check(FT.db.rows.guild == false and FT.db.rows.level == true and FT.db.rows.other == true, "rows merged with defaults")
FT:SetRow("guild", true)

-- Classification
hover()
check(rows() == "Sulemac Hearthcast / Misär - Initiate / Level 22 Human / Paladin / Alliance", "default shows all: " .. rows())

-- The user's case: hide guild, faction, class -> name and level only
FT:SetRow("guild", false); FT:SetRow("faction", false); FT:SetRow("class", false)
M.Frame(1)
check(rows() == "Sulemac Hearthcast / Level 22 Human", "name and level only: " .. rows())
check(_G.GameTooltipTextLeft2:GetText() == "Level 22 Human", "level packed into row 2 (no gap)")
check(math.abs(tip:GetHeight() - (20 + 12 + 2 + 12)) < 0.5, "height fits two rows: " .. tip:GetHeight())
-- level row keeps its own color after moving up
local r, g, b = _G.GameTooltipTextLeft2:GetTextColor()
check(r == 1 and g == 1 and b == 1, "moved row keeps its color")

-- Holding Shift shows the full tooltip
M.shift = true; M.Frame(1)
check(rows() == "Sulemac Hearthcast / Misär - Initiate / Level 22 Human / Paladin / Alliance", "shift shows all: " .. rows())
local r2, g2, b2 = _G.GameTooltipTextLeft2:GetTextColor()
check(r2 == 0.5 and g2 == 0.5 and b2 == 1, "guild color restored")
M.shift = false; M.Frame(1)
check(rows() == "Sulemac Hearthcast / Level 22 Human", "release shift hides again")

-- Another addon adds a line afterwards (counted as "other")
tip:AddLine("Target: Cowboy"); tip:Show(); M.Frame(1)
check(rows() == "Sulemac Hearthcast / Level 22 Human / Target: Cowboy", "late addon row shown: " .. rows())
FT:SetRow("other", false); M.Frame(1)
check(rows() == "Sulemac Hearthcast / Level 22 Human", "other rows hidden: " .. rows())
FT:SetRow("other", true); M.Frame(1)

-- Collapse counts visible rows only
FT:Set("collapsed", true); FT:Set("collapseLines", 2); M.Frame(1)
check(rows() == "Sulemac Hearthcast / Level 22 Human", "collapse 2 counts visible rows: " .. rows())
FT:Set("collapseLines", 1); M.Frame(1)
check(rows() == "Sulemac Hearthcast", "collapse 1: " .. rows())
FT:Set("collapsed", false); M.Frame(1)
check(rows() == "Sulemac Hearthcast / Level 22 Human / Target: Cowboy", "uncollapse: " .. rows())
tip:Hide()

-- Re-showing in the same tooltip (refresh) keeps working
hover(); hover()
check(rows() == "Sulemac Hearthcast / Level 22 Human", "second hover filtered: " .. rows())
tip:Hide()

-- Our own target row is never filtered as "other"
FT:Set("showTarget", true); FT:SetRow("other", false)
hover()
check(rows():find("Target: Cowboy", 1, true) ~= nil, "own target row kept: " .. rows())
FT:Set("showTarget", false); FT:SetRow("other", true)
tip:Hide()

-- Hiding the level row too, and the PvP row on your own tooltip
FT:SetRow("level", false); FT:SetRow("pvp", false)
hover("player")
check(rows() == "Me", "player with level and pvp hidden: " .. rows())
FT:SetRow("pvp", true); M.Frame(1)
check(rows() == "Me / PvP", "pvp back: " .. rows())
tip:Hide()
FT:SetRow("level", true)

-- NPC title row
M.units.npc = { name = "Talonaxe", title = "Gryphon Master", level = 30, race = nil }
hover("npc")
check(rows() == "Talonaxe / <Gryphon Master> / Level 30", "npc default: " .. rows())
FT:SetRow("title", false); M.Frame(1)
check(rows() == "Talonaxe / Level 30", "npc title hidden: " .. rows())
FT:SetRow("title", true)
tip:Hide()

-- Secret text rows always show; unknown unit -> unrecognized rows always show
M.secret["Misär - Initiate"] = true
FT:SetRow("guild", false); FT:SetRow("other", false)
hover()
check(rows():find("Misär", 1, true) ~= nil, "secret row stays visible: " .. rows())
M.secret["Misär - Initiate"] = nil
tip:Hide()

-- Settings window still builds and refreshes with the new column
FT:ToggleOptions()
check(FlexTipOptionsFrame:IsShown(), "options open")
FT:SetRow("guild", true)
FT:ToggleOptions()

io.write(string.format("test_rows: %d passed, %d failed\n", passed, failed))
local errs = 0
for _, s in ipairs(M.printed) do if s:find("ff6060") then errs = errs + 1; io.write("  ", s, "\n") end end
io.write("debug errors: ", errs, "\n")
os.exit((failed == 0 and errs == 0) and 0 or 1)

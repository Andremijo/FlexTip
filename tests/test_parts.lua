-- Parts of rows: realm and title in the name, guild rank, level / race (or creature
-- type) / class on the level row, and Questie's quest givers vs objectives.
-- Run from the repository root: lua5.1 tests/test_parts.lua tests .
package.path = arg[1] .. "/?.lua;" .. package.path
local M = require("mock")
assert(loadfile(arg[1] .. "/questie_mock.lua"))(M)
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
        if text then
            text = text:gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", "")
            t[#t + 1] = text
        end
    end
    return table.concat(t, " / ")
end
local function hover(unit)
    GameTooltip_SetDefaultAnchor(tip, UIParent)
    tip:SetUnit(unit)
    tip:Show()
    M.Frame(1)
end
local function set(row, value) FT:SetRow(row, value); M.Frame(1) end

M.units.vex = { name = "Vex", realm = "Argent Dawn", nameLine = "Sergeant Vex-Argent Dawn", pvpName = "Sergeant Vex",
    player = true, class = "WARRIOR", classLocal = "Warrior", race = "Orc", level = 30, faction = "Horde" }
M.units.retail = { name = "Lyra", player = true, class = "PALADIN", classLocal = "Paladin", race = "Human",
    levelLine = "Level 80 Human |cfff48cbaPaladin|r (Player)", noClassLine = true, faction = "Alliance" }
M.units.gnoll = { name = "Riverpaw Gnoll", level = 8, creatureType = "Humanoid", giver = "Gnoll Bounty", quests = {
    { type = "QuestTitle", text = "Riverpaw Gnolls" },
    { type = "QuestObjective", text = "Riverpaw Gnoll slain: 2/8" },
} }

-- Settings saved by 1.2.0: "level" off hid the race too, "quest" off hid quest givers too.
FlexTipDB = { rows = { level = false, quest = false } }
M.FireEvent("ADDON_LOADED", "FlexTip"); M.FireEvent("PLAYER_LOGIN")
check(FT.db.rows.race == false and FT.db.rows.questGivers == false and FT.db.rows.guildRank == true,
    "old hidden rows stay hidden after upgrading")
FT:ResetAll()

local DEFAULT = "Sulemac Hearthcast / Misär - Initiate / Level 22 Human / Paladin / Alliance"
hover("mouseover")
check(rows() == DEFAULT, "default tooltip unchanged: " .. rows())

-- Guild
set("guildRank", false)
check(rows() == "Sulemac Hearthcast / Misär / Level 22 Human / Paladin / Alliance", "rank removed: " .. rows())
set("guild", false)
check(rows() == "Sulemac Hearthcast / Level 22 Human / Paladin / Alliance", "guild row hidden: " .. rows())
set("guild", true); set("guildRank", true)
check(rows() == DEFAULT, "guild back: " .. rows())

-- Level row
set("race", false)
check(rows() == "Sulemac Hearthcast / Misär - Initiate / Level 22 / Paladin / Alliance", "race removed: " .. rows())
set("race", true); set("level", false)
check(rows() == "Sulemac Hearthcast / Misär - Initiate / Human / Paladin / Alliance", "level removed: " .. rows())
set("race", false)
check(rows() == "Sulemac Hearthcast / Misär - Initiate / Paladin / Alliance", "level row hidden: " .. rows())
local r, g, b = _G.GameTooltipTextLeft3:GetTextColor()
check(r == 0.96 or (r == 1 and g == 1 and b == 1), "moved rows keep their colors")

-- The user's example: name and level only
set("level", true); set("guild", false); set("class", false); set("faction", false)
check(rows() == "Sulemac Hearthcast / Level 22", "name and level only: " .. rows())

-- Holding Shift shows every row as the game wrote it
M.shift = true; M.Frame(1)
check(rows() == DEFAULT, "shift shows the original tooltip: " .. rows())
M.shift = false; M.Frame(1)
check(rows() == "Sulemac Hearthcast / Level 22", "release shift: " .. rows())

-- Collapse counts the rows that are left
set("guild", true); set("guildRank", false)
FT:Set("collapsed", true); FT:Set("collapseLines", 2); M.Frame(1)
check(rows() == "Sulemac Hearthcast / Misär", "collapse 2 after shortening: " .. rows())
FT:Set("collapsed", false); FT:ResetAll(); M.Frame(1)
check(rows() == DEFAULT, "reset all restores the tooltip: " .. rows())
tip:Hide()

-- Name row: realm and title
hover("vex")
check(rows():find("^Sergeant Vex%-Argent Dawn / ") ~= nil, "name with title and realm: " .. rows())
set("realm", false)
check(rows():find("^Sergeant Vex / ") ~= nil, "realm removed: " .. rows())
set("playerTitle", false)
check(rows():find("^Vex / ") ~= nil, "title and realm removed: " .. rows())
set("realm", true)
check(rows():find("^Vex%-Argent Dawn / ") ~= nil, "title removed: " .. rows())
set("playerTitle", true)
tip:Hide()

-- Class on the level row (retail layout)
hover("retail")
check(rows() == "Lyra / Level 80 Human Paladin (Player) / Alliance", "retail default: " .. rows())
set("class", false)
check(rows() == "Lyra / Level 80 Human / Alliance", "class removed from the level row: " .. rows())
set("class", true); set("race", false)
check(rows() == "Lyra / Level 80 Paladin / Alliance", "race removed, class kept: " .. rows())
set("race", true)
tip:Hide()

-- NPC: creature type, and Questie's quest givers vs objectives
hover("gnoll")
check(rows() == "Riverpaw Gnoll / Level 8 Humanoid / [6] Gnoll Bounty / [5] Riverpaw Gnolls / Riverpaw Gnoll slain: 2/8",
    "npc default: " .. rows())
set("race", false)
check(rows():find("^Riverpaw Gnoll / Level 8 / ") ~= nil, "creature type removed: " .. rows())
set("race", true); set("questGivers", false)
check(rows() == "Riverpaw Gnoll / Level 8 Humanoid / [5] Riverpaw Gnolls / Riverpaw Gnoll slain: 2/8", "quest givers hidden: " .. rows())
set("questGivers", true); set("quest", false)
check(rows() == "Riverpaw Gnoll / Level 8 Humanoid / [6] Gnoll Bounty", "objectives hidden: " .. rows())
set("quest", true)
FT:Set("collapsed", true); FT:Set("collapseLines", 1); M.Frame(1)
check(rows() == "Riverpaw Gnoll / [6] Gnoll Bounty / [5] Riverpaw Gnolls / Riverpaw Gnoll slain: 2/8",
    "collapsed keeps both kinds of quest rows: " .. rows())
FT:Set("collapsed", false); M.Frame(1)
tip:Hide()

-- A secret guild row can't be shortened, so it shows as it came
M.secret["Misär - Initiate"] = true
set("guildRank", false)
hover("mouseover")
check(rows():find("Misär - Initiate", 1, true) ~= nil, "secret row left alone: " .. rows())
tip:Hide()

-- The options window builds with the new checkboxes
FT:ToggleOptions()
check(FlexTipOptionsFrame:IsShown(), "options open")
FT:ToggleOptions()

io.write(string.format("test_parts: %d passed, %d failed\n", passed, failed))
local errs = 0
for _, s in ipairs(M.printed) do if s:find("ff6060") then errs = errs + 1; io.write("  ", s, "\n") end end
os.exit((failed == 0 and errs == 0) and 0 or 1)

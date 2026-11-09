-- FlexTip with Questie: quest rows survive row hiding and collapse, in and out of instances.
-- Run from the repository root: lua5.1 tests/test_questie.lua tests .
package.path = arg[1] .. "/?.lua;" .. package.path
local M = require("mock")
-- Questie loads before FlexTip (alphabetical isn't guaranteed, so this is the harder order:
-- its post-call runs before ours).
local Q = assert(loadfile(arg[1] .. "/questie_mock.lua"))(M)
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

M.units.kobold = { name = "Kobold Vermin", level = 5, quests = {
    { type = "QuestTitle", text = "Kobold Camp Cleanup", id = 7 },
    { type = "QuestObjective", text = "Kobold Vermin slain: 3/10" },
} }
local ALL = "Kobold Vermin / Level 5 / [5] Kobold Camp Cleanup / Kobold Vermin slain: 3/10"

M.FireEvent("ADDON_LOADED", "FlexTip"); M.FireEvent("PLAYER_LOGIN")
check(FT.questie == true, "Questie detected")
check(FT.db.rows.quest == true and FT.db.collapseKeepsQuests == true, "quest defaults")

hover("kobold")
check(rows() == ALL, "Questie rows shown by default: " .. rows())

-- Hiding "other" rows keeps Questie's rows; a non-Questie addon row is still "other".
tip:AddLine("Item level: 5"); tip:Show(); M.Frame(1)
FT:SetRow("other", false); M.Frame(1)
check(rows() == ALL, "other hidden, quest rows kept: " .. rows())
FT:SetRow("other", true); M.Frame(1)
check(rows() == ALL .. " / Item level: 5", "other row back: " .. rows())
tip:Hide()

-- Hiding the level row packs the quest rows up.
FT:SetRow("level", false)
hover("kobold")
check(rows() == "Kobold Vermin / [5] Kobold Camp Cleanup / Kobold Vermin slain: 3/10", "level hidden: " .. rows())
check(_G.GameTooltipTextLeft2:GetText():find("Kobold Camp Cleanup", 1, true), "quest title moved to row 2")
FT:SetRow("level", true); M.Frame(1)

-- Collapse: quest rows stay by default and don't use up the row limit.
FT:Set("collapsed", true); FT:Set("collapseLines", 1); M.Frame(1)
check(rows() == "Kobold Vermin / [5] Kobold Camp Cleanup / Kobold Vermin slain: 3/10", "collapsed keeps quests: " .. rows())
FT:Set("collapseKeepsQuests", false); M.Frame(1)
check(rows() == "Kobold Vermin", "collapsed without quests: " .. rows())
M.shift = true; M.Frame(1)
check(rows() == ALL, "shift shows everything: " .. rows())
M.shift = false
FT:Set("collapseKeepsQuests", true); FT:Set("collapsed", false); M.Frame(1)

-- Unticking quest progress hides Questie's rows.
FT:SetRow("quest", false); M.Frame(1)
check(rows() == "Kobold Vermin / Level 5", "quest rows hidden: " .. rows())
FT:SetRow("quest", true); M.Frame(1)

-- A rebuild of the same unit (the game refreshing the tooltip) gives no duplicates.
tip:SetUnit("kobold"); M.Frame(2)
check(rows() == ALL, "no duplicate rows after rebuild: " .. rows())
tip:Hide()

-- Inside an instance: Questie re-adds the game's rows with secret text.
Q.inInstance = true
FT:SetRow("level", false)
hover("kobold")
check(rows() == "Kobold Vermin / Kobold Camp Cleanup / Kobold Vermin slain: 3/10", "instance rows packed: " .. rows())
check(_G.GameTooltipTextLeft3:CanWordWrap() == true and _G.GameTooltipTextLeft2:CanWordWrap() == false,
    "word wrap moves with the row")
FT:SetRow("other", false); M.Frame(1)
check(rows() == "Kobold Vermin / Kobold Camp Cleanup / Kobold Vermin slain: 3/10", "secret quest rows aren't 'other'")
FT:SetRow("quest", false); M.Frame(1)
check(rows() == "Kobold Vermin", "secret quest rows can be hidden: " .. rows())
FT:SetRow("quest", true); FT:SetRow("other", true); FT:SetRow("level", true)
tip:Hide()
Q.inInstance = false

-- The other hook order: FlexTip's post-call before Questie's.
table.insert(M.postCalls, table.remove(M.postCalls, 1))
FT:SetRow("other", false)
hover("kobold")
check(rows() == ALL, "FlexTip-first order keeps quest rows: " .. rows())
FT:SetRow("other", true)
tip:Hide()

-- Rows added by Blizzard code are never taken for Questie's.
hover("mouseover")
check(rows():find("Misär", 1, true) ~= nil, "player tooltip unaffected: " .. rows())
tip:Hide()

io.write(string.format("test_questie: %d passed, %d failed\n", passed, failed))
local errs = 0
for _, s in ipairs(M.printed) do if s:find("ff6060") then errs = errs + 1; io.write("  ", s, "\n") end end
os.exit((failed == 0 and errs == 0) and 0 or 1)

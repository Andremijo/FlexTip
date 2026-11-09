-- Without Questie: the game's own quest rows count as quest progress.
-- Run from the repository root: lua5.1 tests/test_quest_native.lua tests .
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
        if text then t[#t + 1] = text end
    end
    return table.concat(t, " / ")
end

M.units.kobold = { name = "Kobold Vermin", level = 5, quests = {
    { type = "QuestTitle", text = "Kobold Camp Cleanup" },
    { type = "QuestObjective", text = "Kobold Vermin slain: 3/10" },
} }
M.FireEvent("ADDON_LOADED", "FlexTip"); M.FireEvent("PLAYER_LOGIN")
check(not FT.questie, "no Questie hooks without Questie")

FT:SetRow("other", false); FT:SetRow("level", false)
GameTooltip_SetDefaultAnchor(tip, UIParent); tip:SetUnit("kobold"); tip:Show(); M.Frame(1)
check(rows() == "Kobold Vermin / Kobold Camp Cleanup /  - Kobold Vermin slain: 3/10", "native quest rows kept: " .. rows())
FT:SetRow("quest", false); M.Frame(1)
check(rows() == "Kobold Vermin", "native quest rows hidden: " .. rows())

io.write(string.format("test_quest_native: %d passed, %d failed\n", passed, failed))
local errs = 0
for _, s in ipairs(M.printed) do if s:find("ff6060") then errs = errs + 1; io.write("  ", s, "\n") end end
os.exit((failed == 0 and errs == 0) and 0 or 1)

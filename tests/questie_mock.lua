-- A stand-in for Questie's Forever tooltip behaviour (Modules/Tooltips/Tooltip.lua):
--  * readable quest rows from the game are dropped by a line pre-call and Questie's
--    unit post-call adds its own rows instead;
--  * inside instances the game's rows are secret, so the pre-call re-adds them
--    restyled (objectives wrap) and the post-call adds nothing.
local M = ...
local Q = { enabled = true, inInstance = false }
local STACK = "Interface/AddOns/FlexTip/Tooltip.lua:500: in function <Interface/AddOns/FlexTip/Tooltip.lua:498>\n"
    .. "[C]: in function `AddLine'\n"
    .. "Interface/AddOns/Questie/Modules/Tooltips/TooltipHandler.lua:52: in function `AddUnitDataToTooltip'"

local function Add(tip, text, r, g, b, wrap)
    M.stack = STACK
    tip:AddLine(text, r, g, b, wrap)
    M.stack = nil
end

for _, name in ipairs({ "QuestTitle", "QuestObjective", "QuestPlayer" }) do
    TooltipDataProcessor.AddLinePreCall(Enum.TooltipDataLineType[name], function(tip, line)
        if not Q.enabled then return end
        if Q.inInstance then
            local text = name == "QuestTitle" and line.leftText or ("   " .. line.leftText)
            M.secret[text] = true
            Add(tip, text, 1, 0.82, 0, name ~= "QuestTitle")
        end
        return true
    end)
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tip)
    if not Q.enabled or Q.inInstance then return end
    local d = M.units[tip.__unit]
    for _, q in ipairs(d.quests or {}) do
        if q.type == "QuestTitle" then
            Add(tip, "|TInterface\\Addons\\Questie\\Icons\\tooltip_complete.png:14|t|cFFFFFF00[5] " .. q.text .. "|r")
        else
            Add(tip, "   |cFFEEEEEE" .. q.text .. "|r")
        end
    end
end)

M.loaded.Questie = true
return Q

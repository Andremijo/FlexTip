-- Clicks every checkbox, slider and button in the options window and fails on any Lua error.
-- Run from the repository root: lua5.1 tests/test_widgets.lua tests .
package.path = arg[1] .. "/?.lua;" .. package.path
local M = require("mock")
local created = {}
local origCF = CreateFrame
CreateFrame = function(...) local f = origCF(...); created[#created + 1] = f; return f end
local ns = {}
for _, file in ipairs({ "Core.lua", "Tooltip.lua", "Mover.lua", "Options.lua" }) do assert(loadfile(arg[2] .. "/" .. file))("FlexTip", ns) end
M.FireEvent("ADDON_LOADED", "FlexTip"); M.FireEvent("PLAYER_LOGIN")
local before = #created
ns:ToggleOptions()
local counts, errors = {}, 0
for i = before + 1, #created do
  local f = created[i]
  local t = f.__type
  local ok, err = pcall(function()
    if t == "CheckButton" then f.__checked = not f.__checked; f:RunScript("OnClick", "LeftButton")
    elseif t == "Slider" then f:SetValue(f.__max); f:SetValue(f.__min); f:RunScript("OnMouseWheel", 1)
    elseif t == "Button" then f:RunScript("OnClick", "LeftButton"); f:RunScript("OnClick", "RightButton"); f:RunScript("OnEnter"); f:RunScript("OnLeave") end
  end)
  if ok then counts[t] = (counts[t] or 0) + 1 else errors = errors + 1; io.write("ERR ", t, ": ", tostring(err), "\n") end
end
local total = 0
for _, v in pairs(counts) do total = total + v end
io.write(string.format("test_widgets: clicked %d widgets, %d errors\n", total, errors))
os.exit((errors == 0 and total > 0) and 0 or 1)

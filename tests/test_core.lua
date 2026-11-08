-- Core behaviour: anchoring, collapse, appearance, scale, mover, options, slash commands.
-- Run from the repository root: lua5.1 tests/test_core.lua tests .
package.path = arg[1] .. "/?.lua;" .. package.path
local M = require("mock")
local ADDON = arg[2]

local ns = {}
for _, file in ipairs({ "Core.lua", "Tooltip.lua", "Mover.lua", "Options.lua" }) do
    local chunk = assert(loadfile(ADDON .. "/" .. file))
    chunk("FlexTip", ns)
end
local FT = ns
local tip = GameTooltip
local passed, failed = 0, 0
local function print_real(s) io.stdout:write(s, "\n") end
local function check(cond, msg)
    if cond then passed = passed + 1 else failed = failed + 1; print_real("FAIL: " .. msg) end
end

M.FireEvent("ADDON_LOADED", "FlexTip")
M.FireEvent("PLAYER_LOGIN")
check(FT.ready, "ready after login")
check(FT.mover and not FT.mover:IsShown(), "mover hidden while locked")
check(#M.categories == 1, "settings category registered")

local function hover(unit, parent)
    GameTooltip_SetDefaultAnchor(tip, parent or UIParent)
    tip:SetUnit(unit or "mouseover")
    tip:Show()
    M.Frame(1)
end
local function line(i) return _G["GameTooltipTextLeft" .. i]:GetText() end

-- 1. World tooltip pinned to the mover
hover()
local p, rel, rp = tip:GetPoint(1)
check(rel == FT.mover and p == "BOTTOMRIGHT" and rp == "BOTTOMRIGHT", "world tooltip anchored to mover BOTTOMRIGHT")
local r, g, b = _G.GameTooltipTextLeft1:GetTextColor()
check(math.abs(r - 0.96) < 0.01, "name class colored")
check(tip:NumLines() == 5, "5 lines, no target line by default")
local fullH = tip:GetHeight()

-- 2. Collapse
FT:ToggleCollapse()
M.Frame(2)
check(line(1) == "Sulemac Hearthcast" and line(2) == nil and line(5) == nil, "collapsed to 1 line")
check(tip:GetHeight() < fullH and math.abs(tip:GetHeight() - 32) < 0.5, "height fitted to one line, got " .. tip:GetHeight())
-- hold shift to expand
M.shift = true; M.Frame(1)
check(line(2) == "Misär - Initiate" and line(5) == "Alliance", "shift expands")
check(math.abs(tip:GetHeight() - fullH) < 0.5, "expanded height restored")
local r2, g2, b2 = _G.GameTooltipTextLeft2:GetTextColor()
check(r2 == 0.5 and g2 == 0.5 and b2 == 1, "restored line color")
M.shift = false; M.Frame(1)
check(line(2) == nil, "release shift collapses again")
-- another addon adds a line while collapsed
tip:AddLine("Item level: 600"); tip:Show(); M.Frame(1)
check(line(6) == nil, "late line hidden while collapsed")
M.shift = true; M.Frame(1)
check(line(6) == "Item level: 600", "late line restored on expand")
M.shift = false; M.Frame(1)
-- change lines kept while collapsed
FT:Set("collapseLines", 3); M.Frame(1)
check(line(3) == "Level 22 Human" and line(4) == nil, "collapseLines=3 shows 3 lines")
FT:Set("collapseLines", 1); M.Frame(1)
check(line(2) == nil and line(3) == nil, "back to 1 line")
FT:ToggleCollapse(); M.Frame(1)
check(line(6) == "Item level: 600" and line(2) ~= nil, "uncollapse restores all")
tip:Hide()

-- 3. Target line and border
FT:Set("showTarget", true); FT:Set("classColorBorder", true)
hover()
check(tip:NumLines() == 6 and line(6):find("Cowboy"), "target line added: " .. tostring(line(6)))
local br = tip.NineSlice.TopLeftCorner:GetVertexColor()
check(math.abs(br - 0.96) < 0.01, "border class colored")
tip:Hide()
br = tip.NineSlice.TopLeftCorner:GetVertexColor()
check(br == 1, "border restored on hide")

-- 4. Background alpha applies to any tooltip, restored on hide
FT:Set("bgAlpha", 0.5)
tip:SetOwner(UIParent, "ANCHOR_NONE"); tip:AddLine("Some item"); tip:Show()
check(select(4, tip.NineSlice.Center:GetVertexColor()) == 0.5, "bg alpha applied on show")
tip:Hide()
check(select(4, tip.NineSlice.Center:GetVertexColor()) == 1, "bg alpha restored on hide")
FT:Set("bgAlpha", 1)

-- 5. Scale
FT:SetScale(1.37)
check(tip:GetScale() == 1.37 and ShoppingTooltip1:GetScale() == 1.37, "scale applied")
FT:SetScale(9)
check(FT.db.scale == 2, "scale clamped to 2")
FT:SetScale(1)

-- 6. Cursor mode
FT:Set("worldAnchor", "CURSOR")
hover()
local cp, crel, crp, cx, cy = tip:GetPoint(1)
check(cp == "BOTTOMLEFT" and crel == UIParent and cx == 516 and cy == 416, "cursor anchor " .. tostring(cx) .. "," .. tostring(cy))
M.cursor = { 700, 300 }; M.Frame(1)
cp, crel, crp, cx, cy = tip:GetPoint(1)
check(cx == 716 and cy == 316, "follows cursor")
tip:SetOwner(UIParent, "ANCHOR_RIGHT"); tip:AddLine("x"); tip:Show()
M.cursor = { 100, 100 }; M.Frame(1)
cp, crel, crp, cx, cy = tip:GetPoint(1)
check(cx ~= 116, "stops following after a non-default SetOwner")
tip:Hide()
FT:Set("worldAnchor", "MOVER")

-- 7. Frame tooltips use frameAnchor
FT:Set("frameAnchor", "DEFAULT")
local unitFrame = CreateFrame("Button", nil, UIParent)
hover("mouseover", unitFrame)
p, rel = tip:GetPoint(1)
check(rel == UIParent and p == "BOTTOMRIGHT", "frame tooltip left at Blizzard default")
tip:Hide()
FT:Set("frameAnchor", "MOVER")

-- 8. Hide in combat
FT:Set("hideInCombat", "WORLD")
M.combat = true
hover()
check(not tip:IsShown(), "world tooltip hidden in combat")
hover("mouseover", unitFrame)
check(tip:IsShown(), "frame tooltip still shown in combat (WORLD mode)")
tip:Hide()
M.combat = false
hover()
check(tip:IsShown(), "shown out of combat")
M.FireEvent("PLAYER_REGEN_DISABLED")
check(not tip:IsShown(), "hidden when entering combat")
FT:Set("hideInCombat", "NEVER")

-- 9. Health bar
FT:Set("hideHealthBar", true)
hover()
check(not GameTooltipStatusBar:IsShown(), "health bar hidden")
tip:Hide()
FT:Set("hideHealthBar", false)

-- 10. Mover: unlock, drag, anchorPoint change keeps it in place
FT:SetLocked(false)
check(FT.mover:IsShown(), "mover shown when unlocked")
local m = FT.mover
local l0, b0 = m:GetLeft(), m:GetBottom()
check(math.abs(l0 - (1920 - 95 - 220)) < 0.01 and math.abs(b0 - 110) < 0.01, "default mover position " .. l0 .. "," .. b0)
m:RunScript("OnMouseDown", "LeftButton")
m:RunScript("OnDragStart")
m:ClearAllPoints(); m:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 300, 700)
m:RunScript("OnDragStop")
m:RunScript("OnMouseUp", "LeftButton")
check(FT.db.moverPos.point == "BOTTOMRIGHT" and math.abs(m:GetLeft() - 300) < 0.11 and math.abs(m:GetTop() - 700) < 0.11,
    "drag saved: " .. FT.db.moverPos.x .. "," .. FT.db.moverPos.y)
check(not (tip:IsShown() and tip:IsOwned(m)), "drag does not trigger preview")
m:RunScript("OnMouseDown", "LeftButton")
m:RunScript("OnMouseUp", "LeftButton")
check(tip:IsShown() and tip:IsOwned(m), "click on mover shows preview")
p, rel, rp = tip:GetPoint(1)
check(p == "BOTTOMRIGHT" and rel == m, "preview pinned to mover")
FT:Set("anchorPoint", "TOPLEFT")
check(FT.db.moverPos.point == "TOPLEFT" and math.abs(m:GetLeft() - 300) < 0.11 and math.abs(m:GetTop() - 700) < 0.11,
    "anchorPoint change keeps mover in place")
p, rel, rp = tip:GetPoint(1)
check(p == "TOPLEFT" and rel == m, "shown tooltip re-pinned to new corner")
-- grip scale
local grip = m.grip
check(grip:GetPoint(1) == "BOTTOMRIGHT", "grip opposite of TOPLEFT")
M.cursor = { 100, 100 }
grip:RunScript("OnMouseDown", "LeftButton")
M.cursor = { 175, 25 }
grip:RunScript("OnUpdate")
grip:RunScript("OnMouseUp")
check(math.abs(FT.db.scale - 2) < 0.001, "grip scaled up to " .. FT.db.scale)
m:RunScript("OnMouseWheel", -1)
check(math.abs(FT.db.scale - 1.95) < 0.001, "wheel scales down " .. FT.db.scale)
m:RunScript("OnMouseUp", "RightButton")
check(not m:IsShown() and FT.db.locked, "right-click locks")
check(not tip:IsShown(), "preview hidden on lock")
FT:ResetPosition()
check(FT.db.moverPos.point == "BOTTOMRIGHT", "reset position")

-- 11. Options window
FT:ToggleOptions()
local f = FlexTipOptionsFrame
check(f and f:IsShown(), "options shown")
local count = 0
for _ in pairs(UISpecialFrames) do count = count + 1 end
check(count == 1, "registered for Escape")
-- exercise every widget's Refresh and a few interactions via the real widgets
FT:RefreshOptions()
FT:Set("expandModifier", "CTRL"); FT:Set("hideInCombat", "ALL"); FT:Set("cursorX", -500)
check(FT.db.cursorX == -100, "cursorX clamped")
FT:Set("hideInCombat", "BOGUS")
check(FT.db.hideInCombat == "NEVER", "invalid choice falls back to default")
FT:ToggleOptions()
check(not f:IsShown(), "options toggled off")

-- 12. Slash commands
SlashCmdList.FLEXTIP("scale 1.25")
check(FT.db.scale == 1.25, "slash scale")
SlashCmdList.FLEXTIP("unlock"); check(not FT.db.locked, "slash unlock")
SlashCmdList.FLEXTIP("lock"); check(FT.db.locked, "slash lock")
SlashCmdList.FLEXTIP("help")
SlashCmdList.FLEXTIP("collapse"); check(FT.db.collapsed, "slash collapse")
SlashCmdList.FLEXTIP("collapse")
FlexTip_ToggleCollapse(); FlexTip_ToggleCollapse()
SlashCmdList.FLEXTIP("preview"); check(tip:IsShown(), "slash preview")
SlashCmdList.FLEXTIP("resetall")
check(FT.db.scale == 1 and FT.db.anchorPoint == "BOTTOMRIGHT" and FlexTipDB == FT.db, "reset all")

-- 13. Secret values do not raise errors
FT:Set("showTarget", true); FT:Set("collapsed", true); FT:Set("debug", true)
M.secret["Cowboy"] = true
local ok, err = pcall(hover)
check(ok, "hover with secret target name: " .. tostring(err))
check(line(2) == nil, "collapse still works with secret target")
tip:Hide()
M.secret["Cowboy"] = nil

-- 14. Saved variables sanitized on load
FlexTipDB = { scale = "abc", anchorPoint = "NOWHERE", moverPos = { point = "X" }, collapseLines = 3.7 }
FT:InitDB()
check(FT.db.scale == 1 and FT.db.anchorPoint == "BOTTOMRIGHT" and FT.db.moverPos.point == "BOTTOMRIGHT" and FT.db.collapseLines == 4,
    "bad saved values repaired (collapseLines=" .. tostring(FT.db.collapseLines) .. ")")

print_real(string.format("test_core: %d passed, %d failed", passed, failed))
local errs = {}
for _, s in ipairs(M.printed) do if s:find("ff6060") then errs[#errs + 1] = s end end
print_real("Debug errors printed: " .. #errs)
for _, e in ipairs(errs) do print_real("  " .. e) end
os.exit((failed == 0 and #errs == 0) and 0 or 1)

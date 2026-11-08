-- FlexTip anchor: the draggable box that tooltips are pinned to.
local _, FT = ...

local WIDTH, HEIGHT = 220, 92
local GRAB_TEXTURE = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-"

-- The scale grip sits in the corner opposite the pinned corner, so dragging
-- it "away" from where the tooltip is pinned makes the tooltip bigger.
local GRIP_CORNER = {
    TOPLEFT = "BOTTOMRIGHT", TOP = "BOTTOMRIGHT", TOPRIGHT = "BOTTOMLEFT",
    LEFT = "BOTTOMRIGHT", CENTER = "BOTTOMRIGHT", RIGHT = "BOTTOMLEFT",
    BOTTOMLEFT = "TOPRIGHT", BOTTOM = "TOPRIGHT", BOTTOMRIGHT = "TOPLEFT",
}

-- Where a point sits inside a frame, as fractions from the bottom left.
local function PointFraction(point)
    local fx = point:find("LEFT") and 0 or point:find("RIGHT") and 1 or 0.5
    local fy = point:find("BOTTOM") and 0 or point:find("TOP") and 1 or 0.5
    return fx, fy
end

local function PointText(point)
    for _, choice in ipairs(FT.POINTS) do
        if choice.value == point then return choice.text end
    end
    return point
end

local function Round1(value)
    return math.floor(value * 10 + 0.5) / 10
end

---------------------------------------------------------------------------
-- Scale grip
---------------------------------------------------------------------------
local function GripOnUpdate(self)
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    local dx, dy = (x - self.startX) / scale, (y - self.startY) / scale
    local delta = dx * self.dirX + dy * self.dirY
    FT:SetScale(self.startScale + delta / 150)
end

local function GripStop(self)
    self:SetScript("OnUpdate", nil)
end

local function CreateGrip(mover)
    local grip = CreateFrame("Button", nil, mover)
    grip:SetSize(16, 16)
    grip:SetNormalTexture(GRAB_TEXTURE .. "Up")
    grip:SetPushedTexture(GRAB_TEXTURE .. "Down")
    grip:SetHighlightTexture(GRAB_TEXTURE .. "Highlight")
    grip:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        self.startX, self.startY = GetCursorPosition()
        self.startScale = FT.db.scale
        self:SetScript("OnUpdate", GripOnUpdate)
    end)
    grip:SetScript("OnMouseUp", GripStop)
    grip:SetScript("OnHide", GripStop)
    return grip
end

local function PlaceGrip(grip, mover, pinned)
    local corner = GRIP_CORNER[pinned] or "BOTTOMRIGHT"
    local fx, fy = PointFraction(corner)
    grip:ClearAllPoints()
    grip:SetPoint(corner, mover, corner, fx == 0 and 2 or -2, fy == 0 and 2 or -2)
    grip.dirX, grip.dirY = fx * 2 - 1, fy * 2 - 1
    -- The art points to the bottom right; mirror it for the other corners.
    local flipX, flipY = fx == 0, fy == 1
    local l, r = flipX and 1 or 0, flipX and 0 or 1
    local t, b = flipY and 1 or 0, flipY and 0 or 1
    for _, tex in ipairs({ grip:GetNormalTexture(), grip:GetPushedTexture(), grip:GetHighlightTexture() }) do
        tex:SetTexCoord(l, r, t, b)
    end
end

---------------------------------------------------------------------------
-- Mover frame
---------------------------------------------------------------------------
function FT:CreateMover()
    if self.mover then return end

    local m = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    m:SetSize(WIDTH, HEIGHT)
    m:SetFrameStrata("DIALOG")
    m:SetClampedToScreen(true)
    m:SetMovable(true)
    m:EnableMouse(true)
    m:EnableMouseWheel(true)
    m:RegisterForDrag("LeftButton")
    m:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    m:SetBackdropColor(0.05, 0.3, 0.55, 0.6)
    m:SetBackdropBorderColor(0.4, 0.8, 1, 1)
    m:Hide()

    local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("CENTER", 0, 28)
    title:SetText("FlexTip anchor")

    local hint = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("CENTER", 0, 0)
    hint:SetWidth(WIDTH - 50)
    hint:SetText("Drag to move, click to preview\nWheel or corner grip to scale\nRight-click to lock")

    m.info = m:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    m.info:SetPoint("CENTER", 0, -30)

    -- Shows which corner of the tooltip is pinned here.
    m.marker = m:CreateTexture(nil, "OVERLAY")
    m.marker:SetSize(10, 10)
    m.marker:SetColorTexture(1, 0.82, 0, 1)

    m.grip = CreateGrip(m)

    m:SetScript("OnMouseDown", function(self)
        self.dragged = false
    end)
    m:SetScript("OnDragStart", function(self)
        self.dragged = true
        self:StartMoving()
    end)
    m:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        FT:SaveMoverPosition()
        FT:ApplyMoverPosition()
    end)
    m:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            FT:SetLocked(true)
        elseif button == "LeftButton" and not self.dragged then
            FT:ShowPreview()
        end
    end)
    m:SetScript("OnMouseWheel", function(_, delta)
        FT:SetScale(FT.db.scale + delta * 0.05)
    end)
    m:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(1, 1, 1, 1)
    end)
    m:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.4, 0.8, 1, 1)
    end)

    self.mover = m
end

function FT:ApplyMoverPosition()
    local m = self.mover
    if not m then return end
    local pos = self.db.moverPos
    m:ClearAllPoints()
    m:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
end

-- Store the anchor's position measured from the screen corner that matches
-- the pinned tooltip corner, so it stays put if the screen size changes.
function FT:SaveMoverPosition()
    local m = self.mover
    if not m then return end
    local left, bottom = m:GetLeft(), m:GetBottom()
    local width, height = m:GetWidth(), m:GetHeight()
    local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
    if not (left and bottom and screenW and screenH) then return end
    -- The mover is a child of UIParent at scale 1, so they share coordinates.
    local point = self.db.anchorPoint
    local fx, fy = PointFraction(point)
    self.db.moverPos = {
        point = point,
        relPoint = point,
        x = Round1(left + width * fx - screenW * fx),
        y = Round1(bottom + height * fy - screenH * fy),
    }
end

function FT:UpdateMover()
    local m = self.mover
    if not m then return end
    self:ApplyMoverPosition()

    local point = self.db.anchorPoint
    m.marker:ClearAllPoints()
    m.marker:SetPoint("CENTER", m, point, 0, 0)
    PlaceGrip(m.grip, m, point)
    m.info:SetText(string.format("Scale %.2f, pinned at %s", self.db.scale, PointText(point):lower()))

    if self.db.locked then
        if m:IsShown() then
            self:HidePreview()
            m:Hide()
        end
    else
        m:Show()
    end
end

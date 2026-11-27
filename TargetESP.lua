--[[
    TargetESP  -  "ghosts" effect for CelestialLib (pure Luau, client-side only)

    When the cursor is over another player's character, 3-4 glowing translucent orbs fly around it.
    Every orb drags a tapering trail behind it. Orbs move on 3D paths (spiral / sine wave / tilted rings)
    at different heights and angles. When the cursor leaves the player, the orbs shrink and fade out.

    Two styles:
        "Ghosts"  glowing orbs with trails fly around the target (trajectory: Spiral / Sine / Orbit / Scanner).
        "Circle"  a thin horizontal ring around the target slides from the feet to the top of the head and back
                  (sine easing: it slows down at both ends). A skirt of light trails behind the ring: it is
                  opaque near the ring and fades to transparent away from it; while the ring goes up the skirt
                  hangs below it, while it goes down the skirt stays above it.

    The effect is only a marker: it works from a raycast under the cursor, so it is shown only when the
    player's character is really under the cursor (it does not show anything through walls).

    ---------------------------------------------------------------------------------------------
    1) Ready-made function for the GUI (adds a card + all settings to a section):

        local TargetESP = require(script.Parent.TargetESP)
        local feature, fx = TargetESP.Attach(Visual, {          -- Visual = Window:AddSection(...)
            Keybind = Enum.KeyCode.J,                           -- optional
            Names   = { Title = "Target ESP" },                 -- optional (texts of the GUI)
            Config  = { Count = 4 },                            -- optional (see DEFAULTS below)
        })

    2) Standalone, without the GUI:

        local fx = TargetESP.new({ Mode = "Sine", Count = 3 })
        fx:Start()
        fx:Set("Speed", 2.5)        -- options can be changed live
        fx:Stop()
        fx:Destroy()

    In the GUI, settings of the style that is not selected are hidden (Ghosts: trajectory, count, size, scanner
    tilt only for the Scanner trajectory; Circle: ring offset). Attach(section, { HideUnused = false }) keeps all.

    Methods: :Start() :Stop() :IsRunning() :Set(key, value) :Get(key) :GetTarget() :Destroy()
    Options (Config):
        Style        "Ghosts" | "Circle"   (default "Ghosts")
        CircleOffset studs      Circle: distance of the ring from the model (default 0.6)
        RingThickness studs     Circle: thickness of the ring (default 0.1)
        Count        1..12      Ghosts: number of orbs (default 4)
        Size         studs      Ghosts: orb diameter (default 0.45)
        Speed        number     rotation / sweep speed, both styles (default 1.6)
        TrailLength  seconds    trail lifetime = length of the Circle skirt, both styles (default 0.55)
        Mode         Ghosts trajectory: "Spiral" | "Sine" | "Orbit" | "Scanner"
                     Scanner: all orbs fly around on ONE height (an even ring) and the whole ring slides
                     up and down along the body; the orbs lean 2-3 degrees in the direction of the
                     vertical movement (looking up while going up, down while going down).
        ScannerTilt  degrees    lean of the orbs in Scanner mode (default 2.5)
        ColorMode    "Gradient" | "Rainbow" | "White"
        Colors       { Color3, Color3 }   gradient from the first orb to the last
        Glow         boolean    halo around the orb + a small light (default true)
        TeamCheck    boolean    do not show on teammates (default false)
        MaxDistance  studs      max distance of the cursor ray (default 500)
        Linger       seconds    how long the effect stays after the cursor leaves the target, then it
                                fades out smoothly (default 1, 0 = start fading immediately)
        Filter       function(player) -> boolean, optional extra filter
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local TargetESP = {}
TargetESP.__index = TargetESP
TargetESP.Version = "1.0.0"

local DEFAULTS = {
    Style = "Ghosts",
    CircleOffset = 0.6,
    RingThickness = 0.1,
    Count = 4,
    Size = 0.45,
    Speed = 1.6,
    TrailLength = 0.55,
    Mode = "Spiral",
    ScannerTilt = 2.5,
    ColorMode = "Gradient",
    Colors = { Color3.fromRGB(128, 66, 196), Color3.fromRGB(228, 76, 132) },
    Glow = true,
    TeamCheck = false,
    MaxDistance = 500,
    Linger = 1,
    Filter = nil,
}

local SCAN_W = 0.9    -- vertical speed of the "Scanner" ring (radians per unit of time)
local SCAN_BAND = 2.2 -- height of the Scanner trail band relative to the orb size
local CIRCLE_W = 0.75 -- vertical speed of the "Circle" ring (radians per unit of time)
-- transparency of the Circle skirt along its length (time, transparency): head -> tail
local TRAIL_ALPHA = { { 0, 0.15 }, { 0.3, 0.6 }, { 1, 1 } }
local FADE_IN = 3.3  -- 1 / fade-in seconds
local FADE_OUT = 4.2 -- 1 / fade-out seconds

local function merge(base, extra)
    local out = {}
    for k, v in pairs(base) do
        out[k] = v
    end
    if extra then
        for k, v in pairs(extra) do
            out[k] = v
        end
    end
    return out
end

local function newPart(parent, name, size, transparency)
    local p = Instance.new("Part")
    p.Name = name
    p.Shape = Enum.PartType.Ball
    p.Material = Enum.Material.Neon
    p.Anchored = true
    p.CanCollide = false
    p.CanTouch = false
    p.CanQuery = false
    p.CastShadow = false
    p.Massless = true
    p.Size = Vector3.new(size, size, size)
    p.Transparency = transparency
    p.Parent = parent
    return p
end

local function newBlock(parent, name, size, transparency)
    local p = Instance.new("Part")
    p.Name = name
    p.Material = Enum.Material.Neon
    p.Anchored = true
    p.CanCollide = false
    p.CanTouch = false
    p.CanQuery = false
    p.CastShadow = false
    p.Massless = true
    p.Size = size
    p.Transparency = transparency
    p.Parent = parent
    return p
end

-- NumberSequence from { {time, transparency}, ... } faded by k (0 = invisible, 1 = as designed)
local function fadeSequence(points, k)
    local keypoints = {}
    for i, point in ipairs(points) do
        keypoints[i] = NumberSequenceKeypoint.new(point[1], 1 - (1 - point[2]) * k)
    end
    return NumberSequence.new(keypoints)
end

-- ============================================================================
-- Construction / lifecycle
-- ============================================================================

function TargetESP.new(config)
    local self = setmetatable({}, TargetESP)
    self.Config = merge(DEFAULTS, config)
    self._time = 0
    self._lastSeen = 0
    self._active = nil
    self._dying = {}
    self._conn = nil
    self._rayParams = RaycastParams.new()
    self._rayParams.FilterType = Enum.RaycastFilterType.Exclude
    return self
end

function TargetESP:IsRunning()
    return self._conn ~= nil
end

function TargetESP:Start()
    if self._conn then
        return
    end
    self._conn = RunService.RenderStepped:Connect(function(dt)
        self:_step(dt)
    end)
end

function TargetESP:Stop()
    if self._conn then
        self._conn:Disconnect()
        self._conn = nil
    end
    self:_clear()
end

function TargetESP:Destroy()
    self:Stop()
    if self._folder then
        self._folder:Destroy()
        self._folder = nil
    end
end

function TargetESP:GetTarget()
    return self._active and self._active.Player or nil
end

function TargetESP:Get(key)
    return self.Config[key]
end

function TargetESP:Set(key, value)
    local cfg = self.Config
    if cfg[key] == value then
        return
    end
    cfg[key] = value

    -- does the number / kind of parts change? then the current group is rebuilt in place
    local g = self._active
    local rebuild = false
    if g then
        if key == "Style" or key == "Glow" then
            rebuild = true
        elseif key == "Count" then
            rebuild = g.Style == "Ghosts"
        elseif key == "CircleOffset" or key == "RingThickness" then
            rebuild = g.Style == "Circle"
        end
    end

    if rebuild then
        self:_destroyGroup(g)
        self._active = self:_spawn({
            Player = g.Player, Character = g.Character, Root = g.Root, Humanoid = g.Humanoid,
        }, 1)
        self:_updateGroup(self._active, 0) -- position the new parts right away
    elseif key == "Mode" then
        -- Scanner trails are real 3D bands (they follow the orb tilt), the others always face the camera
        self:_eachGroup(function(group)
            if group.Style == "Ghosts" then
                for _, orb in ipairs(group.Orbs) do
                    orb.Trail.FaceCamera = value ~= "Scanner"
                end
            end
        end)
    elseif key == "TrailLength" then
        self:_eachGroup(function(group)
            for _, orb in ipairs(group.Orbs) do
                orb.Trail.Lifetime = value
            end
        end)
    elseif key == "ColorMode" or key == "Colors" then
        self:_eachGroup(function(group)
            for i, orb in ipairs(group.Orbs) do
                self:_applyColor(orb, self:_groupColor(group, i))
            end
            if group.Light then
                group.Light.Color = self:_groupColor(group, 1)
            end
        end)
    end
end

function TargetESP:_eachGroup(fn)
    if self._active then
        fn(self._active)
    end
    for _, g in ipairs(self._dying) do
        fn(g)
    end
end

function TargetESP:_clear()
    if self._active then
        self:_destroyGroup(self._active)
        self._active = nil
    end
    for _, g in ipairs(self._dying) do
        self:_destroyGroup(g)
    end
    self._dying = {}
end

function TargetESP:_destroyGroup(g)
    if g.Folder then
        g.Folder:Destroy()
        g.Folder = nil
    end
end

function TargetESP:_getFolder()
    local cam = Workspace.CurrentCamera
    if not self._folder then
        self._folder = Instance.new("Folder")
        self._folder.Name = "TargetESP"
    end
    if cam and self._folder.Parent ~= cam then
        self._folder.Parent = cam -- parts under the camera exist only on this client
    end
    return self._folder
end

-- ============================================================================
-- Target detection (raycast under the cursor)
-- ============================================================================

function TargetESP:_findTarget()
    local cam = Workspace.CurrentCamera
    if not cam then
        return nil
    end
    local cfg = self.Config
    local lp = Players.LocalPlayer
    local loc = UserInputService:GetMouseLocation()
    local ray = cam:ViewportPointToRay(loc.X, loc.Y)

    local ignore = {}
    if lp.Character then
        ignore[1] = lp.Character
    end
    self._rayParams.FilterDescendantsInstances = ignore

    local result = Workspace:Raycast(ray.Origin, ray.Direction * cfg.MaxDistance, self._rayParams)
    if not result then
        return nil
    end

    local inst = result.Instance
    while inst and inst ~= Workspace do
        if inst:IsA("Model") then
            local player = Players:GetPlayerFromCharacter(inst)
            if player then
                if player == lp then
                    return nil
                end
                local hum = inst:FindFirstChildOfClass("Humanoid")
                local root = inst:FindFirstChild("HumanoidRootPart") or inst.PrimaryPart
                if not hum or not root or hum.Health <= 0 then
                    return nil
                end
                if cfg.TeamCheck and player.Team ~= nil and player.Team == lp.Team then
                    return nil
                end
                if cfg.Filter and not cfg.Filter(player) then
                    return nil
                end
                return { Player = player, Character = inst, Root = root, Humanoid = hum }
            end
        end
        inst = inst.Parent
    end
    return nil
end

-- ============================================================================
-- Orbs
-- ============================================================================

function TargetESP:_orbColor(index, count)
    local cfg = self.Config
    if cfg.ColorMode == "Rainbow" then
        return Color3.fromHSV((self._time * 0.15 + (index - 1) / count) % 1, 0.75, 1)
    elseif cfg.ColorMode == "White" then
        return Color3.new(1, 1, 1)
    end
    local colors = cfg.Colors
    local f = count <= 1 and 0 or (index - 1) / (count - 1)
    return colors[1]:Lerp(colors[2], f)
end

-- color of the i-th element of a group (orb of "Ghosts" / bead of the "Circle" ring)
function TargetESP:_groupColor(g, index)
    if g.Style ~= "Circle" then
        return self:_orbColor(index, #g.Orbs)
    end
    local mode = self.Config.ColorMode
    local bead = g.Orbs[index]
    if mode == "Rainbow" then
        return Color3.fromHSV((self._time * 0.15 + bead.Angle / (math.pi * 2)) % 1, 0.75, 1)
    elseif mode == "White" then
        return Color3.new(1, 1, 1)
    end
    -- seamless two-color gradient around the ring
    local colors = self.Config.Colors
    return colors[1]:Lerp(colors[2], 0.5 + 0.5 * math.cos(bead.Angle))
end

function TargetESP:_applyColor(orb, color)
    orb.Core.Color = color
    if orb.Halo then
        orb.Halo.Color = color
    end
    if orb.Light then
        orb.Light.Color = color
    end
    orb.Trail.Color = ColorSequence.new(color)
end

function TargetESP:_spawn(target, alpha)
    local cfg = self.Config
    local extents = target.Character:GetExtentsSize()
    -- feet and top of the head, relative to the root part
    local bbCFrame, bbSize = target.Character:GetBoundingBox()
    local rootY = target.Root.Position.Y
    local bottom = bbCFrame.Position.Y - bbSize.Y * 0.5 - rootY
    local top = bbCFrame.Position.Y + bbSize.Y * 0.5 - rootY

    local folder = Instance.new("Folder")
    folder.Name = target.Player.Name
    folder.Parent = self:_getFolder()

    local group = {
        Style = cfg.Style == "Circle" and "Circle" or "Ghosts",
        Player = target.Player,
        Character = target.Character,
        Root = target.Root,
        Humanoid = target.Humanoid,
        R = math.clamp(math.max(extents.X, extents.Z) * 0.5 + 0.6, 2, 6),
        H = math.clamp(extents.Y, 2, 12),
        YMid = (top + bottom) * 0.5,
        YAmp = math.max(0.5, (top - bottom) * 0.5),
        Center = target.Root.Position,
        Target = target.Root.Position,
        Alpha = alpha or 0,
        Dying = false,
        Orbs = {},
        Folder = folder,
    }

    if group.Style == "Circle" then
        self:_buildCircle(group, extents)
    else
        self:_buildGhosts(group)
    end
    return group
end

-- "Circle": a ring made of thin neon blocks (a regular polygon with many sides). Every block carries a
-- vertical Trail whose width is exactly the side of the polygon, so the trails join into one cylindrical
-- skirt that stays behind the moving ring and fades out along its length.
function TargetESP:_buildCircle(group, extents)
    local cfg = self.Config
    local folder = group.Folder
    local R = math.clamp(math.max(extents.X, extents.Z) * 0.5 + cfg.CircleOffset, 1.2, 8)
    local n = math.clamp(math.floor(R * 12 + 0.5), 24, 48)
    local chord = 2 * R * math.sin(math.pi / n)
    local thick = cfg.RingThickness
    group.RingR = R
    group.Apothem = R * math.cos(math.pi / n) -- distance from the center to the middle of a side

    for i = 1, n do
        local angle = (i - 0.5) / n * math.pi * 2
        local radial = Vector3.new(math.cos(angle), 0, math.sin(angle))
        local bead = {
            Angle = angle,
            Radial = radial,
            -- local X of the block = tangent of the ring, so the block (and its trail width) lies along the side
            Rot = CFrame.lookAt(Vector3.new(0, 0, 0), radial),
            TrailOn = false,
        }
        bead.Core = newBlock(folder, "Ring", Vector3.new(chord * 1.04, thick, thick * 1.5), 0.05)
        if cfg.Glow then
            bead.Halo = newBlock(folder, "Glow", Vector3.new(chord * 1.04, thick * 3.5, thick * 5), 0.82)
        end

        bead.A0 = Instance.new("Attachment")
        bead.A0.Position = Vector3.new(chord * 0.5, 0, 0)
        bead.A0.Parent = bead.Core
        bead.A1 = Instance.new("Attachment")
        bead.A1.Position = Vector3.new(-chord * 0.5, 0, 0)
        bead.A1.Parent = bead.Core

        local trail = Instance.new("Trail")
        trail.Attachment0 = bead.A0
        trail.Attachment1 = bead.A1
        trail.Lifetime = cfg.TrailLength
        trail.MinLength = 0.02
        trail.FaceCamera = false -- a real vertical strip, not a camera-facing ribbon
        trail.LightEmission = 1
        trail.LightInfluence = 0
        trail.Transparency = fadeSequence(TRAIL_ALPHA, 0) -- opaque near the ring -> transparent at the tail
        trail.Enabled = false -- enabled after the first positioning (no streak from the origin)
        trail.Parent = bead.Core
        bead.Trail = trail

        group.Orbs[i] = bead
        self:_applyColor(bead, self:_groupColor(group, i))
    end

    if cfg.Glow then
        group.LightPart = newBlock(folder, "Light", Vector3.new(0.2, 0.2, 0.2), 1)
        group.Light = Instance.new("PointLight")
        group.Light.Range = 10
        group.Light.Brightness = 1.2
        group.Light.Shadows = false
        group.Light.Color = self:_groupColor(group, 1)
        group.Light.Parent = group.LightPart
    end
end

function TargetESP:_buildGhosts(group)
    local cfg = self.Config
    local folder = group.Folder
    local count = math.clamp(math.floor(cfg.Count + 0.5), 1, 12)
    for i = 1, count do
        local phase = (i - 1) / count * math.pi * 2
        local size = cfg.Size

        local orb = {
            Phase = phase,
            Dir = (i % 2 == 0) and -1 or 1, -- neighbours fly in opposite directions
            TrailOn = false,
        }

        -- tilted ring for the "Orbit" mode: every orb gets its own plane
        local tilt = math.rad(25 + 55 * (i - 1) / math.max(1, count - 1))
        local normal = Vector3.new(math.sin(tilt) * math.cos(phase), math.cos(tilt), math.sin(tilt) * math.sin(phase))
        local u = normal:Cross(Vector3.new(0, 1, 0))
        if u.Magnitude < 1e-3 then
            u = Vector3.new(1, 0, 0)
        end
        orb.U = u.Unit
        orb.V = normal:Cross(orb.U).Unit

        orb.Core = newPart(folder, "Core", size, 0.1)
        if cfg.Glow then
            orb.Halo = newPart(folder, "Halo", size * 2.6, 0.82)
            orb.Light = Instance.new("PointLight")
            orb.Light.Range = 6
            orb.Light.Brightness = 1.5
            orb.Light.Shadows = false
            orb.Light.Parent = orb.Core
        end

        orb.A0 = Instance.new("Attachment")
        orb.A0.Position = Vector3.new(0, size * 0.5, 0)
        orb.A0.Parent = orb.Core
        orb.A1 = Instance.new("Attachment")
        orb.A1.Position = Vector3.new(0, -size * 0.5, 0)
        orb.A1.Parent = orb.Core

        local trail = Instance.new("Trail")
        trail.Attachment0 = orb.A0
        trail.Attachment1 = orb.A1
        trail.Lifetime = cfg.TrailLength
        trail.MinLength = 0.02
        trail.FaceCamera = cfg.Mode ~= "Scanner"
        trail.LightEmission = 1
        trail.LightInfluence = 0
        trail.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.25),
            NumberSequenceKeypoint.new(1, 1),
        })
        trail.WidthScale = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(1, 0),
        })
        trail.Enabled = false -- enabled after the first positioning (no streak from the origin)
        trail.Parent = orb.Core
        orb.Trail = trail

        self:_applyColor(orb, self:_orbColor(i, count))
        group.Orbs[i] = orb
    end
end

-- offset of an orb from the center of the target (in studs)
function TargetESP:_offset(group, orb, t)
    local mode = self.Config.Mode
    local R, H = group.R, group.H
    local theta = t * orb.Dir + orb.Phase

    if mode == "Scanner" then
        -- one common height for every orb, the ring sweeps up and down along the body
        local a = t + orb.Phase -- all orbs rotate in the same direction, evenly spaced
        return Vector3.new(R * math.cos(a), H * 0.46 * math.sin(t * SCAN_W), R * math.sin(a))
    elseif mode == "Sine" then
        -- a wave winding around the body: height follows sin of the angle
        local y = H * 0.32 * math.sin(theta * 3 + orb.Phase)
        return Vector3.new(R * math.cos(theta), y, R * math.sin(theta))
    elseif mode == "Orbit" then
        -- tilted rings, every orb in its own plane
        local a = t * orb.Dir * 1.15 + orb.Phase
        local ring = (orb.U * math.cos(a) + orb.V * math.sin(a)) * R
        return ring + Vector3.new(0, H * 0.08 * math.sin(t * 0.7 + orb.Phase), 0)
    end
    -- "Spiral": breathing radius + slow rise and fall along the whole body
    local r = R * (0.92 + 0.14 * math.sin(t * 1.7 + orb.Phase * 2))
    local y = H * 0.45 * math.sin(t * 0.85 + orb.Phase * 1.3)
    return Vector3.new(r * math.cos(theta), y, r * math.sin(theta))
end

function TargetESP:_updateGroup(g, dt)
    local cfg = self.Config
    if g.Dying then
        g.Alpha = math.max(0, g.Alpha - dt * FADE_OUT)
    else
        g.Alpha = math.min(1, g.Alpha + dt * FADE_IN)
    end
    local eased = g.Alpha * g.Alpha * (3 - 2 * g.Alpha)

    if g.Root and g.Root.Parent then
        g.Target = g.Root.Position
    end
    g.Center = g.Center:Lerp(g.Target, 1 - math.exp(-14 * dt))

    local t = self._time * cfg.Speed
    if g.Style == "Circle" then
        self:_updateCircle(g, eased, t)
    else
        self:_updateGhosts(g, eased, t)
    end
end

function TargetESP:_updateCircle(g, eased, t)
    local cfg = self.Config
    -- sine easing: the ring slows down at the feet and at the top of the head
    local ringY = g.YMid + g.YAmp * math.sin(t * CIRCLE_W)
    local center = Vector3.new(g.Center.X, g.Center.Y + ringY, g.Center.Z)
    local rainbow = cfg.ColorMode == "Rainbow"

    for i, bead in ipairs(g.Orbs) do
        local cf = CFrame.new(center + bead.Radial * g.Apothem) * bead.Rot
        bead.Core.CFrame = cf
        if bead.Halo then
            bead.Halo.CFrame = cf
        end
        if rainbow then
            self:_applyColor(bead, self:_groupColor(g, i))
        end
        if not bead.TrailOn then
            bead.TrailOn = true
            bead.Trail.Enabled = true
        end
    end

    if g.LightPart then
        g.LightPart.CFrame = CFrame.new(center)
        g.Light.Brightness = 1.2 * eased
        if rainbow then
            g.Light.Color = self:_groupColor(g, 1)
        end
    end

    -- fade in / out of the ring, the glow and the skirt (only while the fade is running)
    if g.FadeApplied ~= eased then
        g.FadeApplied = eased
        for _, bead in ipairs(g.Orbs) do
            bead.Core.Transparency = 1 - 0.95 * eased
            if bead.Halo then
                bead.Halo.Transparency = 1 - 0.18 * eased
            end
            bead.Trail.Transparency = fadeSequence(TRAIL_ALPHA, eased)
        end
    end
end

function TargetESP:_updateGhosts(g, eased, t)
    local cfg = self.Config
    local count = #g.Orbs
    local scanner = cfg.Mode == "Scanner"
    local band = scanner and SCAN_BAND or 1
    for i, orb in ipairs(g.Orbs) do
        local pos = g.Center + self:_offset(g, orb, t)
        local cf
        if scanner then
            -- face the way the orb flies (along the ring), leaned a few degrees up / down
            -- following the vertical movement of the ring (+ while rising, - while sinking)
            local a = t + orb.Phase
            local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
            local pitch = math.rad(cfg.ScannerTilt) * math.cos(t * SCAN_W)
            cf = CFrame.lookAt(pos, pos + tangent) * CFrame.Angles(pitch, 0, 0)
        else
            cf = CFrame.new(pos)
        end

        local pulse = 1 + 0.12 * math.sin(self._time * 4 + orb.Phase)
        local s = math.max(0.05, cfg.Size * eased * pulse)
        orb.Core.Size = Vector3.new(s, s, s)
        orb.Core.CFrame = cf
        orb.A0.Position = Vector3.new(0, s * 0.5 * band, 0)
        orb.A1.Position = Vector3.new(0, -s * 0.5 * band, 0)
        if orb.Halo then
            local hs = s * 2.6
            orb.Halo.Size = Vector3.new(hs, hs, hs)
            orb.Halo.CFrame = cf
        end
        if orb.Light then
            orb.Light.Brightness = 1.5 * eased
        end
        if cfg.ColorMode == "Rainbow" then
            self:_applyColor(orb, self:_orbColor(i, count))
        end
        if not orb.TrailOn then
            orb.TrailOn = true
            orb.Trail.Enabled = true
        end
    end
end

function TargetESP:_retire(g)
    g.Dying = true
    table.insert(self._dying, g)
end

function TargetESP:_step(dt)
    self._time = self._time + dt
    local cfg = self.Config

    local target = self:_findTarget()
    local active = self._active

    -- the current target died or left the game
    if active and (not active.Root.Parent or active.Humanoid.Health <= 0) then
        self:_retire(active)
        self._active = nil
        active = nil
    end

    if target then
        self._lastSeen = self._time
        if not active or active.Character ~= target.Character then
            if active then
                self:_retire(active)
            end
            active = self:_spawn(target, 0)
            self._active = active
        end
    elseif active and self._time - self._lastSeen > cfg.Linger then
        self:_retire(active)
        self._active = nil
        active = nil
    end

    if active then
        self:_updateGroup(active, dt)
    end
    for i = #self._dying, 1, -1 do
        local g = self._dying[i]
        self:_updateGroup(g, dt)
        if g.Alpha <= 0 then
            self:_destroyGroup(g)
            table.remove(self._dying, i)
        end
    end
end

-- ============================================================================
-- GUI integration (CelestialLib)
-- ============================================================================

local DEFAULT_NAMES = {
    Title = "Target ESP",
    Description = "Призраки вокруг игрока под курсором",
    Count = "Количество призраков",
    Size = "Размер призраков",
    Speed = "Скорость",
    Trail = "Длина шлейфа",
    TrailSuffix = " с",
    Linger = "Задержка исчезновения",
    Path = "Траектория призраков",
    Spiral = "Спираль",
    Sine = "Синусоида",
    Orbit = "Орбиты",
    Scanner = "Сканер",
    Style = "Режим",
    Ghosts = "Призраки",
    Circle = "Круг",
    Offset = "Отступ кольца",
    Tilt = "Наклон сканера",
    TiltSuffix = "°",
    Color = "Цвет",
    Gradient = "Градиент",
    Rainbow = "Радуга",
    White = "Белый",
    Glow = "Свечение",
    TeamCheck = "Не показывать на союзниках",
}

-- Adds the "Target ESP" function with all settings to a CelestialLib section.
-- Returns the feature and the effect object.
function TargetESP.Attach(section, opts)
    opts = opts or {}
    local names = merge(DEFAULT_NAMES, opts.Names)
    local config = merge({}, opts.Config)
    if not config.Colors then
        local theme = section.Window.Theme
        config.Colors = { theme.Accent, theme.Accent2 }
    end
    local fx = TargetESP.new(config)
    local cfg = fx.Config

    local feature = section:AddFunction({
        Name = names.Title,
        Description = names.Description,
        Default = opts.Default,
        Keybind = opts.Keybind,
        Callback = function(state)
            if state then
                fx:Start()
            else
                fx:Stop()
            end
        end,
    })

    -- settings that belong to one style only are hidden while the other style is selected
    -- (Show property of CelestialLib settings). Pass HideUnused = false to keep everything visible.
    local pathDD, countSl, sizeSl, offsetSl, tiltSl
    local function refresh()
        if opts.HideUnused == false then
            return
        end
        local circle = cfg.Style == "Circle"
        pathDD.Show = not circle
        countSl.Show = not circle
        sizeSl.Show = not circle
        tiltSl.Show = not circle and cfg.Mode == "Scanner"
        offsetSl.Show = circle
    end

    feature:AddDropdown({
        Name = names.Style,
        Options = { names.Ghosts, names.Circle },
        Default = ({ Ghosts = names.Ghosts, Circle = names.Circle })[cfg.Style],
        Callback = function(value)
            fx:Set("Style", value == names.Circle and "Circle" or "Ghosts")
            refresh()
        end,
    })
    pathDD = feature:AddDropdown({
        Name = names.Path,
        Options = { names.Spiral, names.Sine, names.Orbit, names.Scanner },
        Default = ({
            Spiral = names.Spiral, Sine = names.Sine, Orbit = names.Orbit, Scanner = names.Scanner,
        })[cfg.Mode],
        Callback = function(value)
            local map = {
                [names.Spiral] = "Spiral", [names.Sine] = "Sine",
                [names.Orbit] = "Orbit", [names.Scanner] = "Scanner",
            }
            fx:Set("Mode", map[value] or "Spiral")
            refresh()
        end,
    })
    feature:AddDropdown({
        Name = names.Color,
        Options = { names.Gradient, names.Rainbow, names.White },
        Default = ({ Gradient = names.Gradient, Rainbow = names.Rainbow, White = names.White })[cfg.ColorMode],
        Callback = function(value)
            local map = { [names.Gradient] = "Gradient", [names.Rainbow] = "Rainbow", [names.White] = "White" }
            fx:Set("ColorMode", map[value] or "Gradient")
        end,
    })
    countSl = feature:AddSlider({
        Name = names.Count, Min = 1, Max = 8, Default = cfg.Count, Increment = 1,
        Callback = function(v) fx:Set("Count", v) end,
    })
    sizeSl = feature:AddSlider({
        Name = names.Size, Min = 0.2, Max = 1.2, Default = cfg.Size, Increment = 0.05,
        Callback = function(v) fx:Set("Size", v) end,
    })
    feature:AddSlider({
        Name = names.Speed, Min = 0.5, Max = 5, Default = cfg.Speed, Increment = 0.1,
        Callback = function(v) fx:Set("Speed", v) end,
    })
    feature:AddSlider({
        Name = names.Trail, Min = 0.1, Max = 1.5, Default = cfg.TrailLength, Increment = 0.05,
        Suffix = names.TrailSuffix,
        Callback = function(v) fx:Set("TrailLength", v) end,
    })
    offsetSl = feature:AddSlider({
        Name = names.Offset, Min = 0, Max = 3, Default = cfg.CircleOffset, Increment = 0.1,
        Callback = function(v) fx:Set("CircleOffset", v) end,
    })
    tiltSl = feature:AddSlider({
        Name = names.Tilt, Min = 0, Max = 15, Default = cfg.ScannerTilt, Increment = 0.5,
        Suffix = names.TiltSuffix,
        Callback = function(v) fx:Set("ScannerTilt", v) end,
    })
    feature:AddSlider({
        Name = names.Linger, Min = 0, Max = 3, Default = cfg.Linger, Increment = 0.1,
        Suffix = names.TrailSuffix,
        Callback = function(v) fx:Set("Linger", v) end,
    })
    feature:AddToggle({
        Name = names.Glow, Default = cfg.Glow,
        Callback = function(v) fx:Set("Glow", v) end,
    })
    feature:AddToggle({
        Name = names.TeamCheck, Default = cfg.TeamCheck,
        Callback = function(v) fx:Set("TeamCheck", v) end,
    })

    refresh()
    return feature, fx
end

return TargetESP

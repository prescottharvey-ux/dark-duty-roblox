--!strict
-- MovementFX.client.lua (post-camera head-bob + FOV; bob only on sprint)

local Players = game:GetService 'Players'
local RunService = game:GetService 'RunService'

local LP = Players.LocalPlayer
local CAM = workspace.CurrentCamera

-- ====== Tunables ======
local BASE_FOV = 70
local SPRINT_FOV = 78
local SNEAK_FOV = 64
local FOV_LERP = 0.12 -- gentle easing

-- Bob amplitudes (studs) / roll (radians)
local AMP_SPRINT_Y = 0.12
local AMP_SPRINT_R = 0.02

local FREQ_BASE = 6.0 -- slower/steadier
local LERP_BOB = 0.18 -- smoother bob
local ROLL_SCALE = 0.33 -- roll runs slower than vertical

-- ====== State ======
local HUM: Humanoid? = nil
local bobT = 0
local targetFov = BASE_FOV
local targetAmpY = 0.0
local targetAmpR = 0.0
local curOffY = 0.0
local curRoll = 0.0

local BIND_KEY = 'MovementFX:HeadBob'

local function getB(attr: string): boolean
  local v = LP:GetAttribute(attr)
  return typeof(v) == 'boolean' and v or false
end

local function bind()
  if not LP.Character then
    return
  end
  HUM = LP.Character:FindFirstChildOfClass 'Humanoid'
  if not (HUM and CAM) then
    return
  end

  -- reset
  CAM.FieldOfView = BASE_FOV
  HUM.CameraOffset = Vector3.zero

  pcall(function()
    RunService:UnbindFromRenderStep(BIND_KEY)
  end)

  RunService:BindToRenderStep(BIND_KEY, Enum.RenderPriority.Camera.Value + 1, function(dt)
    if not (HUM and CAM) then
      return
    end

    local sprint = getB 'IsSprinting'
    local sneak = getB 'IsSneaking'
    local moving = HUM.MoveDirection.Magnitude > 0.02
    local grounded = HUM.FloorMaterial ~= Enum.Material.Air

    -- FOV target (keep sneak/sprint FOV, even if bob is off)
    if sprint then
      targetFov = SPRINT_FOV
    elseif sneak then
      targetFov = SNEAK_FOV
    else
      targetFov = BASE_FOV
    end
    CAM.FieldOfView = CAM.FieldOfView + (targetFov - CAM.FieldOfView) * FOV_LERP

    -- ====== Bob ONLY while sprinting ======
    if sprint and moving and grounded then
      targetAmpY, targetAmpR = AMP_SPRINT_Y, AMP_SPRINT_R
    else
      targetAmpY, targetAmpR = 0, 0
      bobT = 0 -- reset phase so it restarts cleanly next sprint
    end

    -- Advance phase; mild speed scaling
    local speed = HUM.WalkSpeed > 0 and (HUM.MoveDirection.Magnitude * HUM.WalkSpeed) or 0
    local freq = FREQ_BASE * (0.6 + 0.4 * math.clamp(speed / 16, 0, 1))
    bobT += dt * freq * math.pi * 2

    -- Smooth towards target offsets
    local goalY = math.sin(bobT) * targetAmpY
    local goalRol = math.sin(bobT * ROLL_SCALE) * targetAmpR
    curOffY = curOffY + (goalY - curOffY) * LERP_BOB
    curRoll = curRoll + (goalRol - curRoll) * LERP_BOB

    -- Apply AFTER default camera
    local cf = CAM.CFrame
    cf = cf * CFrame.new(0, curOffY, 0) * CFrame.fromAxisAngle(cf.LookVector, curRoll)
    CAM.CFrame = cf
  end)
end

Players.LocalPlayer.CharacterAdded:Connect(function()
  task.defer(bind)
end)

if LP.Character then
  bind()
end

--!strict
-- Simple camera FOV FX: widen on sprint, tighten on sneak.

local Players = game:GetService 'Players'
local RunService = game:GetService 'RunService'
local player = Players.LocalPlayer

local BASE_FOV = 70 -- your normal FOV
local SPRINT_FOV = 80 -- widen for speed feel
local SNEAK_FOV = 62 -- tighter "zoom" when sneaking
local LERP_SPEED = 10 -- higher = snappier

-- If you already set a different FOV elsewhere, you can read it once:
local cam = workspace.CurrentCamera
if cam then
  BASE_FOV = cam.FieldOfView
end

local function targetFov(): number
  local sprint = player:GetAttribute 'IsSprinting' == true
  local sneak = player:GetAttribute 'IsSneaking' == true
  if sprint then
    return SPRINT_FOV
  end
  if sneak then
    return SNEAK_FOV
  end
  return BASE_FOV
end

RunService.RenderStepped:Connect(function(dt)
  local cam = workspace.CurrentCamera
  if not cam then
    return
  end
  local t = targetFov()
  -- simple exponential lerp
  local alpha = math.clamp(dt * LERP_SPEED, 0, 1)
  cam.FieldOfView = cam.FieldOfView + (t - cam.FieldOfView) * alpha
end)

-- keep in sync when attrs flip
local function onAttrChanged()
  -- force a tiny tug so the next frame lerps toward new target
end
player:GetAttributeChangedSignal('IsSprinting'):Connect(onAttrChanged)
player:GetAttributeChangedSignal('IsSneaking'):Connect(onAttrChanged)

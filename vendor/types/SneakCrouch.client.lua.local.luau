--!strict
-- Makes the player visually “crouch” when IsSneaking=true:
-- - Lowers camera smoothly
-- - Plays crouch idle/walk if animations exist
-- - (Optional) tweens HipHeight a tad (off by default; see APPLY_HIPHEIGHT)

local Players = game:GetService 'Players'
local RunService = game:GetService 'RunService'
local TweenService = game:GetService 'TweenService'
local RS = game:GetService 'ReplicatedStorage'

local plr = Players.LocalPlayer

-- Tunables
local CAM_DROP = 1.0 -- how much to lower the camera (studs)
local CAM_TWEEN_IN = 0.18
local CAM_TWEEN_OUT = 0.15
local APPLY_HIPHEIGHT = false -- set true if you want to physically lower; can cause foot clipping on some rigs
local HIPHEIGHT_SCALE = 0.92
local HIP_TWEEN = 0.18

-- Animation names looked up (optional)
local ANIM_NAMES_IDLE = { 'CrouchIdle', 'SneakIdle', 'Crouch_Idle' }
local ANIM_NAMES_WALK = { 'CrouchWalk', 'SneakWalk', 'Crouch_Move' }

-- State
local char: Model? = nil
local hum: Humanoid? = nil
local animator: Animator? = nil
local baseCameraOffset: Vector3 = Vector3.new()
local baseHip: number = 0
local crouchIdle: AnimationTrack? = nil
local crouchWalk: AnimationTrack? = nil
local camTween: Tween? = nil
local hipTween: Tween? = nil
local moveConn: RBXScriptConnection? = nil

-- ===== helpers =====
local function getAnimator(): Animator?
  if not hum then
    return nil
  end
  local a = hum:FindFirstChildOfClass 'Animator' :: Animator?
  if not a then
    a = Instance.new 'Animator'
    a.Parent = hum
  end
  return a
end

local function findAnimByNames(nameList: { string }): Animation?
  -- Prefer RS/Animations/Crouch/*
  local anims = RS:FindFirstChild 'Animations'
  if anims then
    local crouchFolder = anims:FindFirstChild 'Crouch'
    if crouchFolder then
      for _, n in ipairs(nameList) do
        local a = crouchFolder:FindFirstChild(n)
        if a and a:IsA 'Animation' and a.AnimationId ~= '' then
          return a
        end
      end
    end
    -- Fallback RS/Animations/*
    for _, n in ipairs(nameList) do
      local a = anims:FindFirstChild(n)
      if a and a:IsA 'Animation' and a.AnimationId ~= '' then
        return a
      end
    end
  end
  return nil
end

local function stopTrack(t: AnimationTrack?)
  if not t then
    return
  end
  pcall(function()
    t:Stop(0.12)
  end)
  pcall(function()
    t:Destroy()
  end)
end

local function stopAllTracks()
  stopTrack(crouchIdle)
  crouchIdle = nil
  stopTrack(crouchWalk)
  crouchWalk = nil
end

local function ensureTracks()
  if not animator then
    return
  end
  if not crouchIdle then
    local a = findAnimByNames(ANIM_NAMES_IDLE)
    if a then
      crouchIdle = animator:LoadAnimation(a)
      crouchIdle.Priority = Enum.AnimationPriority.Idle
      crouchIdle.Looped = true
    end
  end
  if not crouchWalk then
    local a = findAnimByNames(ANIM_NAMES_WALK)
    if a then
      crouchWalk = animator:LoadAnimation(a)
      crouchWalk.Priority = Enum.AnimationPriority.Movement
      crouchWalk.Looped = true
    end
  end
end

local function tweenCameraOffset(to: Vector3, dur: number)
  if not hum then
    return
  end
  if camTween then
    camTween:Cancel()
  end
  local proxy = Instance.new 'Vector3Value'
  proxy.Value = hum.CameraOffset
  proxy:GetPropertyChangedSignal('Value'):Connect(function()
    if hum then
      hum.CameraOffset = proxy.Value
    end
  end)
  camTween = TweenService:Create(
    proxy,
    TweenInfo.new(dur, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
    { Value = to }
  )
  camTween:Play()
end

local function tweenHipHeight(to: number, dur: number)
  if not hum or not APPLY_HIPHEIGHT then
    return
  end
  if hipTween then
    hipTween:Cancel()
  end
  local v = Instance.new 'NumberValue'
  v.Value = hum.HipHeight
  v:GetPropertyChangedSignal('Value'):Connect(function()
    if hum then
      hum.HipHeight = v.Value
    end
  end)
  hipTween = TweenService:Create(
    v,
    TweenInfo.new(dur, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
    { Value = to }
  )
  hipTween:Play()
end

local function isMoving(): boolean
  return hum ~= nil and hum.MoveDirection.Magnitude > 0.05
end

local function updateCrouchAnim()
  -- choose idle vs walk while sneaking
  if not (crouchIdle or crouchWalk) then
    return
  end
  local moving = isMoving()
  if moving and crouchWalk then
    if crouchIdle and crouchIdle.IsPlaying then
      crouchIdle:Stop(0.10)
    end
    if not crouchWalk.IsPlaying then
      crouchWalk:Play(0.12, 1.0, 1.0)
    end
  else
    if crouchWalk and crouchWalk.IsPlaying then
      crouchWalk:Stop(0.10)
    end
    if crouchIdle and not crouchIdle.IsPlaying then
      crouchIdle:Play(0.12, 1.0, 1.0)
    end
  end
end

local function setCrouch(on: boolean)
  if not hum then
    return
  end

  -- camera
  if on then
    tweenCameraOffset(Vector3.new(0, -CAM_DROP, 0), CAM_TWEEN_IN)
  else
    tweenCameraOffset(baseCameraOffset, CAM_TWEEN_OUT)
  end

  -- optional hipheight (OFF by default)
  if APPLY_HIPHEIGHT then
    local target = on and (baseHip * HIPHEIGHT_SCALE) or baseHip
    tweenHipHeight(target, HIP_TWEEN)
  end

  -- animations
  animator = getAnimator()
  if on then
    ensureTracks()
    updateCrouchAnim()
    if not moveConn then
      moveConn = RunService.Heartbeat:Connect(function()
        updateCrouchAnim()
      end)
    end
  else
    if moveConn then
      moveConn:Disconnect()
      moveConn = nil
    end
    stopAllTracks()
  end
end

local function hookAttrs(p: Players.Player)
  p:GetAttributeChangedSignal('IsSneaking'):Connect(function()
    local on = (p:GetAttribute 'IsSneaking' == true)
    setCrouch(on)
  end)
  -- apply current value on spawn
  local on = (p:GetAttribute 'IsSneaking' == true)
  setCrouch(on)
end

local function onCharacter(c: Model)
  char = c
  hum = c:WaitForChild 'Humanoid' :: Humanoid
  baseCameraOffset = hum.CameraOffset
  baseHip = hum.HipHeight
  stopAllTracks()
  if moveConn then
    moveConn:Disconnect()
    moveConn = nil
  end
  animator = getAnimator()
  -- reapply crouch if already sneaking
  local on = (plr:GetAttribute 'IsSneaking' == true)
  setCrouch(on)
end

-- boot
hookAttrs(plr)
plr.CharacterAdded:Connect(onCharacter)
if plr.Character then
  onCharacter(plr.Character)
end

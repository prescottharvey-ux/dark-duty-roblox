--!strict
-- FootstepSFX.client.lua
-- Lower volume/pitch while sneaking, louder while sprinting

local Players = game:GetService 'Players'
local RS = game:GetService 'ReplicatedStorage'
local RunService = game:GetService 'RunService'

local LP = Players.LocalPlayer
local CHARACTER: Model? = nil
local HUM: Humanoid? = nil
local HRP: BasePart? = nil
local runSound: Sound? = nil

-- Optional fallback asset (replace with your own)
local SOUND_ID = '' -- e.g. "rbxassetid://12345678"

local function ensureRunSound()
  if not HRP then
    return
  end
  -- Try to reuse existing
  for _, s in ipairs(HRP:GetChildren()) do
    if s:IsA 'Sound' and (s.Name == 'Running' or s.Name == 'Run' or s.Name == 'Footsteps') then
      runSound = s
      return
    end
  end
  -- Create minimal loop if none exists
  if SOUND_ID ~= '' then
    local s = Instance.new 'Sound'
    s.Name = 'Footsteps'
    s.Looped = true
    s.SoundId = SOUND_ID
    s.Volume = 0.4
    s.PlaybackSpeed = 1.0
    s.Parent = HRP
    runSound = s
    s:Play()
  end
end

local function applySfx()
  if not runSound then
    return
  end
  local sprint = LP:GetAttribute 'IsSprinting' == true
  local sneak = LP:GetAttribute 'IsSneaking' == true

  -- base values
  local vol, spd = 0.5, 1.0
  if sprint then
    vol, spd = 0.9, 1.12
  elseif sneak then
    vol, spd = 0.25, 0.92
  end

  -- also scale a bit with current speed
  if HUM then
    local v = HUM.MoveDirection.Magnitude * (HUM.WalkSpeed or 16)
    local t = math.clamp(v / 14, 0, 1)
    vol = vol * (0.6 + 0.4 * t)
    spd = spd * (0.96 + 0.08 * t)
  end

  runSound.Volume = vol
  runSound.PlaybackSpeed = spd

  -- play/pause based on moving + grounded
  local moving = HUM and HUM.MoveDirection.Magnitude > 0.02
  local onGround = HUM and HUM.FloorMaterial ~= Enum.Material.Air
  if moving and onGround then
    if runSound.IsPaused then
      runSound:Resume()
    end
    if not runSound.IsPlaying then
      runSound:Play()
    end
  else
    if runSound.IsPlaying then
      runSound:Pause()
    end
  end
end

local function bind()
  if not CHARACTER then
    return
  end
  HUM = CHARACTER:FindFirstChildOfClass 'Humanoid'
  HRP = CHARACTER:FindFirstChild 'HumanoidRootPart' :: BasePart
  if not (HUM and HRP) then
    return
  end
  ensureRunSound()
  -- react quickly
  for _, attr in ipairs { 'IsSprinting', 'IsSneaking' } do
    Players.LocalPlayer:GetAttributeChangedSignal(attr):Connect(applySfx)
  end
  RunService.RenderStepped:Connect(applySfx)
end

LP.CharacterAdded:Connect(function(c)
  CHARACTER = c
  task.wait()
  bind()
end)
if LP.Character then
  CHARACTER = LP.Character
  bind()
end

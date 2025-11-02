--!strict
local Players = game:GetService 'Players'
local ContextActionService = game:GetService 'ContextActionService'
local RS = game:GetService 'ReplicatedStorage'

local player = Players.LocalPlayer
local AnimIds = require(RS:WaitForChild('Modules'):WaitForChild('Combat'):WaitForChild 'AnimIds')

local Remotes = RS:WaitForChild 'Remotes'
local REFolder = Remotes:WaitForChild 'RemoteEvent'
local RFCombat = REFolder:WaitForChild 'Combat'

local RE_StartBlock = RFCombat:WaitForChild 'StartBlock' :: RemoteEvent
local RE_StopBlock = RFCombat:WaitForChild 'StopBlock' :: RemoteEvent
local RE_DaggerAttack = RFCombat:WaitForChild 'DaggerAttack' :: RemoteEvent
local RE_ForceBlockOff = RFCombat:WaitForChild 'ForceBlockOff' :: RemoteEvent
local RE_ReplicateDagger = RFCombat:WaitForChild 'ReplicateDaggerSwing' :: RemoteEvent

-- Local animation convenience
local function loadAndPlayLocal(animId: number, looped: boolean?, weight: number?): AnimationTrack?
  local char = player.Character or player.CharacterAdded:Wait()
  local hum = char:FindFirstChildOfClass 'Humanoid'
  if not hum then
    return nil
  end
  local animator = hum:FindFirstChildOfClass 'Animator' or Instance.new('Animator', hum)
  local anim = Instance.new 'Animation'
  anim.AnimationId = ('rbxassetid://%d'):format(animId)
  local track = animator:LoadAnimation(anim)
  track.Looped = looped == true
  track.Priority = Enum.AnimationPriority.Action
  track:Play(0.03, 1, weight or 1.0)
  return track
end

local shieldLoopTrack: AnimationTrack? = nil

-- Input bindings (PC: LMB stab, RMB hold block; Gamepad: R2 stab, L2 block; Touch: tap stab, hold block)
local ACTION_STAB = 'Combat_DaggerStab'
local ACTION_BLOCK = 'Combat_ShieldBlock'

local function onStabAction(_, inputState: Enum.UserInputState)
  if inputState == Enum.UserInputState.Begin then
    RE_DaggerAttack:FireServer()
    local id = AnimIds.Dagger.Stab
    if id then
      loadAndPlayLocal(id, false, 1.0)
    end
  end
  return Enum.ContextActionResult.Sink
end

local function onBlockAction(_, inputState: Enum.UserInputState)
  if inputState == Enum.UserInputState.Begin then
    RE_StartBlock:FireServer()
    local id = AnimIds.Shield.BlockLoop
    if id then
      shieldLoopTrack = loadAndPlayLocal(id, true, 1.0)
    end
  elseif inputState == Enum.UserInputState.End then
    RE_StopBlock:FireServer()
    if shieldLoopTrack then
      pcall(function()
        shieldLoopTrack:Stop(0.05)
      end)
      shieldLoopTrack = nil
    end
  end
  return Enum.ContextActionResult.Sink
end

-- Bind: Mouse & Touch & Gamepad friendly
ContextActionService:BindAction(
  ACTION_STAB,
  onStabAction,
  true,
  Enum.UserInputType.MouseButton1,
  Enum.KeyCode.ButtonR2,
  Enum.KeyCode.ButtonR1,
  Enum.KeyCode.X
)

ContextActionService:BindAction(
  ACTION_BLOCK,
  onBlockAction,
  true,
  Enum.UserInputType.MouseButton2,
  Enum.KeyCode.ButtonL2,
  Enum.KeyCode.ButtonL1,
  Enum.KeyCode.F
)

-- Server may force block off (e.g., out of stamina)
RE_ForceBlockOff.OnClientEvent:Connect(function()
  if shieldLoopTrack then
    pcall(function()
      shieldLoopTrack:Stop(0.05)
    end)
    shieldLoopTrack = nil
  end
end)

-- (Optional) play a tiny FPV flourish when others swing (you can add SFX or trails here)
RE_ReplicateDagger.OnClientEvent:Connect(function(attacker: Player)
  if attacker == player then
    return
  end
  -- You can add camera shake, whoosh, or crosshair tick here if desired.
end)

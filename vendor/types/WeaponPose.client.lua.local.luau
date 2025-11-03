--!strict
-- StarterPlayerScripts/WeaponPose.client.lua
-- Plays a "weapon idle" pose whenever a hand item is equipped, stops when empty.

local Players = game:GetService 'Players'
local RS = game:GetService 'ReplicatedStorage'

local me = Players.LocalPlayer

-- Remotes
local Remotes = RS:WaitForChild 'Remotes'
local REF = Remotes:WaitForChild 'RemoteEvent'
local RFF = Remotes:WaitForChild 'RemoteFunction'
local EquipChanged: RemoteEvent = REF:WaitForChild 'EquipChanged' :: RemoteEvent
local EquipmentQuery: RemoteFunction = RFF:WaitForChild 'EquipmentQuery' :: RemoteFunction

-- TODO: put your real animation id here (must be R15 and owned by the game owner/group)
local ARMED_IDLE_ANIM_ID: string = '97887003578329' -- e.g. "rbxassetid://18478530957" or just "18478530957"

-- --- internals ---
type Snapshot = { equipment: { handL: string?, handR: string? } }

local animator: Animator? = nil
local track: AnimationTrack? = nil
local currentAnimId: string? = nil
local warnedInvalid = false

local function getAnimator(): Animator?
  local char = me.Character
  if not char then
    return nil
  end
  local hum = char:FindFirstChildOfClass 'Humanoid'
  if not hum then
    return nil
  end
  local a = hum:FindFirstChildOfClass 'Animator'
  if not a then
    a = Instance.new 'Animator'
    a.Parent = hum
  end
  return a
end

local function normalizeAnimId(raw: string?): string?
  if not raw or raw == '' then
    return nil
  end
  -- accept "12345" or "rbxassetid://12345"
  local num = string.match(raw, '(%d+)')
  if not num or tonumber(num) == nil or tonumber(num) == 0 then
    return nil
  end
  return 'rbxassetid://' .. num
end

local function playPose(animId: string?)
  local norm = normalizeAnimId(animId)
  if not norm then
    if not warnedInvalid then
      warn '[WeaponPose] No valid ARMED_IDLE_ANIM_ID set; pose disabled until you add one.'
      warnedInvalid = true
    end
    return
  end

  animator = animator or getAnimator()
  if not animator then
    return
  end

  if currentAnimId == norm and track and track.IsPlaying then
    return -- already playing this pose
  end

  -- stop old
  if track then
    pcall(function()
      track:Stop(0.15)
    end)
  end

  -- load new
  local anim = Instance.new 'Animation'
  anim.AnimationId = norm
  local ok, newTrack = pcall(function()
    return animator:LoadAnimation(anim)
  end)
  if not ok or not newTrack then
    if not warnedInvalid then
      warn(
        '[WeaponPose] Failed to load animation id:',
        norm,
        'Is it owned by this game/group and R15?'
      )
      warnedInvalid = true
    end
    return
  end

  newTrack.Priority = Enum.AnimationPriority.Action
  newTrack.Looped = true
  pcall(function()
    newTrack:Play(0.15)
  end)

  track = newTrack
  currentAnimId = norm
end

local function stopPose()
  currentAnimId = nil
  if track then
    pcall(function()
      track:Stop(0.15)
    end)
  end
  track = nil
end

local function armed(s: Snapshot?): boolean
  if not s or not s.equipment then
    return false
  end
  return (s.equipment.handL ~= nil) or (s.equipment.handR ~= nil)
end

local function refreshFromSnapshot(s: any)
  local snap = s :: Snapshot
  if armed(snap) then
    playPose(ARMED_IDLE_ANIM_ID)
  else
    stopPose()
  end
end

local function fetchOnce()
  local ok, s = pcall(function()
    return EquipmentQuery:InvokeServer()
  end)
  if ok and typeof(s) == 'table' then
    refreshFromSnapshot(s)
  end
end

-- React to equipment changes
EquipChanged.OnClientEvent:Connect(function(s: any)
  if typeof(s) == 'table' then
    refreshFromSnapshot(s)
  end
end)

-- Re-hook after respawn
me.CharacterAdded:Connect(function()
  animator = nil
  stopPose()
  task.defer(fetchOnce)
end)

-- initial
task.defer(fetchOnce)

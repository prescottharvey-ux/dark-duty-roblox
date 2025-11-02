--!strict
local Players = game:GetService 'Players'
local RunService = game:GetService 'RunService'
local RS = game:GetService 'ReplicatedStorage'
local PPS = game:GetService 'ProximityPromptService'

-- === Remotes ===
local REFolder = RS:FindFirstChild 'Remotes' or Instance.new 'Folder'
REFolder.Name = 'Remotes'
REFolder.Parent = RS

local REEvents = REFolder:FindFirstChild 'RemoteEvent' or Instance.new 'Folder'
REEvents.Name = 'RemoteEvent'
REEvents.Parent = REFolder

local DownedNoticeRE = REEvents:FindFirstChild 'DownedNotice' or Instance.new 'RemoteEvent'
DownedNoticeRE.Name = 'DownedNotice'
DownedNoticeRE.Parent = REEvents

-- === Tunables ===
local BLEEDOUT_SECONDS = 15.0
local REVIVE_HOLD = 2.5
local REVIVE_HEALTH_FRAC = 0.35
local IFRAME_AFTER_REV = 1.25

-- === State ===
type DownedState = {
  uid: number,
  char: Model,
  hum: Humanoid,
  endTime: number,
  paused: boolean,
  revivers: { [number]: true },
  prompt: ProximityPrompt?,
  connDied: RBXScriptConnection?,
  updateLoop: RBXScriptConnection?,
  restore: { WalkSpeed: number, JumpPower: number, AutoRotate: boolean },
}

local downedById: { [number]: DownedState } = {}

local function sendAll(tag: string, payload: any)
  DownedNoticeRE:FireAllClients(tag, payload)
end

local function cleanState(state: DownedState, finalTag: 'revived' | 'dead')
  local plr = Players:GetPlayerByUserId(state.uid)

  if state.updateLoop then
    state.updateLoop:Disconnect()
  end
  if state.connDied then
    state.connDied:Disconnect()
  end
  if state.prompt and state.prompt.Parent then
    state.prompt:Destroy()
  end

  if state.hum and state.hum.Parent then
    state.hum.WalkSpeed = state.restore.WalkSpeed
    state.hum.JumpPower = state.restore.JumpPower
    state.hum.AutoRotate = state.restore.AutoRotate
    state.hum.PlatformStand = false
    -- allow regen again, if property exists
    pcall(function()
      (state.hum :: any).HealthRegenerationRate = 1
    end)
  end

  if plr and plr.Character then
    plr.Character:SetAttribute('Downed', false)
  end

  downedById[state.uid] = nil
  sendAll('end', { userId = state.uid, result = finalTag })
end

local function forceDeath(state: DownedState)
  if state.hum and state.hum.Parent then
    state.hum.Health = 0
  end
  cleanState(state, 'dead')
end

local function revive(state: DownedState)
  if not state.hum or not state.hum.Parent then
    cleanState(state, 'dead')
    return
  end
  local max = math.max(1, state.hum.MaxHealth)
  state.hum.Health = math.max(1, math.floor(max * REVIVE_HEALTH_FRAC + 0.5))
  state.hum:SetAttribute('IFrameUntil', os.clock() + IFRAME_AFTER_REV)
  cleanState(state, 'revived')
end

local function startCountdown(state: DownedState)
  state.updateLoop = RunService.Heartbeat:Connect(function(dt)
    if not state.hum or not state.hum.Parent then
      forceDeath(state)
      return
    end

    -- freeze countdown while paused
    if state.paused then
      state.endTime += dt
    end

    -- clamp HP to 1 while downed (prevents regen)
    if state.hum.Health > 1 then
      state.hum.Health = 1
    end

    local remaining = math.max(0, state.endTime - os.clock())
    sendAll('tick', { userId = state.uid, seconds = remaining, paused = state.paused })
    if remaining <= 0 then
      forceDeath(state)
    end
  end)
end

local function makeRevivePrompt(target: Player, state: DownedState)
  local char = state.char
  local hrp = char:FindFirstChild 'HumanoidRootPart' :: BasePart
  if not hrp then
    return
  end

  local prompt = Instance.new 'ProximityPrompt'
  prompt.Name = 'RevivePrompt'
  prompt.ActionText = 'Revive'
  prompt.ObjectText = target.DisplayName
  prompt.RequiresLineOfSight = false
  prompt.HoldDuration = REVIVE_HOLD
  prompt.MaxActivationDistance = 9
  prompt.Enabled = true
  prompt.Parent = hrp
  state.prompt = prompt

  -- Global service signals; only affect this state if pr == prompt
  local beganConn = PPS.PromptButtonHoldBegan:Connect(function(pr, _input, holder)
    if pr ~= prompt then
      return
    end
    if holder and holder ~= target then
      state.revivers[holder.UserId] = true
      state.paused = true
      sendAll('paused', { userId = state.uid, paused = true })
    end
  end)

  local endedConn = PPS.PromptButtonHoldEnded:Connect(function(pr, holder)
    if pr ~= prompt then
      return
    end
    if holder then
      state.revivers[holder.UserId] = nil
      local any = next(state.revivers) ~= nil
      state.paused = any
      sendAll('paused', { userId = state.uid, paused = any })
    end
  end)

  -- Clean these two small connections when prompt is destroyed
  prompt.Destroying:Connect(function()
    if beganConn.Connected then
      beganConn:Disconnect()
    end
    if endedConn.Connected then
      endedConn:Disconnect()
    end
  end)

  -- Successful revive
  prompt.Triggered:Connect(function(holder: Player)
    if holder == target then
      return
    end -- no self-revive here
    if not downedById[target.UserId] then
      return
    end
    revive(state)
  end)
end

local function enterDowned(plr: Player)
  if downedById[plr.UserId] then
    return
  end
  if not plr.Character then
    return
  end
  local hum = plr.Character:FindFirstChildOfClass 'Humanoid'
  if not hum or hum.Health <= 0 and hum:GetState() == Enum.HumanoidStateType.Dead then
    return
  end

  -- snapshot movement
  local restore = {
    WalkSpeed = hum.WalkSpeed,
    JumpPower = hum.JumpPower,
    AutoRotate = hum.AutoRotate,
  }

  -- immobilize
  hum.PlatformStand = true
  hum.WalkSpeed = 0
  hum.JumpPower = 0
  hum.AutoRotate = false

  plr.Character:SetAttribute('Downed', true)

  -- keep "alive" at 1 HP and disable regen
  hum.Health = 1
  pcall(function()
    (hum :: any).HealthRegenerationRate = 0
  end)

  -- build state
  local state: DownedState = {
    uid = plr.UserId,
    char = plr.Character,
    hum = hum,
    endTime = os.clock() + BLEEDOUT_SECONDS,
    paused = false,
    revivers = {},
    prompt = nil,
    connDied = nil,
    updateLoop = nil,
    restore = restore,
  }
  downedById[plr.UserId] = state

  -- if a true death slips through, resolve as death
  state.connDied = hum.Died:Connect(function()
    if downedById[plr.UserId] then
      forceDeath(state)
    end
  end)

  -- show HUD
  sendAll('start', { userId = plr.UserId, name = plr.DisplayName, seconds = BLEEDOUT_SECONDS })

  makeRevivePrompt(plr, state)
  startCountdown(state)
end

-- Convert lethal damage into Downed state
local function watchCharacter(plr: Player, char: Model)
  local hum = char:WaitForChild 'Humanoid' :: Humanoid
  hum.HealthChanged:Connect(function(h)
    -- if would die and not already downed -> enter downed
    if h <= 0 and not (char:GetAttribute 'Downed' == true) then
      enterDowned(plr)
    end
  end)
end

Players.PlayerAdded:Connect(function(plr)
  plr.CharacterAdded:Connect(function(char)
    watchCharacter(plr, char)
  end)
  if plr.Character then
    watchCharacter(plr, plr.Character)
  end
end)

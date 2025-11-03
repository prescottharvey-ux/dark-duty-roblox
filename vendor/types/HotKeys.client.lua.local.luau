--!strict
-- StarterPlayerScripts/HotKeys.client.lua
-- Shift = Sprint (hold), Left Alt = Sneak (hold), RMB = Block (hold)
-- K = stash:toggle (via EventBus if present)

local Players = game:GetService 'Players'
local UIS = game:GetService 'UserInputService'
local RS = game:GetService 'ReplicatedStorage'

local player = Players.LocalPlayer or Players.PlayerAdded:Wait()

-- ---------- EventBus (normalize, define BEFORE use) ----------
local Bus
do
  local ok, mod = pcall(function()
    local Events = RS:FindFirstChild 'Events'
    local m = Events and Events:FindFirstChild 'EventBus'
    return m and require(m) or nil
  end)
  if ok and mod then
    local function resolveOn(a, b, c)
      if type(a) == 'string' then
        return a, b
      else
        return b, c
      end
    end
    local function resolveFire(a, b, c)
      if type(a) == 'string' then
        return a, b
      else
        return b, c
      end
    end

    local onImpl = mod.On or mod.on or mod.subscribe or mod.Subscribe or mod.Connect
    local fireImpl = mod.Fire or mod.fire or mod.publish or mod.Publish or mod.Emit

    local shim = {}
    function shim.On(a, b, c)
      local topic, fn = resolveOn(a, b, c)
      if onImpl then
        if mod.On then
          return mod:On(topic, fn)
        end
        if mod.on then
          return mod:on(topic, fn)
        end
        if mod.subscribe then
          return mod.subscribe(topic, fn)
        end
        if mod.Subscribe then
          return mod.Subscribe(topic, fn)
        end
        if mod.Connect then
          return mod.Connect(topic, fn)
        end
      end
      return { Disconnect = function() end }
    end
    function shim.Fire(a, b, c)
      local topic, payload = resolveFire(a, b, c)
      if fireImpl then
        if mod.Fire then
          mod:Fire(topic, payload)
          return
        end
        if mod.fire then
          mod:fire(topic, payload)
          return
        end
        if mod.publish then
          mod.publish(topic, payload)
          return
        end
        if mod.Publish then
          mod.Publish(topic, payload)
          return
        end
        if mod.Emit then
          mod.Emit(topic, payload)
          return
        end
      end
    end
    Bus = shim
  else
    Bus = {
      On = function(...)
        return { Disconnect = function() end }
      end,
      Fire = function(...) end,
    }
  end
end

-- Track UI modal so hotkeys don't interfere with open panels
local uiModal = false
Bus:On('ui:modal', function(on)
  uiModal = (on == true)
end)

-- ---------- Remotes (robust discovery) ----------
local function waitFor(parent: Instance, name: string, seconds: number): Instance?
  local t, inst = 0, parent:FindFirstChild(name)
  while not inst and t < seconds do
    task.wait(0.2)
    t += 0.2
    inst = parent:FindFirstChild(name)
  end
  return inst
end

local Remotes = waitFor(RS, 'Remotes', 5)
if not Remotes then
  warn '[HotKeys] ReplicatedStorage/Remotes not found; stamina intents disabled'
  return
end

local StamFolder = waitFor(Remotes, 'Stamina', 5)
if not StamFolder then
  warn '[HotKeys] Remotes/Stamina not found; is StaminaService running?'
  return
end

local IntentsRemoteInst = StamFolder:FindFirstChild 'Intents'
local NoticeRemoteInst = StamFolder:FindFirstChild 'Notice'
if not IntentsRemoteInst or not NoticeRemoteInst then
  warn '[HotKeys] Intents/Notice remotes missing'
  return
end

local IntentsRE: RemoteEvent = IntentsRemoteInst :: RemoteEvent
local NoticeRE: RemoteEvent = NoticeRemoteInst :: RemoteEvent

-- ---------- Flags + helpers ----------
local flags = { Sprinting = false, Sneaking = false, Blocking = false }

local function send()
  IntentsRE:FireServer(flags)
end

-- Keys (hold-to-act)
local KEY_SPRINT = Enum.KeyCode.LeftShift
local KEY_SNEAK = Enum.KeyCode.LeftAlt
local KEY_BLOCK = Enum.UserInputType.MouseButton2

-- K => stash toggle via Bus
UIS.InputBegan:Connect(function(input, gpe)
  if gpe or uiModal or UIS:GetFocusedTextBox() then
    return
  end
  if input.KeyCode == Enum.KeyCode.K then
    Bus:Fire 'stash:toggle'
    return
  end

  if input.KeyCode == KEY_SPRINT then
    flags.Sprinting = true
    flags.Sneaking = false -- exclusive
    send()
  elseif input.KeyCode == KEY_SNEAK then
    flags.Sneaking = true
    flags.Sprinting = false -- exclusive
    send()
  elseif input.UserInputType == KEY_BLOCK then
    flags.Blocking = true
    send()
  end
end)

UIS.InputEnded:Connect(function(input, gpe)
  if gpe then
    return
  end
  if uiModal then
    return
  end
  if input.KeyCode == KEY_SPRINT then
    flags.Sprinting = false
    send()
  elseif input.KeyCode == KEY_SNEAK then
    flags.Sneaking = false
    send()
  elseif input.UserInputType == KEY_BLOCK then
    flags.Blocking = false
    send()
  end
end)

-- Server notices keep client flags in sync
NoticeRE.OnClientEvent:Connect(function(msg: string)
  if msg == 'ForceStopSprint' then
    if flags.Sprinting then
      flags.Sprinting = false
      send()
    end
  elseif msg == 'ForceStopBlock' then
    if flags.Blocking then
      flags.Blocking = false
      send()
    end
  end
end)

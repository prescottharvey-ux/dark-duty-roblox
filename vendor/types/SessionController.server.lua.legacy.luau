--!strict
local RS = game:GetService 'ReplicatedStorage'
local Players = game:GetService 'Players'
local RunService = game:GetService 'RunService'
local timeNow = time

-- === Remotes bucket ===
local R = RS:FindFirstChild 'Remotes' or Instance.new 'Folder'
R.Name = 'Remotes'
R.Parent = RS
local REv = R:FindFirstChild 'RemoteEvent' or Instance.new 'Folder'
REv.Name = 'RemoteEvent'
REv.Parent = R
local SessionRE = REv:FindFirstChild 'Session' :: RemoteEvent
if not SessionRE then
  SessionRE = Instance.new 'RemoteEvent'
  SessionRE.Name = 'Session'
  SessionRE.Parent = REv
end
-- tags:
--   SessionRE:FireAllClients("timer", secondsRemaining:number)
--   SessionRE:FireAllClients("exit_open", "Exit_1"|"Exit_2")
--   SessionRE:FireAllClients("ended", reason:string)

-- Optional EventBus early-end (egg extraction)
local okBus, Bus = pcall(function()
  return require(RS:WaitForChild('Events'):WaitForChild 'EventBus')
end)

-- === Config per GDD ===
local ROUND_SECONDS = 6 * 60 -- 6:00 total
local EXIT_A_AT = 2 * 60 -- 2:00 elapsed
local EXIT_B_AT = 4 * 60 -- 4:00 elapsed

-- === Exit helpers: expects workspace.Exits children named "Exit_1", "Exit_2"
local function getExit(name: string): Instance?
  local exits = workspace:FindFirstChild 'Exits'
  return exits and exits:FindFirstChild(name) or nil
end

local function setGateVisual(model: Instance, open: boolean)
  for _, p in ipairs(model:GetDescendants()) do
    if p:IsA 'BasePart' and p.Name == 'Gate' then
      p.CanCollide = not open
      p.Transparency = open and 1 or 0.3
    end
  end
end

local function setPromptEnabled(model: Instance, enabled: boolean)
  -- Prefer a prompt anywhere under the model; fall back to creating one on the first BasePart/HRP.
  local prompt: ProximityPrompt? = model:FindFirstChildWhichIsA('ProximityPrompt', true)
  if not prompt then
    local root: BasePart? = (model:FindFirstChild 'HumanoidRootPart' :: BasePart?)
      or model:FindFirstChildWhichIsA 'BasePart'
    if root then
      prompt = Instance.new 'ProximityPrompt'
      prompt.Name = 'ExtractPrompt'
      prompt.ActionText = 'Extract'
      prompt.ObjectText = model.Name
      prompt.KeyboardKeyCode = Enum.KeyCode.E
      prompt.HoldDuration = 0.75
      prompt.RequiresLineOfSight = false
      prompt.MaxActivationDistance = 10
      prompt.Parent = root
    end
  end
  if prompt then
    prompt.Enabled = enabled
  end
end

local function setExitOpen(exitName: string, open: boolean)
  local m = getExit(exitName)
  if not m then
    return
  end
  m:SetAttribute('Open', open) -- trusted flag ExtractionService listens to
  setGateVisual(m, open) -- optional visual/physical block
  setPromptEnabled(m, open) -- ensure UX matches immediately
  if open then
    print(('[Session] Opened %s'):format(exitName))
    SessionRE:FireAllClients('exit_open', exitName)
  end
end

-- === “All heroes down” detection (simple)
local function allHeroesDown(): boolean
  local players = Players:GetPlayers()
  if #players == 0 then
    return false
  end
  for _, plr in ipairs(players) do
    local ch = plr.Character
    if not ch then
      return false
    end
    -- DownedService should set Character attribute "Downed" to true while downed
    if ch:GetAttribute 'Downed' ~= true then
      return false
    end
  end
  return true
end

-- === Optional early end when the egg is extracted ===
if okBus and Bus and Bus.subscribe then
  Bus.subscribe('egg.extracted', function()
    SessionRE:FireAllClients('ended', 'egg_extracted')
    warn '[Session] Ending: egg_extracted'
    -- TODO: teleport to lobby or perform your handoff here
  end)
end

-- === Main round loop ===
local ticking = false
local function runRound()
  if ticking then
    return
  end
  ticking = true

  -- Close both exits at round start
  setExitOpen('Exit_1', false)
  setExitOpen('Exit_2', false)

  local t0 = timeNow()
  local sentSec = -1
  local openedA, openedB = false, false

  while true do
    local elapsed = timeNow() - t0
    -- Open exits on schedule (based on wall clock)
    if (not openedA) and elapsed >= EXIT_A_AT then
      openedA = true
      setExitOpen('Exit_1', true)
    end
    if (not openedB) and elapsed >= EXIT_B_AT then
      openedB = true
      setExitOpen('Exit_2', true)
    end

    -- Broadcast timer exactly 1 Hz to avoid jitter
    local remaining = math.max(0, ROUND_SECONDS - math.floor(elapsed + 0.5))
    if remaining ~= sentSec then
      sentSec = remaining
      SessionRE:FireAllClients('timer', remaining)
    end

    -- Early end
    if allHeroesDown() then
      SessionRE:FireAllClients('ended', 'all_down')
      warn '[Session] Ending: all heroes down'
      break
    end
    -- Natural end
    if remaining <= 0 then
      SessionRE:FireAllClients('ended', 'time_up')
      warn '[Session] Ending: time up'
      break
    end

    RunService.Heartbeat:Wait()
  end

  -- Lock exits after end
  setExitOpen('Exit_1', false)
  setExitOpen('Exit_2', false)

  -- TODO: server → lobby transition goes here
  ticking = false
end

-- Auto-start after first player joins (prototype flow)
Players.PlayerAdded:Connect(function()
  if not ticking then
    task.defer(runRound)
  end
end)

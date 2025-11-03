--!strict
local RS = game:GetService 'ReplicatedStorage'
local Bus = require(RS.Events.EventBus)
local Extraction = require(game.ServerScriptService.Extraction.Public).new()
local Egg = require(game.ServerScriptService.Egg.Public).new()

local EXITS = workspace:WaitForChild 'Exits' -- Models with ProximityPrompt

local function setExitEnabled(exitModel: Model, enabled: boolean)
  local p = exitModel:FindFirstChildOfClass 'ProximityPrompt'
  if p then
    p.Enabled = enabled
  end
end

-- Listen for exits opening from the Extraction timer
Bus.subscribe('extraction.exit.opened', function(e)
  -- Simple: enable all exits on event (or choose by name if you track which opens)
  for _, m in ipairs(EXITS:GetChildren()) do
    if m:IsA 'Model' then
      setExitEnabled(m, true)
    end
  end
end)

-- Extract when a player triggers a prompt
for _, m in ipairs(EXITS:GetChildren()) do
  local p = m:FindFirstChildOfClass 'ProximityPrompt'
  if p then
    p.Triggered:Connect(function(plr: Player)
      Bus.publish('player.extracted', { player = plr, exit = m.Name })
      if Egg.isCarried() and Egg.carrier() == plr then
        Bus.publish('egg.extracted', { player = plr })
      end
    end)
  end
end

-- Start round (you can call this from a lobby later)
Extraction.startRound()

--!strict
local Players = game:GetService 'Players'
local Bus = require(game.ReplicatedStorage.Events.EventBus)

local ENEMIES = workspace:FindFirstChild 'Enemies'

local function firstEnemyModel(): Model?
  if not ENEMIES then
    return nil
  end
  for _, inst in ipairs(ENEMIES:GetChildren()) do
    if inst:IsA 'Model' and inst:GetAttribute 'HP' ~= nil then
      return inst
    end
  end
  return nil
end

Players.PlayerAdded:Connect(function(plr)
  plr.Chatted:Connect(function(msg)
    if msg:lower() == '/hit' then
      local target = firstEnemyModel()
      if target then
        Bus.publish('combat.hit', { attacker = plr, target = target, damage = 20 })
        print('[Debug] Hit enemy:', target.Name)
      else
        warn '[Debug] No enemy with HP found under workspace.Enemies'
      end
    end
  end)
end)

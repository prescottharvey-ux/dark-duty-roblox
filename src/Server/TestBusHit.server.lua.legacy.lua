--!strict
local RS = game:GetService 'ReplicatedStorage'
local Players = game:GetService 'Players'
local Bus = require(RS.Events.EventBus)

local ENABLED = false
if not ENABLED then
  return
end

Players.PlayerAdded:Connect(function(p)
  task.delay(2, function()
    local char = p.Character or p.CharacterAdded:Wait()
    local hrp = char:WaitForChild 'HumanoidRootPart'
    -- send a synthetic hit near the player (NPCDamage will resolve nearest NPC)
    Bus:Fire('combat.hit', { attacker = p, target = hrp, damage = 25 })
    print('[TEST] Fired synthetic combat.hit for', p.Name)
  end)
end)

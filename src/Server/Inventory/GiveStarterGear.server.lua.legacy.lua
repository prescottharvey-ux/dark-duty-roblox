--!strict
local Players = game:GetService 'Players'
local Inventory = require(game.ServerScriptService:WaitForChild('Inventory'):WaitForChild 'Public')

Players.PlayerAdded:Connect(function(plr)
  task.wait(0.5) -- let other services boot
  if typeof(Inventory.addItem) == 'function' then
    Inventory.addItem(plr, 'dagger', 1)
  end
end)

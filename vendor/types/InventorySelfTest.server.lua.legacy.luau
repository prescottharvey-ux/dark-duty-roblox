--!strict
local Players = game:GetService 'Players'
local Inventory = require(game.ServerScriptService.Inventory.Public)

Players.PlayerAdded:Connect(function(p)
  task.delay(1, function()
    if Inventory and typeof(Inventory.addItem) == 'function' then
      Inventory.addItem(p, 'bandage', 2)
      print('[TEST] Gave bandage x2 to', p.Name)
    end
  end)
end)

local Players = game:GetService 'Players'
local SSS = game:GetService 'ServerScriptService'
local Http = game:GetService 'HttpService'
local Inventory = require(SSS.Inventory.Public)

local function dump(plr)
  local ok, list = pcall(Inventory.getCarriedList, plr)
  print('[InvProbe] carried for', plr.Name, ok and Http:JSONEncode(list) or 'ERR')
end

Players.PlayerAdded:Connect(function(p)
  task.defer(function()
    -- dump on join and after a bit (e.g., after you open a chest)
    dump(p)
    while p.Parent do
      task.wait(3)
      dump(p)
    end
  end)
end)

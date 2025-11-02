--!strict
local RS = game:GetService 'ReplicatedStorage'
local SSS = game:GetService 'ServerScriptService'
local Inventory = require(SSS.Inventory.Public)

local Remotes = RS:FindFirstChild 'Remotes'
local REF = Remotes and Remotes:FindFirstChild 'RemoteEvent'
local Notice = REF and REF:FindFirstChild 'InventoryNotice'
local Weight = REF and REF:FindFirstChild 'WeightUpdate'

local function push(plr: Player)
  if Notice and typeof(Inventory.getCarriedList) == 'function' then
    local ok, list = pcall(Inventory.getCarriedList, plr)
    if ok then
      Notice:FireClient(plr, 'carried_refresh', list)
    end
  end
  if Weight and typeof(Inventory.getWeight) == 'function' then
    local ok, w = pcall(Inventory.getWeight, plr)
    if ok then
      Weight:FireClient(plr, w)
    end
  end
end

return function(plr: Player, id: string, qty: number?, src: string?)
  qty = (type(qty) == 'number' and qty or 1)
  local ok = pcall(Inventory.addItem, plr, id, qty)
  if ok and Notice then
    Notice:FireClient(plr, 'notice', string.format('+%dx %s', qty, id))
  end
  push(plr)
  return ok
end

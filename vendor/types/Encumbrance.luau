--!strict
local RS = game:GetService 'ReplicatedStorage'
local Require = require(RS.Modules.Require)
local ItemDB = require(Require 'ItemDB')
local Enc = {}

function Enc.GetWeight(plr: Player): number
  local inv = _G.InventoryService
    and _G.InventoryService.getCarried
    and _G.InventoryService.getCarried(plr)
  local total = 0
  if inv then
    for id, qty in pairs(inv) do
      local def = ItemDB.GetItem and ItemDB.GetItem(id) or ItemDB[id]
      local w = (def and def.weight) or 0
      total += (w * (qty :: number))
    end
  end
  return total
end

function Enc.GetSpeedMult(plr: Player): number
  local C = RS.Config and require(RS.Config.StaminaConfig)
  local w = Enc.GetWeight(plr)
  local mult = 1.0 - (w * ((C and C.Stamina and C.Stamina.WeightToSpeedMult) or 0.01))
  return math.clamp(mult, 0.5, 1.0)
end

return Enc

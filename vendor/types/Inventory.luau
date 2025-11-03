--!strict
local SSS = game:GetService 'ServerScriptService'
local Public = require(SSS:WaitForChild('Inventory'):WaitForChild 'Public')
local M: any = {}

function M.GetCarried(plr: Player)
  if Public.getCarried then
    return Public.getCarried(plr)
  end
  if Public.getCarriedList then
    local map = {}
    for _, e in ipairs(Public.getCarriedList(plr)) do
      map[e.id] = (map[e.id] or 0) + (e.qty or 1)
    end
    return map
  end
  return {}
end

function M.Give(plr: Player, id: string, n: number?)
  n = n or 1
  if Public.addItem then
    return Public.addItem(plr, id, n)
  end
  if Public.addCarried then
    return Public.addCarried(plr, id, n)
  end
  return false
end

function M.MoveToStash(plr: Player, id: string, n: number?)
  n = n or 1
  if Public.removeCarried then
    Public.removeCarried(plr, id, n)
  end
  return true
end

for k, v in pairs(Public) do
  if M[k] == nil then
    M[k] = v
  end
end
return M

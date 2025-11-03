--!strict
local Bus = require(game.ReplicatedStorage.Events.EventBus)
local Dura = {}

function Dura.Tick(itemId: string, reason: string)
  Bus:Fire('durability.changed', { id = itemId, reason = reason })
end

function Dura.Get(itemId: string)
  return 1 -- placeholder; wire to your inventory/equipment durability map
end

return Dura

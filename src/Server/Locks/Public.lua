--!strict
local Types = require(game.ReplicatedStorage.Types)
local Bus = require(game.ReplicatedStorage.Events.EventBus)
local M = {}
function M.new(): Types.LocksApi
  local self = {} :: any
  function self.tryOpenChest(p: Player, chestId: string, hasPick: boolean)
    local t = 1.5 * (hasPick and 0.75 or 2.0)
    Bus.publish('lock.opened', { player = p, kind = 'chest', id = chestId, time = t })
    return true, t
  end
  function self.tryOpenDoor(p: Player, doorId: string, hasPick: boolean)
    local t = 2.5 * (hasPick and 0.5 or 2.0)
    Bus.publish('lock.opened', { player = p, kind = 'door', id = doorId, time = t })
    return true, t
  end
  return self
end
return M

--!strict
local Types = require(game.ReplicatedStorage.Types)
local Bus = require(game.ReplicatedStorage.Events.EventBus)
local M = {}
function M.new(): Types.EggApi
  local carrier: Player? = nil
  Bus.subscribe('egg.picked_up', function(e)
    carrier = e.player
    Bus.publish('egg.beacon.update', { player = carrier })
  end)
  Bus.subscribe('egg.dropped', function(e)
    carrier = nil
    Bus.publish('egg.beacon.update', { player = nil })
  end)
  Bus.subscribe('egg.extracted', function(e)
    carrier = nil
    Bus.publish('extraction.round.ended', { reason = 'egg' })
  end)
  local self = {} :: any
  function self.isCarried()
    return carrier ~= nil
  end
  function self.carrier()
    return carrier
  end
  return self
end
return M

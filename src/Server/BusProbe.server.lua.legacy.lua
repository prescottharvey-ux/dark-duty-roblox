--!strict
local Bus = require(game.ReplicatedStorage.Events.EventBus)
print('[BusProbe] EventBus =', tostring(Bus))
Bus.subscribe('combat.hit', function(e)
  print('[BusProbe] combat.hit', e and e.damage)
end)

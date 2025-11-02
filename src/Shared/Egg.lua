--!strict
local Bus = require(game.ReplicatedStorage.Events.EventBus)
local Egg = { state = { carriedBy = nil, pos = nil } }

function Egg.GetState()
  return Egg.state
end
function Egg.Pickup(plr: Player)
  Egg.state.carriedBy = plr
  Bus:Fire('egg.carried', plr)
end
function Egg.Drop(pos: Vector3)
  Egg.state.carriedBy = nil
  Egg.state.pos = pos
  Bus:Fire('egg.dropped', pos)
end

return Egg

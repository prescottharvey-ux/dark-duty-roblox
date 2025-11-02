--!strict
local Bus = require(game.ReplicatedStorage.Events.EventBus)
local Noise = {}

function Noise.Emit(pos: Vector3, tier: string)
  Bus:Fire('noise.emit', { pos = pos, tier = tier })
end

return Noise

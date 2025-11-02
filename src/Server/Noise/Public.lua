--!strict
local Types = require(game.ReplicatedStorage.Types)
local Bus = require(game.ReplicatedStorage.Events.EventBus)
local M = {}
function M.new(): Types.NoiseApi
  local self = {} :: any
  function self.emit(pos: Vector3, loudness: number, source: string)
    Bus.publish('noise.emitted', { pos = pos, loudness = loudness, source = source })
  end
  return self
end
return M

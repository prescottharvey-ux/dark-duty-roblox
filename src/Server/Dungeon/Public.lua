--!strict
local Types = require(game.ReplicatedStorage.Types)
local M = {}
function M.new(): Types.DungeonApi
  local self = {} :: any
  function self.currentZoneOf(pos: Vector3): number
    local r = pos.Magnitude
    if r < 100 then
      return 1
    elseif r < 200 then
      return 2
    elseif r < 300 then
      return 3
    else
      return 4
    end
  end
  return self
end
return M

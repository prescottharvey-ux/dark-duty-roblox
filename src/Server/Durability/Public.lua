--!strict
local Types = require(game.ReplicatedStorage.Types)
local Bus = require(game.ReplicatedStorage.Events.EventBus)
local M = {}
function M.new(): Types.CombatApi
  local self = {} :: any
  function self.applyMeleeHit(attacker: Player, target: Instance, damage: number)
    Bus.publish('combat.hit', { attacker = attacker, target = target, damage = damage })
  end
  return self
end
return M

--!strict
local Types = require(game:GetService('ReplicatedStorage'):WaitForChild 'Types')

local M = {}
function M.new(): Types.EconomyApi
  local balances: { [number]: number } = {}
  local Bus = require(game.ReplicatedStorage.Events.EventBus)
  local self = {} :: any
  function self.balance(p: Player)
    return balances[p.UserId] or 0
  end
  function self.grant(p: Player, amt: number, reason: string?)
    balances[p.UserId] = (self.balance(p) + amt)
    Bus.publish(
      'coin.collected',
      { player = p, amount = amt, source = reason or 'grant', ts = os.time() }
    )
  end
  function self.spend(p: Player, amt: number)
    local cur = self.balance(p)
    if cur < amt then
      return false
    end
    balances[p.UserId] = cur - amt
    return true
  end

  return self
end
return M

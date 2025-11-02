--!strict
local Bus = require(game.ReplicatedStorage.Events.EventBus)

local M = {}
function M.new()
  local RUN, E1, E2 = 6 * 60, 2 * 60, 4 * 60
  local elapsed = 0
  local exit1Opened, exit2Opened, ended = false, false, false

  game:GetService('RunService').Heartbeat:Connect(function(dt)
    elapsed += dt
    if (not exit1Opened) and elapsed >= E1 then
      exit1Opened = true
      Bus.publish('extraction.exit.opened', { at = E1 })
    end
    if (not exit2Opened) and elapsed >= E2 then
      exit2Opened = true
      Bus.publish('extraction.exit.opened', { at = E2 })
    end
    if (not ended) and elapsed >= RUN then
      ended = true
      Bus.publish('extraction.round.ended', { reason = 'time' })
    end
  end)

  local self = {} :: any
  function self.startRound()
    elapsed, exit1Opened, exit2Opened, ended = 0, false, false, false
    Bus.publish('extraction.round.started', {})
  end
  function self.getTimeRemaining(): number
    return math.max(0, RUN - elapsed)
  end
  return self
end
return M

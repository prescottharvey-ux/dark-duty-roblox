--!strict
local RS = game:GetService 'ReplicatedStorage'
local Bus = require(RS:WaitForChild('Events'):WaitForChild 'EventBus')

local Match = { _t0 = 0, _len = 360, _running = false }

function Match.Start(cfg: { RoundLength: number }?)
  Match._len = (cfg and cfg.RoundLength) or 360
  Match._t0, Match._running = os.clock(), true
  task.delay(120, function()
    if Match._running then
      Bus:Fire('extract.open', 1)
    end
  end)
  task.delay(240, function()
    if Match._running then
      Bus:Fire('extract.open', 2)
    end
  end)
end

function Match.GetTime(): number
  if not Match._running then
    return 0
  end
  return math.clamp(os.clock() - Match._t0, 0, Match._len)
end

return Match

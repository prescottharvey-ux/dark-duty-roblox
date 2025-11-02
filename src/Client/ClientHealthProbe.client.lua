-- Verifies the client can subscribe to EventBus & receive server pings
local RS = game:GetService 'ReplicatedStorage'
local container = RS:FindFirstChild 'Modules' or RS
local BusModule = container:FindFirstChild 'EventBus'
if not BusModule then
  warn '[ClientHealthProbe] EventBus not found (non-fatal)'
  return -- <<< stop here
end
local Bus = require(BusModule)
-- Bus.On(...) etc.

local received = false
local onFn = Bus.On or Bus.on
if type(onFn) == 'function' then
  onFn(Bus, 'healthcheck.client', function(payload)
    received = true
    print '[ClientProbe] EventBus OK (client received ping)'
  end)
else
  warn '[ClientProbe] Bus.On missing on client'
end

-- Let server-side Healthcheck fire: Bus.Fire("healthcheck.client", {...})
-- If you don't see the print after joining, your bus isn't client-wired.

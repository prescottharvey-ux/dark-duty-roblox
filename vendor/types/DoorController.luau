--!strict
local Bus = require(game.ReplicatedStorage.Events.EventBus)

local DoorController = {}

-- Example listener so Healthcheck sees the module; wire to your doors if needed.
Bus:On('extract.open', function(doorId: number)
  -- toggle prompts/doors for doorId here if you want
end)

return DoorController

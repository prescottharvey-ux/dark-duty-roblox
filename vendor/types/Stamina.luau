-- ReplicatedStorage/Modules/Stamina
-- Adapter: return the server StaminaService when it's ready
local tries = 0
repeat
  tries += 1
  if _G.StaminaService then
    return _G.StaminaService
  end
  task.wait(0.05)
until tries > 200
error 'StaminaService not ready'

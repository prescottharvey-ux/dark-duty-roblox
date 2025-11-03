--!strict
-- Publishes "noise.emitted" footsteps while players move.
-- NoiseRouter will scale radius by the player's NoiseScalar (from StaminaService).

local Players = game:GetService 'Players'
local RS = game:GetService 'ReplicatedStorage'
local RunService = game:GetService 'RunService'

-- Works whether your EventBus is under ReplicatedStorage/Events or /Modules
local Events = RS:FindFirstChild 'Events' or RS:FindFirstChild 'Modules' or RS
local Bus = require(Events:WaitForChild 'EventBus')

-- Base hearing radius before NoiseScalar scaling
local BASE_RADIUS = 35

-- Step cadence by movement state (seconds between footsteps)
local PERIOD = { Walk = 0.50, Sneak = 0.60, Sprint = 0.33 }

local function moveState(plr: Player, hum: Humanoid): 'Idle' | 'Walk' | 'Sneak' | 'Sprint'
  local moving = hum.MoveDirection.Magnitude > 0.05
  if not moving then
    return 'Idle'
  end
  if plr:GetAttribute 'IsSprinting' then
    return 'Sprint'
  end
  if plr:GetAttribute 'IsSneaking' then
    return 'Sneak'
  end
  return 'Walk'
end

local function startCharacterLoop(plr: Player, char: Model)
  local hum = char:WaitForChild 'Humanoid' :: Humanoid
  local root = char:WaitForChild 'HumanoidRootPart' :: BasePart

  local alive = true
  hum.Died:Once(function()
    alive = false
  end)

  local acc = 0
  local last = os.clock()

  task.spawn(function()
    while alive and char.Parent do
      local now = os.clock()
      local dt = now - last
      last = now

      local state = moveState(plr, hum)

      -- Only emit when on the ground and moving
      if state ~= 'Idle' and hum.FloorMaterial ~= Enum.Material.Air then
        acc += dt
        local period = (state == 'Sprint' and PERIOD.Sprint)
          or (state == 'Sneak' and PERIOD.Sneak)
          or PERIOD.Walk

        if acc >= period then
          acc -= period

          -- Keep loudness at 1.0; NoiseRouter multiplies radius by NoiseScalar
          Bus.publish('noise.emitted', {
            pos = root.Position,
            loudness = 1.0,
            radius = BASE_RADIUS,
            source = 'footstep',
            actor = plr, -- lets router read NoiseScalar
          })
        end
      else
        acc = 0
      end

      RunService.Heartbeat:Wait()
    end
  end)
end

local function trackPlayer(plr: Player)
  -- existing character
  if plr.Character then
    startCharacterLoop(plr, plr.Character)
  end
  -- future spawns
  plr.CharacterAdded:Connect(function(char)
    startCharacterLoop(plr, char)
  end)
end

Players.PlayerAdded:Connect(trackPlayer)
for _, p in ipairs(Players:GetPlayers()) do
  trackPlayer(p)
end

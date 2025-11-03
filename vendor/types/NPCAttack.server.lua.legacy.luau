--!strict
local Players = game:GetService 'Players'
local RS = game:GetService 'ReplicatedStorage'
local RunService = game:GetService 'RunService'
local Bus = require(RS:WaitForChild('Events'):WaitForChild 'EventBus')

local DEBUG = true
local function log(...)
  if DEBUG then
    print('[NPCAttack]', ...)
  end
end

-- i-frames per player so NPCs can’t machine-gun
local lastHit: { [number]: number } = {}
local IFRAME = 0.5 -- seconds between taking damage

local function isDowned(plr: Player): boolean
  local ch = plr.Character
  return ch and ch:GetAttribute 'Downed' == true or false
end

-- publish a player-damage event everyone can subscribe to
local function damagePlayer(attackerModel: Model, targetPlayer: Player, amount: number)
  -- hard guard: never damage downed targets
  if isDowned(targetPlayer) then
    return
  end

  local t = os.clock()
  local last = lastHit[targetPlayer.UserId] or 0
  if t - last < IFRAME then
    return
  end
  lastHit[targetPlayer.UserId] = t

  Bus.publish('combat.player_hit', {
    attacker = attackerModel,
    player = targetPlayer,
    damage = amount,
  })
end

-- small loop: any tagged NPC near a player will attack on a cooldown
local ATTACK_RANGE = 4.0
local ATTACK_COOLDOWN = 1.2
local lastSwing: { [Model]: number } = {}

local function getHRP(model: Model): BasePart?
  return (model:FindFirstChild 'HumanoidRootPart' :: any) or model.PrimaryPart
end

RunService.Heartbeat:Connect(function()
  local now = os.clock()
  for _, m in ipairs(workspace:GetDescendants()) do
    if m:IsA 'Model' and (m:GetAttribute 'IsGoblin' or m:GetAttribute 'DamageableNPC') then
      local hum = m:FindFirstChildOfClass 'Humanoid'
      if hum and hum.Health > 0 then
        local root = getHRP(m)
        if not root then
          continue
        end

        -- find the nearest NON-DOWNED player
        local closestP: Player? = nil
        local closestD = math.huge
        for _, plr in ipairs(Players:GetPlayers()) do
          if isDowned(plr) then
            -- skip downed players entirely
            continue
          end
          local ch = plr.Character
          local hrp = ch and ch:FindFirstChild 'HumanoidRootPart'
          local ph = ch and ch:FindFirstChildOfClass 'Humanoid'
          if hrp and ph and ph.Health > 0 then
            local d = (hrp.Position - root.Position).Magnitude
            if d < closestD then
              closestD, closestP = d, plr
            end
          end
        end

        if closestP and closestD <= ATTACK_RANGE then
          local last = lastSwing[m] or 0
          if now - last >= ATTACK_COOLDOWN then
            lastSwing[m] = now
            log('Swing', m.Name, '->', closestP.Name, ('%.1f studs'):format(closestD))
            damagePlayer(m, closestP, 12) -- base NPC melee damage
          end
        end
      end
    end
  end
end)

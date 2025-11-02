--!strict
-- Consumes combat.player_hit and resolves blocking + damage.
local Players = game:GetService 'Players'
local RS = game:GetService 'ReplicatedStorage'
local Bus = require(RS:WaitForChild('Events'):WaitForChild 'EventBus')

local DEBUG = true
local function log(...)
  if DEBUG then
    print('[PlayerDamage]', ...)
  end
end

-- EventBus compatibility helpers
local function busOn(topic: string, fn: (...any) -> ()): RBXScriptConnection?
  for _, name in ipairs { 'On', 'Connect', 'Subscribe', 'subscribe' } do
    local f = (Bus :: any)[name]
    if typeof(f) == 'function' then
      return f(topic, fn)
    end
  end
  error 'EventBus missing On/Connect/Subscribe'
end
local function busFire(topic: string, payload: any?)
  for _, name in ipairs { 'Fire', 'Publish', 'publish', 'Emit', 'emit' } do
    local f = (Bus :: any)[name]
    if typeof(f) == 'function' then
      f(topic, payload)
      return
    end
  end
  error 'EventBus missing Fire/Publish/Emit'
end

-- Resolve a player’s humanoid safely
local function getHum(plr: Player): Humanoid?
  local ch = plr.Character
  if not ch then
    return nil
  end
  local hum = ch:FindFirstChildOfClass 'Humanoid'
  if not hum or hum.Health <= 0 then
    return nil
  end
  return hum
end

-- Main handler: NPC -> Player hit attempts
busOn('combat.player_hit', function(e: any)
  -- Normalize payload from NPCAttack
  local attackerModel: Model? = e and e.attacker or nil
  local targetPlayer: Player? = e and e.player or nil
  local amount: number = tonumber(e and e.damage) or 0

  if not targetPlayer or amount <= 0 then
    return
  end
  local hum = getHum(targetPlayer)
  if not hum then
    return
  end
  local ch = targetPlayer.Character
  if not ch then
    return
  end

  -- If player is currently blocking, consume the hit and charge stamina
  if ch:GetAttribute 'IsBlocking' == true then
    log(
      'Blocked hit:',
      attackerModel and attackerModel.Name or '?',
      '->',
      targetPlayer.Name,
      'for',
      amount
    )

    -- Tell the stamina service to spend the extra "successful block" cost
    -- (CombatService.server.lua listens to this)
    busFire('Combat:ShieldBlocked', targetPlayer)

    -- Optional: tiny chip damage or stagger could go here instead of hard negate.
    -- hum:TakeDamage(math.min(2, amount * 0.1))

    return -- cancel damage
  end

  -- Not blocking -> apply full damage
  log('Damage applied:', targetPlayer.Name, amount)
  hum:TakeDamage(amount)
end)

log 'PlayerDamage ready (listening for combat.player_hit).'

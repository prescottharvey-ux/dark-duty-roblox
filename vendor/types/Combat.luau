--!strict
-- ReplicatedStorage/Modules/Combat/Combat.lua
local Players = game:GetService 'Players'
local RS = game:GetService 'ReplicatedStorage'
local Workspace = game:GetService 'Workspace'

local Bus = require(RS:WaitForChild('Events'):WaitForChild 'EventBus')

-- Optional helpers (safe fallbacks if missing)
local Noise = (function()
  local ok, mod = pcall(function()
    return require(RS:WaitForChild('Modules'):WaitForChild 'Noise')
  end)
  return ok and mod or { Emit = function() end }
end)()

local Durability = (function()
  local ok, mod = pcall(function()
    return require(RS:WaitForChild('Modules'):WaitForChild 'Durability')
  end)
  return ok and mod or { Tick = function() end }
end)()

local ItemDB = (function()
  local ok, mod = pcall(function()
    return require(RS:WaitForChild('Modules'):WaitForChild 'ItemDB')
  end)
  return ok and mod or {}
end)()

local Combat = {}

-- === Tunables ===
local DEFAULT_MELEE_RANGE = 5.0
local DEFAULT_DAMAGE = 21

-- === Helpers ===
local function itemWeight(id: string?): number
  if not id then
    return 0
  end
  local d = (typeof((ItemDB :: any).GetItem) == 'function') and (ItemDB :: any).GetItem(id)
    or (ItemDB :: any)[id]
  local w = (type(d) == 'table' and typeof((d :: any).weight) == 'number') and (d :: any).weight
    or 0
  return w
end

local function computeDamage(weaponId: string?): number
  local w = itemWeight(weaponId)
  if w <= 0 then
    return DEFAULT_DAMAGE
  end
  return math.clamp(12 + math.floor(w * 3), 10, 50)
end

-- === Player -> NPC (server-auth melee) ===
-- Back-compat signatures:
--   ApplyMelee(attacker, targetMaybe, weaponIdMaybe)
--   ApplyMelee(attacker, weaponIdString)
function Combat.ApplyMelee(attacker: Player, targetMaybe: Instance?, weaponIdMaybe: string?)
  -- Normalize old/new args (weaponId in 2nd or 3rd position)
  local weaponId = weaponIdMaybe
  if typeof(targetMaybe) == 'string' and weaponIdMaybe == nil then
    weaponId = targetMaybe :: any
  end

  if not attacker or not attacker.Character then
    return { dmg = 0, killed = false, hit = false }
  end
  local char = attacker.Character
  local hrp = char:FindFirstChild 'HumanoidRootPart' :: BasePart?
  if not hrp then
    return { dmg = 0, killed = false, hit = false }
  end

  -- Short, safe raycast in look direction
  local params = RaycastParams.new()
  params.FilterType = Enum.RaycastFilterType.Exclude
  params.FilterDescendantsInstances = { char }
  params.IgnoreWater = true

  local rc = Workspace:Raycast(hrp.Position, hrp.CFrame.LookVector * DEFAULT_MELEE_RANGE, params)
  if not rc then
    Bus.Fire('combat.swing', { attacker = attacker, hit = false })
    return { dmg = 0, killed = false, hit = false }
  end

  local hitModel = rc.Instance:FindFirstAncestorOfClass 'Model'
  local hum = hitModel and hitModel:FindFirstChildOfClass 'Humanoid' :: Humanoid?
  if not hum then
    Bus.Fire('combat.swing', { attacker = attacker, hit = false })
    return { dmg = 0, killed = false, hit = false }
  end

  local dmg = computeDamage(weaponId)
  local before = hum.Health
  hum:TakeDamage(dmg)

  -- Side-effects (best-effort)
  pcall(function()
    (Durability :: any).Tick(attacker, weaponId or '', 1)
  end)
  pcall(function()
    (Noise :: any).Emit(rc.Position, 'Melee')
  end)

  -- Bus events for other systems
  Bus.Fire('combat.hit', dmg) -- ultra-compat simple payload
  Bus.Fire('combat.player_hit_npc', {
    attacker = attacker,
    weaponId = weaponId,
    humanoid = hum,
    amount = dmg,
    pos = rc.Position,
    before = before,
    after = hum.Health,
  })

  return { dmg = dmg, killed = hum.Health <= 0, hit = true, pos = rc.Position }
end

-- === NPC -> Player central gate ===
-- Respects Character attribute "IsBlocking".
-- Fires your existing topic ("Combat:ShieldBlocked") and a compatibility topic ("Combat:BlockedHit").
function Combat.ApplyNPCHit(attackerModel: Model, victimHum: Humanoid, baseDamage: number)
  if not victimHum or victimHum.Health <= 0 then
    return { blocked = false, dmg = 0 }
  end

  local char = victimHum.Parent
  local plr = char and Players:GetPlayerFromCharacter(char)

  if plr and char and (char:GetAttribute 'IsBlocking' == true) then
    -- Original topic (kept):
    Bus.Fire('Combat:ShieldBlocked', plr)
    -- Compat topic (structured payload used by some newer listeners):
    Bus.Fire('Combat:BlockedHit', {
      Player = plr,
      Attacker = attackerModel,
      Damage = baseDamage,
      Char = char,
    })
    return { blocked = true, dmg = 0 }
  end

  victimHum:TakeDamage(baseDamage)
  return { blocked = false, dmg = baseDamage }
end

return Combat

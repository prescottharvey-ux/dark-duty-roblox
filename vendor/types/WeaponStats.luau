--!strict
-- Single source of truth for per-weapon tuning:
--   - damage, swingTime, stamina (may use StaminaService), chargeFuse
--   - weight (from ItemDB/overrides)
--   - hitBox spec (width/height/length + forwardBias), weight-driven with overrides
--   - chargeSpec for dagger (requiredHold, charged multipliers & finisher damage)
--
-- Reads (all optional):
--   ReplicatedStorage/Config/StaminaConfig
--   ReplicatedStorage/Modules/ItemDB
--   _G.StaminaService

local RS = game:GetService 'ReplicatedStorage'

-- ===== Defaults (used when config/ItemDB not present) =====
local DEFAULT = {
  Costs = {
    SwingFlat = 12,
    WeightToSwing = { Base = 6, PerUnit = 2.0, Min = 5, Max = 30 },
    Weapon = {}, -- hard overrides per item id
  },
  Weapons = {
    -- Weight → swingTime (seconds)
    WeightToSwingTime = { Base = 0.34, PerUnit = 0.030, Min = 0.24, Max = 0.90 },
    -- Weight → damage
    WeightToDamage = { Base = 18, PerUnit = 3.0, Min = 12, Max = 50 },
    -- Weight → hitBox (size + offset)
    HitBox = {
      Width = { Base = 2.0, PerUnit = 0.35, Min = 1.8, Max = 4.5 },
      Height = { Base = 2.2, PerUnit = 0.35, Min = 2.0, Max = 4.2 },
      Length = { Base = 3.2, PerUnit = 0.90, Min = 2.8, Max = 7.0 },
      ForwardBias = 0.90, -- extra push forward beyond half-length, to avoid self-overlap
      DaggerScale = { Width = 0.85, Height = 0.90, Length = 0.95 }, -- small tweak for daggers
    },
    -- Optional hard overrides per item id:
    -- Overrides = {
    --   Dagger = { damage=12, swingTime=0.30, stamina=8, weightOverride=0.3,
    --              hitBox = { width=1.9, height=2.0, length=3.0, forwardBias=0.85 } },
    -- }
    Overrides = {},
  },
  -- Dagger charge spec (server-authoritative; client just mirrors UI)
  Charge = {
    Dagger = {
      requiredHold = 1.0, -- seconds to count as "charged"
      chargedStaminaMult = 1.20, -- stamina multiplier vs light
      chargedDamage = 34, -- heavy baseline (near greatsword)
      backstabKillDamage = 200, -- finisher threshold for most players
    },
  },
}

-- Lightweight local overrides (keeps sensible fallbacks if ItemDB missing)
local LOCAL_OVERRIDES: { [string]: { weightOverride: number?, damage: number? } } = {
  DebugSword = { weightOverride = 1.0, damage = 20 },
  Greatsword = { weightOverride = 4.0, damage = 35 },
  Dagger = { weightOverride = 0.3, damage = 12 },
}

-- ===== tiny utils =====
local function clamp(x: number, a: number, b: number): number
  if x < a then
    return a
  end
  if x > b then
    return b
  end
  return x
end

local function shallowMerge(dst: any, src: any)
  for k, v in pairs(src) do
    if type(v) == 'table' and type(dst[k]) == 'table' then
      for k2, v2 in pairs(v) do
        dst[k][k2] = v2
      end
    else
      dst[k] = v
    end
  end
  return dst
end

-- ===== Safe load of (optional) StaminaConfig =====
local function loadStaminaConfig(): any?
  local cfgFolder = RS:FindFirstChild 'Config'
  local mod = cfgFolder and cfgFolder:FindFirstChild 'StaminaConfig'
  if mod and mod:IsA 'ModuleScript' then
    local ok, t = pcall(require, mod)
    if ok and type(t) == 'table' then
      return t
    end
  end
  return nil
end

local CFG: any = shallowMerge(table.clone(DEFAULT), loadStaminaConfig() or {})

-- ===== Optional ItemDB (for weight) =====
local ItemDB: any = nil
do
  local m = RS:FindFirstChild 'Modules'
  if m and m:FindFirstChild 'ItemDB' then
    local ok, tbl = pcall(function()
      return require(m.ItemDB)
    end)
    if ok and type(tbl) == 'table' then
      ItemDB = tbl
    end
  end
end

-- ===== Optional StaminaService (authoritative for stamina costs if present) =====
local StaminaService: any = rawget(_G, 'StaminaService')

-- ===== weight lookup =====
local function getWeight(itemId: string): number?
  -- Prefer ItemDB if available
  if ItemDB then
    local ok, w = pcall(function()
      if typeof(ItemDB.GetItem) == 'function' then
        local item = ItemDB.GetItem(itemId)
        if item and typeof(item) == 'table' then
          return item.weight or item.Weight
        end
      end
      local entry = ItemDB[itemId]
      return entry and (entry.weight or entry.Weight)
    end)
    if ok and typeof(w) == 'number' then
      return w
    end
  end
  -- Config overrides (weightOverride)
  local ovCfg = (CFG.Weapons and CFG.Weapons.Overrides) or {}
  local ov = ovCfg[itemId]
  if ov and typeof(ov) == 'table' and typeof(ov.weightOverride) == 'number' then
    return ov.weightOverride
  end
  -- Local fallbacks
  local loc = LOCAL_OVERRIDES[itemId]
  if loc and typeof(loc.weightOverride) == 'number' then
    return loc.weightOverride
  end
  return nil
end

-- ===== stamina cost (prefers service, else config/weight curve) =====
local function staminaCost(itemId: string, p: Player?): number
  -- Authoritative service (can include encumbrance etc.)
  if StaminaService and typeof(StaminaService.SwingCost) == 'function' then
    local ok, val = pcall(function()
      return StaminaService.SwingCost(itemId, p)
    end)
    if ok and typeof(val) == 'number' then
      return val
    end
  end

  -- Config hard override?
  local overrideMap = (CFG.Costs and CFG.Costs.Weapon) or {}
  local hard = overrideMap[itemId]
  if typeof(hard) == 'number' then
    return hard
  end

  -- Weight curve fallback
  local tun = (CFG.Costs and CFG.Costs.WeightToSwing) or DEFAULT.Costs.WeightToSwing
  local base = tun.Base or 6
  local per = tun.PerUnit or 2
  local minC = tun.Min or 5
  local maxC = tun.Max or 30

  local w = getWeight(itemId)
  local cost = (w and (base + per * w))
    or ((CFG.Costs and CFG.Costs.SwingFlat) or DEFAULT.Costs.SwingFlat)
  return clamp(cost, minC, maxC)
end

-- ===== swing time (weight curve with optional per-item override) =====
local function swingTime(itemId: string): number
  local ovMap = (CFG.Weapons and CFG.Weapons.Overrides) or {}
  local ov = ovMap[itemId]
  if ov and typeof(ov) == 'table' and typeof(ov.swingTime) == 'number' then
    return ov.swingTime
  end

  local t = (CFG.Weapons and CFG.Weapons.WeightToSwingTime) or DEFAULT.Weapons.WeightToSwingTime
  local base = t.Base or 0.34
  local per = t.PerUnit or 0.03
  local minT = t.Min or 0.24
  local maxT = t.Max or 0.90

  local w = getWeight(itemId)
  local s = (w and (base + per * w)) or base
  return clamp(s, minT, maxT)
end

-- ===== damage (weight curve with optional per-item override) =====
local function damage(itemId: string): number
  local ovMap = (CFG.Weapons and CFG.Weapons.Overrides) or {}
  local ov = ovMap[itemId]
  if ov and typeof(ov) == 'table' and typeof(ov.damage) == 'number' then
    return ov.damage
  end

  local t = (CFG.Weapons and CFG.Weapons.WeightToDamage) or DEFAULT.Weapons.WeightToDamage
  local base = t.Base or 18
  local per = t.PerUnit or 3.0
  local minD = t.Min or 12
  local maxD = t.Max or 50

  local w = getWeight(itemId)
  local d = (w and (base + per * w)) or base
  return clamp(d, minD, maxD)
end

-- ===== fuse window (prevents double charge) =====
local function chargeFuse(itemId: string): number
  local st = swingTime(itemId)
  return clamp(st * 0.65, 0.18, 0.60)
end

-- ===== hitBox (weight curve with optional per-item override) =====
export type HitBox = { size: Vector3, forwardBias: number }

local function isDaggerId(id: string): boolean
  local s = string.lower(id)
  return string.find(s, 'dagger', 1, true) ~= nil or id == 'Dagger'
end

local function hitBox(itemId: string): HitBox
  -- Per-item hard override
  local ovMap = (CFG.Weapons and CFG.Weapons.Overrides) or {}
  local ov = ovMap[itemId]
  if ov and typeof(ov) == 'table' and ov.hitBox then
    local hb = ov.hitBox
    if typeof(hb) == 'table' then
      -- accept {size=Vector3, forwardBias=number} OR {width=,height=,length=, forwardBias=}
      if typeof(hb.size) == 'Vector3' then
        return {
          size = hb.size,
          forwardBias = hb.forwardBias
            or (CFG.Weapons.HitBox and CFG.Weapons.HitBox.ForwardBias)
            or DEFAULT.Weapons.HitBox.ForwardBias,
        }
      else
        local w = hb.width or 2.0
        local h = hb.height or 2.2
        local l = hb.length or 3.2
        return {
          size = Vector3.new(w, h, l),
          forwardBias = hb.forwardBias
            or (CFG.Weapons.HitBox and CFG.Weapons.HitBox.ForwardBias)
            or DEFAULT.Weapons.HitBox.ForwardBias,
        }
      end
    end
  end

  -- Weight-driven default
  local HB = (CFG.Weapons and CFG.Weapons.HitBox) or DEFAULT.Weapons.HitBox
  local w = getWeight(itemId) or 1.0

  local function calc(a: any): number
    local base = a.Base or 0
    local per = a.PerUnit or 0
    local mn = a.Min or -math.huge
    local mx = a.Max or math.huge
    return clamp(base + per * w, mn, mx)
  end

  local width = calc(HB.Width)
  local height = calc(HB.Height)
  local length = calc(HB.Length)

  if isDaggerId(itemId) and HB.DaggerScale then
    width = width * (HB.DaggerScale.Width or 1.0)
    height = height * (HB.DaggerScale.Height or 1.0)
    length = length * (HB.DaggerScale.Length or 1.0)
  end

  return {
    size = Vector3.new(width, height, length),
    forwardBias = HB.ForwardBias or DEFAULT.Weapons.HitBox.ForwardBias,
  }
end

-- ===== optional chargeSpec (dagger) =====
local function getChargeSpec(itemId: string): any?
  if isDaggerId(itemId) then
    return (CFG.Charge and CFG.Charge.Dagger) or DEFAULT.Charge.Dagger
  end
  return nil
end

-- ===== public API =====
local M = {}

export type WeaponStats = {
  damage: number,
  swingTime: number,
  chargeFuse: number,
  stamina: number,
  weight: number?,
}

function M.get(itemId: string, p: Player?): WeaponStats
  local w = getWeight(itemId)
  return {
    damage = damage(itemId),
    swingTime = swingTime(itemId),
    stamina = staminaCost(itemId, p),
    chargeFuse = chargeFuse(itemId),
    weight = w,
  }
end

function M.damage(itemId: string): number
  return damage(itemId)
end
function M.swingTime(itemId: string): number
  return swingTime(itemId)
end
function M.stamina(itemId: string, p: Player?): number
  return staminaCost(itemId, p)
end
function M.chargeFuse(itemId: string): number
  return chargeFuse(itemId)
end

-- NEW:
function M.hitBox(itemId: string): HitBox
  return hitBox(itemId)
end
function M.getChargeSpec(itemId: string): any?
  return getChargeSpec(itemId)
end

return M

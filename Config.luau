-- ReplicatedStorage/Modules/Config.lua
--!strict
-- Bridge module so `require("Config")` works from ReplicatedStorage/Modules.
-- Preserves Get/Set + Changed and (optionally) merges in RS/Config/* sub-modules.
-- NEW: Derives Combat.Weapons and Loot.GearPools from ItemDB if available,
--      so ItemDB is the source of truth.

local RS = game:GetService 'ReplicatedStorage'

local Config: any = {}

-- ===== Feature flags =====
Config.Flags = { Noise = true, Durability = true, Egg = true, Stamina = true }

-- ===== Round timings & doors =====
Config.Timers = { RoundLength = 360, FirstExtractOpen = 120, SecondExtractOpen = 240 }

-- ===== Locks / Interactions =====
Config.Locks = {
  ChestBase = 1.5,
  DoorBase = 2.5,
  WithLockpickMult = 0.75,
  NoLockpickMult = 2.0,
  InterruptOnDamage = false,
}

-- ===== Stamina & Encumbrance =====
Config.Stamina = {
  Max = 100,
  RegenPerSec = 12,
  SneakBonusMult = 1.4,
  AttackCost = 8,
  SprintCostPerSec = 16,
  DashCost = 20,
  WeightToMaxStamina = 0.25,
  WeightToSpeedMult = 0.01,
}

-- ===== Durability (dots) =====
Config.Durability = {
  WeaponUseLoss = 1,
  ShieldBlockLoss = 2,
  LockpickUseLoss = 1,
  RepairCostBase = 5,
  RepairRarityMult = { Common = 1.0, Uncommon = 1.2, Rare = 1.6, Epic = 2.2, Legendary = 3.0 },
}

-- ===== Noise tiers → radius (studs) =====
Config.Noise = {
  TierRadius = {
    FootstepLight = 18,
    FootstepMed = 28,
    FootstepHeavy = 40,
    Sprint = 52,
    Melee = 36,
    ChestOpen = 24,
  },
}

-- ===== Economy & loot (base defaults; can be overwritten by ItemDB derivation) =====
Config.Economy = { StashSlotsBase = 12, SellRates = { Treasure = 1.0, Gear = 0.6 } }
Config.RarityOrder = { 'Common', 'Uncommon', 'Rare', 'Epic', 'Legendary' }

Config.Combat = {
  BackstabMult = 1.5,
  -- Will be replaced by ItemDB-derived data if possible:
  Weapons = {
    Sword_Iron = { DamageDots = 3, Weight = 7, Rarity = 'Uncommon' },
    Dagger_Wood = { DamageDots = 1, Weight = 1, Rarity = 'Common', BackstabBonus = 2 },
    Bow_Short = { DamageDots = 2, Weight = 3, Rarity = 'Uncommon' },
  },
}

Config.Loot = {
  ZoneChance = { Treasure = 0.7, Gear = 0.3 },
  Z1 = { AddRarities = { 'Common', 'Uncommon' } },
  Z2 = { AddRarities = { 'Rare' } },
  Z3 = { AddRarities = { 'Epic' } },
  Z4 = { AddRarities = { 'Legendary' } },
  -- Will be replaced by ItemDB-derived pools if possible:
  GearPools = {
    Z1 = { 'Dagger_Wood', 'Sword_Iron', 'Bow_Short' },
    Z2 = { 'Sword_Iron', 'Bow_Short' },
    Z3 = { 'Bow_Short' },
    Z4 = { 'Sword_Iron' },
  },
}

Config.Egg = { Weight = 12, BeaconEnabled = true, BeaconInterval = 2.0 }

-- ===== Get/Set + Changed =====
local Changed = Instance.new 'BindableEvent'
Config.Changed = Changed.Event

local function split(path: string): { string }
  local t = {}
  for seg in string.gmatch(path, '([^%.]+)') do
    t[#t + 1] = seg
  end
  return t
end

function Config.Get(path: string, default: any?): any
  local node: any = Config
  for _, seg in ipairs(split(path)) do
    node = node and node[seg] or nil
  end
  return node == nil and default or node
end

function Config.Set(path: string, value: any)
  local segs = split(path)
  local node: any = Config
  for i = 1, #segs - 1 do
    local k = segs[i]
    if type(node[k]) ~= 'table' then
      node[k] = {}
    end
    node = node[k]
  end
  node[segs[#segs]] = value
  Changed:Fire(path, value)
end

-- ===== Try to derive Weapons + GearPools from ItemDB =====
local function safeRequireItemDB()
  local ok, mod = pcall(function()
    return require(RS:WaitForChild('Modules'):WaitForChild 'ItemDB')
  end)
  return ok and mod or nil
end

local function toLowerStr(v: any): string?
  if type(v) ~= 'string' then
    return nil
  end
  return string.lower(v)
end

local function rarityFrom(def: any): string?
  -- Accept various casings/fields
  return def and (def.Rarity or def.rarity or (def.meta and (def.meta.Rarity or def.meta.rarity)))
end

local function equipSlotFrom(def: any): string?
  local slot = def and ((def.equip and def.equip.slot) or def.equipSlot or def.slot)
  return toLowerStr(slot)
end

local function damageDotsFrom(def: any): number?
  local v = def and (def.DamageDots or def.damageDots or def.damage or def.Damage)
  return (type(v) == 'number') and v or nil
end

local function weightFrom(def: any): number?
  local v = def and (def.Weight or def.weight)
  return (type(v) == 'number') and v or nil
end

local function backstabFrom(def: any): number?
  local v = def and (def.BackstabBonus or def.backstabBonus)
  return (type(v) == 'number') and v or nil
end

local function looksLikeItem(def: any): boolean
  return type(def) == 'table'
    and (def.equip ~= nil or def.type ~= nil or def.weight ~= nil or def.Weight ~= nil)
end

local function enumerateItemDB(ItemDB: any): { [string]: any }
  -- Try common shapes: Items table, GetAll(), or the module table itself.
  local out: { [string]: any } = {}

  local function addAll(tbl: any)
    if type(tbl) ~= 'table' then
      return
    end
    for id, def in pairs(tbl) do
      if type(id) == 'string' and looksLikeItem(def) then
        out[id] = def
      end
    end
  end

  if ItemDB == nil then
    return out
  end
  if type(ItemDB.Items) == 'table' then
    addAll(ItemDB.Items)
  end

  if type(ItemDB.GetAll) == 'function' then
    local ok, res = pcall(ItemDB.GetAll)
    if ok then
      addAll(res)
    end
  end

  -- Fallback: scan the table itself (skip functions/utility fields)
  if next(out) == nil and type(ItemDB) == 'table' then
    addAll(ItemDB)
  end

  return out
end

local function deriveFromItemDB()
  local ItemDB = safeRequireItemDB()
  if not ItemDB then
    return
  end

  local items = enumerateItemDB(ItemDB)
  if next(items) == nil then
    return
  end

  -- Optional alias map if ItemDB exposes one (nice to have, not required)
  local Aliases = (type(ItemDB.Aliases) == 'table') and ItemDB.Aliases or nil
  local function canon(id: string): string
    if Aliases and type(Aliases[id]) == 'string' then
      return Aliases[id]
    end
    return id
  end

  -- Build Combat.Weapons from hand-slot items that look like weapons.
  local derivedWeapons: { [string]: any } = {}
  for id, def in pairs(items) do
    local slot = equipSlotFrom(def)
    if slot == 'hand' then
      local dmg = damageDotsFrom(def)
      local wt = weightFrom(def)
      local rar = rarityFrom(def) or 'Common'
      if dmg or wt or rar then
        derivedWeapons[canon(id)] = {
          DamageDots = dmg or 1,
          Weight = wt or 0,
          Rarity = rar,
          BackstabBonus = backstabFrom(def),
        }
      end
    end
  end
  if next(derivedWeapons) ~= nil then
    Config.Combat.Weapons = derivedWeapons
  end

  -- Build Loot.GearPools by rarity buckets (hand-slot gear only).
  local pools = { Z1 = {}, Z2 = {}, Z3 = {}, Z4 = {} }
  for id, def in pairs(items) do
    if equipSlotFrom(def) == 'hand' then
      local r = toLowerStr(rarityFrom(def) or 'Common')
      local cid = canon(id)
      if r == 'legendary' then
        table.insert(pools.Z4, cid)
      elseif r == 'epic' then
        table.insert(pools.Z3, cid)
      elseif r == 'rare' then
        table.insert(pools.Z2, cid)
      else
        -- Common / Uncommon default to Z1
        table.insert(pools.Z1, cid)
      end
    end
  end

  -- Keep lists stable for diffs/logs
  local function sortList(t)
    table.sort(t, function(a, b)
      return tostring(a) < tostring(b)
    end)
  end
  sortList(pools.Z1)
  sortList(pools.Z2)
  sortList(pools.Z3)
  sortList(pools.Z4)

  if #pools.Z1 + #pools.Z2 + #pools.Z3 + #pools.Z4 > 0 then
    Config.Loot.GearPools = pools
  end
end

-- Try to derive values from ItemDB. If anything fails, we leave your defaults intact.
pcall(deriveFromItemDB)

-- ===== Optional: merge in ReplicatedStorage/Config/* (if present) =====
local function deepMerge(dst: any, src: any)
  if type(dst) ~= 'table' or type(src) ~= 'table' then
    return
  end
  for k, v in pairs(src) do
    if type(v) == 'table' then
      if type(dst[k]) ~= 'table' then
        dst[k] = {}
      end
      deepMerge(dst[k], v)
    else
      dst[k] = v
    end
  end
end

local cfgFolder = RS:FindFirstChild 'Config'
if cfgFolder and cfgFolder:IsA 'Folder' then
  for _, mod in ipairs(cfgFolder:GetChildren()) do
    if mod:IsA 'ModuleScript' then
      local ok, tbl = pcall(require, mod)
      if ok and type(tbl) == 'table' then
        deepMerge(Config, tbl)
      end
    end
  end
end

return Config

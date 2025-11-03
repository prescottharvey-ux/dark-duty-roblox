-- ReplicatedStorage/Modules/ItemDB.lua
--!strict

-- =========================
-- Types
-- =========================
export type DurabilityWeapon = {
  type: 'weapon',
  max: number,
  costs: { swing: number?, hit: number? }?,
  breaksWhenZero: boolean?,
}

export type DurabilityArmor = {
  type: 'armor',
  max: number,
  perDamage: number, -- wear per point of incoming damage
  breaksWhenZero: boolean?,
}

export type DurabilityBurn = {
  type: 'burn',
  max: number, -- total burn seconds
  burnPerSecond: number, -- durability per second while lit
  breaksWhenZero: boolean?,
}

export type DurabilityUse = {
  type: 'use',
  max: number,
  useCost: number, -- per use/cast/attempt
  breaksWhenZero: boolean?,
}

export type Durability = DurabilityWeapon | DurabilityArmor | DurabilityBurn | DurabilityUse

export type Item = {
  name: string?,
  displayName: string?,
  type: string?, -- "Weapon" | "Armor" | "Shield" | "Light" | "Tool" | "Magic" | "Loot" | "Consumable" | "Egg" | "PetToken" | "Trinket"
  rarity: string?, -- "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | etc.
  weight: number?, -- round number
  hotbar: boolean?,
  bindable: boolean?,
  slot: string?, -- legacy hint
  equip: { slot: string, twoHanded: boolean? }?,
  equipSlot: string?,
  twoHanded: boolean?,
  grip: CFrame?,
  stackable: boolean?,
  sellValue: number?,
  icon: string?,
  durability: Durability?,
}

-- =========================
-- Constants
-- =========================
local DEFAULT_WEIGHT = 0
local DISPLAY_FALLBACK = '[unnamed]'

local ItemDB = {}

-- =========================
-- Items (standardized)
-- =========================
local Items: { [string]: Item } = {
  -- ===== Loot / Misc (no durability) =====
  coin_pouch = {
    displayName = 'Coin Pouch',
    type = 'Loot',
    rarity = 'Common',
    weight = 0,
  },
  bandage = {
    displayName = 'Bandage',
    type = 'Consumable',
    rarity = 'Common',
    weight = 0,
  },
  ruby = {
    displayName = 'Ruby',
    type = 'Loot',
    rarity = 'Rare',
    weight = 1,
  },
  sapphire = {
    displayName = 'Sapphire',
    type = 'Loot',
    rarity = 'Rare',
    weight = 1,
  },
  idol = {
    displayName = 'Idol',
    type = 'Loot',
    rarity = 'Epic',
    weight = 4,
  },
  chalice = {
    displayName = 'Chalice',
    type = 'Loot',
    rarity = 'Legendary',
    weight = 6,
  },

  -- ===== Armor (durability: armor) =====
  helmet_leather = {
    displayName = 'Leather Helmet',
    type = 'Armor',
    rarity = 'Common',
    weight = 1,
    equip = { slot = 'head' },
    durability = { type = 'armor', max = 120, perDamage = 0.06, breaksWhenZero = false },
  },
  armor_leather = {
    displayName = 'Leather Armor',
    type = 'Armor',
    rarity = 'Common',
    weight = 4,
    equip = { slot = 'torso' },
    durability = { type = 'armor', max = 200, perDamage = 0.08, breaksWhenZero = false },
  },
  gloves_leather = {
    displayName = 'Leather Gloves',
    type = 'Armor',
    rarity = 'Common',
    weight = 1,
    equip = { slot = 'hands' },
    durability = { type = 'armor', max = 100, perDamage = 0.05, breaksWhenZero = false },
  },
  legs_leather = {
    displayName = 'Leather Leggings',
    type = 'Armor',
    rarity = 'Common',
    weight = 3,
    equip = { slot = 'legs' },
    durability = { type = 'armor', max = 160, perDamage = 0.07, breaksWhenZero = false },
  },
  boots_leather = {
    displayName = 'Leather Boots',
    type = 'Armor',
    rarity = 'Common',
    weight = 1,
    equip = { slot = 'feet' },
    durability = { type = 'armor', max = 120, perDamage = 0.06, breaksWhenZero = false },
  },
  trinket_charm = {
    displayName = 'Charm',
    type = 'Trinket',
    rarity = 'Uncommon',
    weight = 0,
    equip = { slot = 'trinket' },
    -- no durability (passive)
  },

  -- ===== Weapons / Shields =====
  dagger = {
    displayName = 'Dagger',
    type = 'Weapon',
    rarity = 'Common',
    weight = 1,
    hotbar = true,
    equip = { slot = 'hand', twoHanded = false },
    grip = CFrame.new(0, -0.40, -0.20) * CFrame.Angles(0, math.rad(90), 0),
    durability = { type = 'weapon', max = 120, costs = { swing = 1, hit = 1 }, breaksWhenZero = false },
  },
  sword_short = {
    displayName = 'Short Sword',
    type = 'Weapon',
    rarity = 'Common',
    weight = 2,
    hotbar = true,
    equip = { slot = 'hand', twoHanded = false },
    durability = { type = 'weapon', max = 140, costs = { swing = 1, hit = 2 }, breaksWhenZero = false },
  },
  shield_wood = {
    displayName = 'Wooden Shield',
    type = 'Shield',
    rarity = 'Common',
    weight = 3,
    hotbar = true,
    equip = { slot = 'hand', twoHanded = false },
    -- Treat shields like armor: they wear down on incoming damage / blocks
    durability = { type = 'armor', max = 160, perDamage = 0.10, breaksWhenZero = false },
  },

  -- ===== Light sources (durability: burn) =====
  torch = {
    displayName = 'Torch',
    type = 'Light',
    rarity = 'Common',
    weight = 1,
    hotbar = true,
    equip = { slot = 'hand', twoHanded = false },
    durability = { type = 'burn', max = 900, burnPerSecond = 1, breaksWhenZero = true }, -- ~15 minutes
  },
  candle = {
    displayName = 'Candle',
    type = 'Light',
    rarity = 'Common',
    weight = 0,
    hotbar = true,
    equip = { slot = 'hand', twoHanded = false },
    durability = { type = 'burn', max = 600, burnPerSecond = 1, breaksWhenZero = true }, -- ~10 minutes
  },

  -- ===== Magic / Tools (durability: use) =====
  spellbook_basic = {
    displayName = 'Spellbook',
    type = 'Magic',
    rarity = 'Uncommon',
    weight = 1,
    hotbar = true,
    equip = { slot = 'hand', twoHanded = false },
    durability = { type = 'use', max = 100, useCost = 1, breaksWhenZero = false },
  },
  bow_long = {
    displayName = 'Longbow',
    type = 'Weapon',
    rarity = 'Uncommon',
    weight = 2,
    hotbar = true,
    equip = { slot = 'hand', twoHanded = true },
    durability = { type = 'weapon', max = 130, costs = { swing = 1, hit = 1 }, breaksWhenZero = false },
  },
  Lockpick = {
    displayName = 'Lockpick',
    type = 'Tool',
    rarity = 'Common',
    weight = 1,
    hotbar = true,
    equip = { slot = 'hand', twoHanded = false },
    durability = { type = 'use', max = 20, useCost = 1, breaksWhenZero = true },
  },

  -- ===== Pets / Eggs (no durability) =====
  MonsterEgg = {
    displayName = 'Monster Egg',
    type = 'Egg',
    weight = 5,
    stackable = false,
    sellValue = 0,
    icon = 'rbxassetid://0',
  },
  PetToken_CommonChick = {
    displayName = 'Common Chick',
    type = 'PetToken',
    weight = 0,
    stackable = false,
    icon = 'rbxassetid://0',
  },
  PetToken_Slimelet = {
    displayName = 'Slimelet',
    type = 'PetToken',
    weight = 0,
    stackable = false,
    icon = 'rbxassetid://0',
  },
  PetToken_Glowbug = {
    displayName = 'Glowbug',
    type = 'PetToken',
    weight = 0,
    stackable = false,
    icon = 'rbxassetid://0',
  },
}

-- =========================
-- Rarity normalization
-- =========================
local function titleCaseRarity(raw: string?): string?
  if not raw then
    return nil
  end
  local s = string.lower(raw)
  if s == 'common' then
    return 'Common'
  end
  if s == 'uncommon' then
    return 'Uncommon'
  end
  if s == 'rare' then
    return 'Rare'
  end
  if s == 'epic' then
    return 'Epic'
  end
  if s == 'legendary' then
    return 'Legendary'
  end
  return raw
end

local function prettifyId(id: string): string
  local spaced = id:gsub('_', ' ')
  return spaced:sub(1, 1):upper() .. spaced:sub(2)
end

-- =========================
-- Normalize each item
-- =========================
for id, def in pairs(Items) do
  -- allow legacy Rarity field
  if (def :: any).Rarity and not def.rarity then
    def.rarity = (def :: any).Rarity
  end
  def.rarity = titleCaseRarity(def.rarity)

  -- ensure display name
  if not def.displayName then
    def.displayName = def.name and #def.name > 0 and def.name or prettifyId(id)
  end

  -- upgrade legacy slot/twoHanded to equip
  if not def.equip and def.slot then
    def.equip = { slot = def.slot, twoHanded = def.twoHanded }
  end
  if def.equip then
    if not def.equipSlot then
      def.equipSlot = def.equip.slot
    end
    if def.twoHanded == nil and def.equip.twoHanded ~= nil then
      def.twoHanded = def.equip.twoHanded
    end
  end

  -- default type: any hand-held without explicit type becomes Weapon
  local isHand = def.equip ~= nil and string.lower(def.equip.slot) == 'hand'
  if def.type == nil and isHand then
    def.type = 'Weapon'
  end

  -- bindability defaults: hand-held or hotbar implies bindable
  if def.bindable == nil then
    def.bindable = (def.hotbar == true) or isHand
  end
  if def.hotbar == nil then
    def.hotbar = def.bindable
  end

  -- legacy canBind alias
  if (def :: any).canBind == nil then
    (def :: any).canBind = def.bindable
  end
end

-- =========================
-- API
-- =========================
function ItemDB.GetItem(id: string): Item?
  return Items[id]
end
function ItemDB.RequireItem(id: string): Item
  local it = Items[id]
  assert(it, ("ItemDB: unknown item id '%s'"):format(id))
  return it
end
function ItemDB.DisplayName(id: string): string
  local it = ItemDB.RequireItem(id)
  return it.displayName or it.name or id or DISPLAY_FALLBACK
end
function ItemDB.WeightOf(id: string): number
  local it = ItemDB.RequireItem(id)
  return it.weight or DEFAULT_WEIGHT
end
function ItemDB.HasEquip(id: string): boolean
  local it = ItemDB.RequireItem(id)
  return it.equip ~= nil
end
function ItemDB.All(): { [string]: Item }
  return Items
end
ItemDB.GetAll = ItemDB.All
function ItemDB.RarityOf(id: string): string?
  local it = Items[id]
  return it and it.rarity or nil
end
function ItemDB.IsHotbarBindable(id: string): boolean
  local it = Items[id]
  return it ~= nil
    and (
      (it.bindable == true)
      or ((it :: any).canBind == true)
      or (it.hotbar == true)
      or (it.equip and it.equip.slot == 'hand')
    )
end
function ItemDB.IsBindable(id: string): boolean
  return ItemDB.IsHotbarBindable(id)
end

-- rich debug: search RS/Models/* and SS/Weapons/*
function ItemDB.BindabilityReport(id: string)
  local it = Items[id]
  if not it then
    return nil
  end
  local function findCI(container: Instance?, name: string): Instance?
    if not container then
      return nil
    end
    local target = string.lower(name)
    for _, d in ipairs(container:GetDescendants()) do
      if string.lower(d.Name) == target then
        return d
      end
    end
    return nil
  end
  local RS = game:GetService 'ReplicatedStorage'
  local SS = game:GetService 'ServerStorage'
  local models = RS:FindFirstChild 'Models'
  local found = (
    models
    and (
      models:FindFirstChild(id)
      or findCI(models, id)
      or (models:FindFirstChild 'Weapons' and (models.Weapons:FindFirstChild(id) or findCI(
        models.Weapons,
        id
      )))
      or (
        models:FindFirstChild 'Items'
        and (models.Items:FindFirstChild(id) or findCI(models.Items, id))
      )
    )
  )
    or (SS:FindFirstChild 'Weapons' and (SS.Weapons:FindFirstChild(id) or findCI(SS.Weapons, id)))
    or SS:FindFirstChild(id)
    or findCI(SS, id)

  return {
    id = id,
    displayName = it.displayName,
    type = it.type,
    hotbar = it.hotbar,
    bindable = it.bindable,
    canBind = (it :: any).canBind,
    equipSlot = it.equipSlot or (it.equip and it.equip.slot),
    twoHanded = it.twoHanded or (it.equip and it.equip.twoHanded),
    hasModel = (found ~= nil),
  }
end

ItemDB.__build = 'durability-v1'
return ItemDB -- <<< EXACTLY ONE VALUE

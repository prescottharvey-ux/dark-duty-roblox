--!strict
-- ReplicatedStorage/Modules/Loot.lua
-- Centralized, ItemDB-backed loot helpers.
local RS = game:GetService 'ReplicatedStorage'
local Require = require(RS:WaitForChild('Modules'):WaitForChild 'Require')

-- Config lives under Modules in your game. Fall back gracefully if absent.
local okCfg, Config = pcall(function()
  return Require.Module 'Config'
end)
if not okCfg then
  warn '[Loot] Config module not found under Modules; using lightweight defaults.'
  Config = nil
end

-- ItemDB is required for validation and (optionally) rarity/weight
local okDB, ItemDB = pcall(function()
  return Require.Module 'ItemDB'
end)
if not okDB or type(ItemDB) ~= 'table' then
  error '[Loot] ItemDB module is missing or invalid (ReplicatedStorage/Modules/ItemDB)'
end

local Loot = {}

-- ---------- ItemDB helpers ----------
local function db_get(id: string): any
  if type(ItemDB.GetItem) == 'function' then
    local ok, v = pcall(ItemDB.GetItem, id)
    if ok then
      return v
    end
  elseif type((ItemDB :: any).GetItem) == 'userdata' then
    local ok, v = pcall(function()
      return (ItemDB :: any):GetItem(id)
    end)
    if ok then
      return v
    end
  end
  return (ItemDB :: any)[id]
end

local function valid(id: string): boolean
  if type(id) ~= 'string' or id == '' then
    return false
  end
  return type(db_get(id)) == 'table'
end

local function rarityOf(id: string): string?
  local def = db_get(id)
  if type(def) == 'table' then
    local r = def.Rarity or def.rarity
    if type(r) == 'string' then
      return r
    end
  end
  return nil
end

-- ---------- Pool building ----------
local function raritySetFor(zoneKey: string): { [string]: boolean }
  local out: { [string]: boolean } = {}
  if Config and Config.Loot and (Config.Loot :: any)[zoneKey] then
    local add = (Config.Loot :: any)[zoneKey].AddRarities
    if type(add) == 'table' then
      for _, r in ipairs(add) do
        out[r] = true
      end
    end
  end
  return out
end

local function derivePoolFromItemDB(rset: { [string]: boolean }): { string }
  local ids: { string } = {}

  local function maybePush(id: string, def: any)
    if type(def) ~= 'table' then
      return
    end
    if next(rset) == nil then
      if valid(id) then
        table.insert(ids, id)
      end
    else
      local r = def.Rarity or def.rarity
      if type(r) == 'string' and rset[r] and valid(id) then
        table.insert(ids, id)
      end
    end
  end

  -- Prefer ItemDB.GetAll()
  if type(ItemDB.GetAll) == 'function' then
    local ok, all = pcall(ItemDB.GetAll)
    if ok and type(all) == 'table' then
      for id, def in pairs(all) do
        maybePush(id, def)
      end
      return ids
    end
  end

  -- Fallbacks
  if type((ItemDB :: any).All) == 'table' then
    for id, def in pairs((ItemDB :: any).All) do
      maybePush(id, def)
    end
    return ids
  end

  for id, def in pairs(ItemDB) do
    maybePush(tostring(id), def)
  end
  return ids
end

local function sanitizePool(zoneKey: string): { string }
  -- First, honor Config.Loot.GearPools if present
  if Config and Config.Loot and type(Config.Loot.GearPools) == 'table' then
    local src = (Config.Loot.GearPools :: any)[zoneKey]
    if type(src) == 'table' then
      local out: { string } = {}
      for _, id in ipairs(src) do
        if valid(id) then
          table.insert(out, id)
        else
          warn(
            ('[Loot] Dropping unknown id from Config.Loot.GearPools.%s: %s'):format(
              zoneKey,
              tostring(id)
            )
          )
        end
      end
      if #out > 0 then
        return out
      end
    end
  end

  -- Else, derive from ItemDB + zone rarities (if any)
  local rset = raritySetFor(zoneKey)
  local derived = derivePoolFromItemDB(rset)
  if #derived == 0 then
    warn(('[Loot] Empty pool for %s; check Config.Loot or ItemDB rarities.'):format(zoneKey))
  end
  return derived
end

local function pick(pool: { string }, n: number): { string }
  if n <= 0 or #pool == 0 then
    return {}
  end
  local bag = table.clone(pool)
  local out: { string } = {}
  for _ = 1, math.min(n, #bag) do
    local idx = math.random(1, #bag)
    table.insert(out, bag[idx])
    table.remove(bag, idx)
  end
  return out
end

-- ---------- Public API ----------
function Loot.GearPool(zoneKey: string): { string }
  return sanitizePool(zoneKey)
end

function Loot.RollGear(zoneKey: string, count: number): { string }
  return pick(sanitizePool(zoneKey), count)
end

function Loot.Validate(id: string): string?
  return valid(id) and id or nil
end

return Loot

-- ServerScriptService/Inventory/Public.lua
--!strict
-- Singleton inventory + stash + equipment + hotbar (4 slots)

local RS = game:GetService 'ReplicatedStorage'
local Players = game:GetService 'Players'

-- ==== ItemDB (safe require so this module always returns exactly one value) ====
local ItemDB: any
do
  local ok, mod = pcall(function()
    return require(RS:WaitForChild('Modules'):WaitForChild 'ItemDB')
  end)
  if ok and typeof(mod) == 'table' then
    ItemDB = mod
  else
    warn('[Inventory/Public] ItemDB require failed; using stub. Error:', mod)
    ItemDB = {
      GetItem = function(_id: string)
        return nil
      end,
      WeightOf = function(_id: string)
        return 0
      end,
      IsHotbarBindable = function(_id: string)
        return true
      end,
    }
  end
end

export type ItemMap = { [string]: number }
export type EquipSlots = {
  head: string?,
  torso: string?,
  hands: string?,
  legs: string?,
  feet: string?,
  trinket1: string?,
  trinket2: string?,
  handL: string?,
  handR: string?,
}
export type Hotbar = { [number]: string? } -- 1..4 → item id

local M = {}

-- ===== private state =====
local _carried: { [number]: ItemMap } = {}
local _stash: { [number]: ItemMap } = {}
local _equip: { [number]: EquipSlots } = {}
local _hotbar: { [number]: Hotbar } = {}

local function ensure_map(mapTable: { [number]: ItemMap }, uid: number): ItemMap
  local t = mapTable[uid]
  if not t then
    t = {}
    mapTable[uid] = t
  end
  return t
end
local function ensure_equip(uid: number): EquipSlots
  local t = _equip[uid]
  if not t then
    t = {
      head = nil,
      torso = nil,
      hands = nil,
      legs = nil,
      feet = nil,
      trinket1 = nil,
      trinket2 = nil,
      handL = nil,
      handR = nil,
    }
    _equip[uid] = t
  end
  return t
end
local function ensure_hotbar(uid: number): Hotbar
  local t = _hotbar[uid]
  if not t then
    t = { [1] = nil, [2] = nil, [3] = nil, [4] = nil }
    _hotbar[uid] = t
  end
  return t
end

Players.PlayerRemoving:Connect(function(p)
  _carried[p.UserId], _stash[p.UserId], _equip[p.UserId], _hotbar[p.UserId] = nil, nil, nil, nil
end)

-- ========== carried / stash ==========
function M.addItem(plr: Player, id: string, qty: number)
  if not (plr and type(id) == 'string' and type(qty) == 'number' and qty > 0) then
    return
  end
  local bag = ensure_map(_carried, plr.UserId)
  bag[id] = (bag[id] or 0) + qty
end

function M.addCarried(plr: Player, id: string, qty: number)
  M.addItem(plr, id, qty)
end

function M.removeCarried(plr: Player, id: string, qty: number): boolean
  if not (plr and type(id) == 'string' and type(qty) == 'number' and qty > 0) then
    return false
  end
  local bag = ensure_map(_carried, plr.UserId) -- (fixed: was ensure(...) typo)
  local have = bag[id] or 0
  if have < qty then
    return false
  end
  local left = have - qty
  bag[id] = (left > 0) and left or nil
  return true
end

function M.getCarried(plr: Player): ItemMap
  if not plr then
    return {}
  end
  local bag = _carried[plr.UserId] or {}
  local out: ItemMap = {}
  for id, qty in pairs(bag) do
    out[id] = qty
  end
  return out
end

function M.getCarriedList(plr: Player): { { id: string, qty: number } }
  if not plr then
    return {}
  end
  local bag = _carried[plr.UserId] or {}
  local out = {}
  for id, qty in pairs(bag) do
    if qty and qty > 0 then
      table.insert(out, { id = id, qty = qty })
    end
  end
  table.sort(out, function(a, b)
    return a.id < b.id
  end)
  return out
end

function M.getStashMap(plr: Player): ItemMap
  if not plr then
    return {}
  end
  return _stash[plr.UserId] or {}
end

function M.getStashList(plr: Player): { { id: string, qty: number } }
  if not plr then
    return {}
  end
  local s = _stash[plr.UserId] or {}
  local list = {}
  for id, qty in pairs(s) do
    table.insert(list, { id = id, qty = qty })
  end
  table.sort(list, function(a, b)
    return a.id < b.id
  end)
  return list
end

-- withdraw stash → carried
function M.withdraw(plr: Player, id: string, qty: number)
  if not (plr and type(id) == 'string' and type(qty) == 'number' and qty > 0) then
    return false
  end
  local uid = plr.UserId
  local s = ensure_map(_stash, uid)
  local have = s[id] or 0
  if have <= 0 then
    return false
  end
  local take = math.min(have, qty)
  local left = have - take
  s[id] = (left > 0) and left or nil
  local bag = ensure_map(_carried, uid)
  bag[id] = (bag[id] or 0) + take
  return true
end

-- extraction: carried → stash (all)
function M.onExtract(plr: Player)
  if not plr then
    return
  end
  local uid = plr.UserId
  local carried = ensure_map(_carried, uid)
  local stash = ensure_map(_stash, uid)
  local moved = false
  for id, qty in pairs(carried) do
    if qty and qty > 0 then
      stash[id] = (stash[id] or 0) + qty
      carried[id] = nil
      moved = true
    end
  end
  -- notify clients
  local Remotes = RS:FindFirstChild 'Remotes'
  if Remotes then
    local REF = Remotes:FindFirstChild 'RemoteEvent'
    local Notice = REF and REF:FindFirstChild 'InventoryNotice'
    if Notice and Notice:IsA 'RemoteEvent' then
      Notice:FireClient(plr, 'stash_refresh', M.getStashList(plr))
      if moved then
        Notice:FireClient(plr, 'notice', 'Extracted loot sent to stash')
      end
    end
  end
end

-- total weight of carried
function M.getWeight(plr: Player): number
  if not plr then
    return 0
  end
  local bag = _carried[plr.UserId]
  if not bag then
    return 0
  end
  local w = 0
  for id, qty in pairs(bag) do
    local wt = 0
    if typeof(ItemDB.WeightOf) == 'function' then
      wt = ItemDB.WeightOf(id) or 0
    else
      local def = (typeof(ItemDB.GetItem) == 'function') and ItemDB.GetItem(id) or ItemDB[id]
      wt = (def and def.weight) or 0
    end
    w += wt * (qty or 0)
  end
  return w
end

-- ========== equipment / hotbar ==========
local EQUIP_SLOTS = {
  head = true,
  torso = true,
  hands = true,
  legs = true,
  feet = true,
  trinket1 = true,
  trinket2 = true,
  handL = true,
  handR = true,
}

local function defFor(id: string): any
  if typeof(ItemDB.GetItem) == 'function' then
    return ItemDB.GetItem(id)
  end
  return ItemDB[id]
end

local function isTwoHanded(id: string): boolean
  local d = defFor(id)
  return (d and d.equip and d.equip.slot == 'hand' and d.equip.twoHanded == true) or false
end

local function canEquipToSlot(id: string, slot: string): boolean
  local d = defFor(id)
  if not d or not d.equip then
    return false
  end
  local s = d.equip.slot
  if slot == 'handL' or slot == 'handR' then
    return s == 'hand'
  end
  if slot == 'trinket1' or slot == 'trinket2' then
    return s == 'trinket'
  end
  return s == slot
end

function M.getEquipment(plr: Player): EquipSlots
  return ensure_equip(plr.UserId)
end

function M.getHotbar(plr: Player): Hotbar
  return ensure_hotbar(plr.UserId)
end

-- Equip one unit of id into a slot; adjusts carried; enforces 2H rules
function M.equip(plr: Player, id: string, slot: string): (boolean, string?)
  if not (plr and type(id) == 'string' and EQUIP_SLOTS[slot]) then
    return false, 'bad_args'
  end
  local d = defFor(id)
  if not d or not d.equip then
    return false, 'not_equipable'
  end
  if not canEquipToSlot(id, slot) then
    return false, 'wrong_slot'
  end

  local uid = plr.UserId
  local eq = ensure_equip(uid)

  if slot == 'handL' or slot == 'handR' then
    if isTwoHanded(id) then
      if eq.handL or eq.handR then
        return false, 'hands_full'
      end
      if not M.removeCarried(plr, id, 1) then
        return false, 'not_in_carried'
      end
      eq.handL, eq.handR = id, id
      return true
    else
      if eq[slot] ~= nil then
        return false, 'slot_full'
      end
      -- block offhand equip if other hand holds a 2H
      local other = (slot == 'handL') and eq.handR or eq.handL
      if other and isTwoHanded(other) then
        return false, 'two_handed_conflict'
      end
      if not M.removeCarried(plr, id, 1) then
        return false, 'not_in_carried'
      end
      eq[slot] = id
      return true
    end
  end

  -- armor / trinkets
  if eq[slot] ~= nil then
    return false, 'slot_full'
  end
  if not M.removeCarried(plr, id, 1) then
    return false, 'not_in_carried'
  end
  eq[slot] = id
  return true
end

-- Unequip a slot → carried (handles 2H collapse to 1 item)
function M.unequip(plr: Player, slot: string): (boolean, string?)
  if not (plr and EQUIP_SLOTS[slot]) then
    return false, 'bad_args'
  end
  local eq = ensure_equip(plr.UserId)
  local id = eq[slot]
  if not id then
    return false, 'empty'
  end

  if slot == 'handL' or slot == 'handR' then
    local otherSlot = (slot == 'handL') and 'handR' or 'handL'
    local otherId = eq[otherSlot]
    -- If both are same 2H, clear both and return a single item
    if otherId and otherId == id and isTwoHanded(id) then
      eq.handL, eq.handR = nil, nil
      M.addItem(plr, id, 1)
      return true
    end
  end

  eq[slot] = nil
  M.addItem(plr, id, 1)
  return true
end

-- Hotbar mapping (binding only)
function M.setHotbar(plr: Player, index: number, id: string?): (boolean, string?)
  if not (plr and type(index) == 'number' and index >= 1 and index <= 4) then
    return false, 'bad_args'
  end
  if id ~= nil then
    -- Prefer ItemDB’s predicate if present
    local bindable: boolean? = nil
    if typeof(ItemDB.IsHotbarBindable) == 'function' then
      local ok, res = pcall(ItemDB.IsHotbarBindable, id)
      if ok then
        bindable = (res == true)
      end
    end
    if bindable == nil then
      local d = defFor(id)
      bindable = (d and (d.hotbar == true or (d.equip and d.equip.slot == 'hand'))) or false
    end
    if not bindable then
      return false, 'not_hotbarable'
    end
  end
  local hb = ensure_hotbar(plr.UserId)
  hb[index] = id
  return true
end

-- ===== compatibility aliases expected by other scripts / healthcheck =====
function M.GetCarried(plr: Player)
  return M.getCarried(plr)
end
function M.Give(plr: Player, id: string, n: number?)
  M.addItem(plr, id, n or 1)
end
function M.MoveToStash(plr: Player, id: string, n: number?)
  if not (plr and type(id) == 'string') then
    return false
  end
  local qty = n or 1
  if not M.removeCarried(plr, id, qty) then
    return false
  end
  local s = ensure_map(_stash, plr.UserId)
  s[id] = (s[id] or 0) + qty
  return true
end

return M

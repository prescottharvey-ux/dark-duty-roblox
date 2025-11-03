--!strict
-- Best-effort normalizer: if a weapon/spellbook ends up in left hand, move it to right; shields/items to left.
local RS = game:GetService 'ReplicatedStorage'
local SSS = game:GetService 'ServerScriptService'

local BusOk, Bus = pcall(function()
  return require(RS.Events.EventBus)
end)
local InvOk, Inventory = pcall(function()
  return require(SSS.Inventory.Public)
end)
if not (BusOk and InvOk and Inventory) then
  return
end

-- Helper: classify item
local function classify(item: any): 'weapon' | 'spellbook' | 'shield' | 'item' | 'other'
  if not item then
    return 'other'
  end
  local t = (item.type or item.Type or ''):lower()
  local tags = item.tags or item.Tags or {}
  local function has(tag: string): boolean
    for _, v in ipairs(tags) do
      if tostring(v):lower() == tag then
        return true
      end
    end
    return false
  end
  if t == 'shield' or has 'shield' then
    return 'shield'
  end
  if t == 'spellbook' or has 'spellbook' then
    return 'spellbook'
  end
  if t == 'weapon' or has 'weapon' or t == 'dagger' or t == 'sword' or t == 'staff' then
    return 'weapon'
  end
  if t == 'item' or has 'item' then
    return 'item'
  end
  return 'other'
end

-- Try to read equipped; expected shapes: {handL=item, handR=item} or list with .slot/.hand
local function getEquipped(plr: Player)
  local ok, eq = pcall(Inventory.GetEquipped, plr)
  return (ok and type(eq) == 'table') and eq or nil
end

local function moveTo(plr: Player, slot: string, item: any)
  if typeof((Inventory :: any).EquipToSlot) == 'function' then
    pcall((Inventory :: any).EquipToSlot, plr, slot, item)
  elseif typeof((Inventory :: any).Equip) == 'function' then
    pcall((Inventory :: any).Equip, plr, slot, item)
  end
end

local function normalize(plr: Player)
  local eq = getEquipped(plr)
  if not eq then
    return
  end
  -- Case A: table with keys handL/handR
  if eq.handL or eq.handR then
    if eq.handL then
      local c = classify(eq.handL)
      if c == 'weapon' or c == 'spellbook' then
        moveTo(plr, 'handR', eq.handL)
        eq.handL = nil
      end
    end
    if eq.handR then
      local c = classify(eq.handR)
      if c == 'shield' or c == 'item' then
        moveTo(plr, 'handL', eq.handR)
        eq.handR = nil
      end
    end
    return
  end
  -- Case B: list of items with .slot or .hand
  for _, it in ipairs(eq) do
    local slot = (it.slot or it.hand or ''):lower()
    local c = classify(it)
    if (c == 'weapon' or c == 'spellbook') and slot:find 'handl' then
      moveTo(plr, 'handR', it)
    end
    if (c == 'shield' or c == 'item') and slot:find 'handr' then
      moveTo(plr, 'handL', it)
    end
  end
end

-- Listen to equip changes; try a few topic names to match your EventBus
local topics = {
  'Inventory:EquipChanged',
  'inventory.equip_changed',
  'inventory.equipped',
  'EquipChanged',
  'equip.changed',
}
for _, t in ipairs(topics) do
  local f = (Bus :: any).On
    or (Bus :: any).Subscribe
    or (Bus :: any).Connect
    or (Bus :: any).subscribe
  if typeof(f) == 'function' then
    f(t, function(payload)
      local plr = payload and (payload.player or payload.Player)
      if plr and typeof(plr) == 'Instance' then
        normalize(plr)
      end
    end)
  end
end

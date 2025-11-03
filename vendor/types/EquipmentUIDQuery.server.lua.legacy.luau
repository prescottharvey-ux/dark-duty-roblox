--!strict
-- ServerScriptService/Inventory/EquipmentUIDQuery.server.lua
-- Returns a normalized snapshot that includes hotbar items with UIDs.

local RS = game:GetService 'ReplicatedStorage'
local SSS = game:GetService 'ServerScriptService'

local Remotes = RS:FindFirstChild 'Remotes' or Instance.new('Folder', RS)
Remotes.Name = 'Remotes'
local RFF = Remotes:FindFirstChild 'RemoteFunction' or Instance.new('Folder', Remotes)
RFF.Name = 'RemoteFunction'
local RF = RFF:FindFirstChild 'EquipmentUIDQuery' or Instance.new('RemoteFunction', RFF)
RF.Name = 'EquipmentUIDQuery'

local InventoryPublic: any = require(SSS:WaitForChild('Inventory'):WaitForChild 'Public')

local function safe(fn, ...)
  if type(fn) ~= 'function' then
    return nil
  end
  local ok, res = pcall(fn, ...)
  return ok and res or nil
end

RF.OnServerInvoke = function(plr: Player)
  -- 1) get hotbar (accept several shapes)
  local rawHotbar: any = safe(InventoryPublic.getHotbar, InventoryPublic, plr)
    or safe(InventoryPublic.GetHotbar, InventoryPublic, plr)
    or safe(InventoryPublic.hotbarOf, InventoryPublic, plr)
    or {}

  -- normalize to { [1]=idOrCell, ... }
  local hb: { [number]: any } = {}
  for i = 1, 4 do
    hb[i] = rawHotbar[i]
      or rawHotbar[tostring(i)]
      or rawHotbar['hotbar' .. i]
      or rawHotbar['slot' .. i]
  end

  -- 2) get all items so we can map id -> uid
  local items = safe(InventoryPublic.ListAllItems, InventoryPublic, plr) or {}
  local byId: { [string]: { string } } = {}
  for _, inst in ipairs(items) do
    local id = tostring(inst.id)
    byId[id] = byId[id] or {}
    table.insert(byId[id], tostring(inst.uid))
  end

  -- 3) build {id, uid} cells (best-effort choose the first uid for each id)
  for i = 1, 4 do
    local cell = hb[i]
    if cell ~= nil then
      local id = (type(cell) == 'table' and cell.id) or (type(cell) == 'string' and cell) or nil
      if id then
        local uidList = byId[id]
        local uid = uidList and uidList[1] or nil
        hb[i] = uid and { id = id, uid = uid } or id
      end
    end
  end

  -- also return equipment if available (optional)
  local equip = safe(InventoryPublic.getEquipment, InventoryPublic, plr)
    or safe(InventoryPublic.GetEquipment, InventoryPublic, plr)
    or {}

  return { hotbar = hb, equipment = equip }
end

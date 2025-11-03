--!strict
-- InventoryService.server.lua
-- Stash/Carried + Withdraw + CarryWeight/MaxCarry sync
-- Equipment + 4-slot Hotbar + handL/handR (+2H) + server-side hand visuals (FPV-safe)
-- UID-aware snapshots for durability bars.
-- Back-compat: EquipChanged.hotbar remains strings; UIDs exposed in a side field.
-- Equipped items are filtered OUT of carried. All equip/unequip paths push both snapshots.

local RS = game:GetService 'ReplicatedStorage'
local Players = game:GetService 'Players'
local RunService = game:GetService 'RunService'
local SSS = game:GetService 'ServerScriptService'
local ServerStorage = game:GetService 'ServerStorage'
local Workspace = game:GetService 'Workspace'
local HttpService = game:GetService 'HttpService'

local STR = string

local Inventory = require(SSS:WaitForChild('Inventory'):WaitForChild 'Public')

-- ========= Options =========
local DEBUG_HANDS = true
local PARENT_VISUALS_IN_WORKSPACE = true
local AUTO_EQUIP_ON_FIRST_BIND = false

local function dbg(...)
  if DEBUG_HANDS then
    print('[HandsDBG]', ...)
  end
end
local function log(...)
  print('[Equip]', ...)
end

-- ========= UID per hotbar slot =========
local uidByHotbar: { [Player]: { [number]: string } } = {}
local function ensureSlotUid(plr: Player, idx: number): string
  uidByHotbar[plr] = uidByHotbar[plr] or {}
  local u = uidByHotbar[plr][idx]
  if not u then
    u = HttpService:GenerateGUID(false)
    uidByHotbar[plr][idx] = u
  end
  return u
end

-- ========= Remotes (create once) =========
local Remotes = RS:FindFirstChild 'Remotes' or Instance.new 'Folder'
Remotes.Name = 'Remotes'
Remotes.Parent = RS
local REF = Remotes:FindFirstChild 'RemoteEvent' or Instance.new 'Folder'
REF.Name = 'RemoteEvent'
REF.Parent = Remotes
local RFF = Remotes:FindFirstChild 'RemoteFunction' or Instance.new 'Folder'
RFF.Name = 'RemoteFunction'
RFF.Parent = Remotes

local function ensureEvent(n: string): RemoteEvent
  return (REF:FindFirstChild(n) :: any)
    or (function()
      local e = Instance.new 'RemoteEvent'
      e.Name = n
      e.Parent = REF
      return e
    end)()
end
local function ensureFunc(n: string): RemoteFunction
  return (RFF:FindFirstChild(n) :: any)
    or (function()
      local f = Instance.new 'RemoteFunction'
      f.Name = n
      f.Parent = RFF
      return f
    end)()
end

-- Primary remotes
local InventoryNotice = ensureEvent 'InventoryNotice'
local StashWithdraw = ensureEvent 'StashWithdraw'
local WeightUpdate = ensureEvent 'WeightUpdate'
local HotbarUse = ensureEvent 'HotbarUse'
local EquipChanged = ensureEvent 'EquipChanged'

local StashQuery = ensureFunc 'StashQuery'
local CarriedQuery = ensureFunc 'CarriedQuery'
local EquipmentQuery = ensureFunc 'EquipmentQuery'
local EquipRequest = ensureFunc 'EquipRequest'
local UnequipRequest = ensureFunc 'UnequipRequest'
local HotbarSet = ensureFunc 'HotbarSet'
local EquipmentUIDQuery = ensureFunc 'EquipmentUIDQuery'

-- Back-compat: many UIs expect a single RF snapshot (nested under Remotes/RemoteFunction)
local InventorySnapshot = ensureFunc 'InventorySnapshot'

-- ========= ItemDB helpers =========
local ItemDB: any = (function()
  local ok, mod = pcall(function()
    return require(RS:WaitForChild('Modules'):WaitForChild 'ItemDB')
  end)
  return ok and mod or {}
end)()

local function itemDef(id: string?): any
  if not id then
    return nil
  end
  if typeof(ItemDB.GetItem) == 'function' then
    return ItemDB.GetItem(id)
  end
  return ItemDB[id]
end

local function equipSlotFor(def: any): string?
  if not def then
    return nil
  end
  local slot = (def.equip and def.equip.slot) or def.equipSlot or def.slot
  return (type(slot) == 'string') and STR.lower(slot) or nil
end

local function isHandItem(id: string): boolean
  return equipSlotFor(itemDef(id)) == 'hand'
end

local function isTwoHanded(id: string): boolean
  local d = itemDef(id)
  if not d then
    return false
  end
  if d.twoHanded ~= nil then
    return d.twoHanded == true
  end
  return d.equip ~= nil and d.equip.twoHanded == true
end

-- ========= Encumbrance =========
local DEFAULT_MAX_CARRY = 40
do
  local ok, cfg = pcall(function()
    return require(RS:WaitForChild('Config'):WaitForChild 'StaminaConfig')
  end)
  if ok and type(cfg) == 'table' then
    local enc = cfg.Encumbrance
    if type(enc) == 'table' and type(enc.MaxCarry) == 'number' then
      DEFAULT_MAX_CARRY = enc.MaxCarry
    end
  end
end

local function getWeightForId(id: string): number
  local rec = itemDef(id)
  return (rec and typeof(rec.weight) == 'number') and rec.weight or 0
end

local function computeCarriedWeight(plr: Player): number
  local list = Inventory.getCarriedList(plr)
  if type(list) ~= 'table' then
    return 0
  end
  local total = 0
  for _, entry in ipairs(list) do
    if typeof(entry) == 'string' then
      total += getWeightForId(entry)
    elseif type(entry) == 'table' then
      local id = entry.id :: any
      local qty = entry.qty :: any
      if type(id) ~= 'string' then
        for k, v in pairs(entry) do
          if type(k) == 'string' then
            id = k
            if type(v) == 'number' then
              qty = v
            end
            break
          end
        end
      end
      if type(id) == 'string' then
        total += getWeightForId(id) * math.max(0, (typeof(qty) == 'number' and qty or 1))
      end
    end
  end
  return total
end

local function resolveMaxCarry(plr: Player): number
  local attr = plr:GetAttribute 'MaxCarry'
  return (type(attr) == 'number' and attr > 0) and attr or DEFAULT_MAX_CARRY
end

local function setAttr(p: Player, name: string, value: any)
  if p:GetAttribute(name) ~= value then
    p:SetAttribute(name, value)
  end
end

local function reconcileCarryAttrs(plr: Player, _reason: string?)
  local weight = computeCarriedWeight(plr)
  local maxCar = resolveMaxCarry(plr)
  setAttr(plr, 'CarryWeight', weight)
  setAttr(plr, 'MaxCarry', maxCar)
  WeightUpdate:FireClient(plr, weight, maxCar)
end

-- ========= Equipment/Hotbar state =========
type EquipmentTable = {
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
type EquipState = { equipment: EquipmentTable, hotbar: { [number]: string? } }

local stateFor: { [Player]: EquipState } = {}
local function emptyState(): EquipState
  return {
    equipment = {
      head = nil,
      torso = nil,
      hands = nil,
      legs = nil,
      feet = nil,
      trinket1 = nil,
      trinket2 = nil,
      handL = nil,
      handR = nil,
    },
    hotbar = { [1] = nil, [2] = nil, [3] = nil, [4] = nil },
  }
end

local validArmorSlots = {
  head = true,
  torso = true,
  hands = true,
  legs = true,
  feet = true,
  trinket1 = true,
  trinket2 = true,
}

-- ========= Slot fit check =========
local function itemFitsArmorSlot(id: string, slot: string): boolean
  local def = itemDef(id)
  if not def or not def.equip then
    return false
  end
  if slot == 'trinket1' or slot == 'trinket2' then
    return equipSlotFor(def) == 'trinket'
  end
  return equipSlotFor(def) == slot
end

-- ========= Carried minus equipped (visual-only hiding) =========
local function equippedCountsOf(S: EquipState): { [string]: number }
  local c: { [string]: number } = {}
  local function add(id: string?)
    if id then
      c[id] = (c[id] or 0) + 1
    end
  end
  add(S.equipment.head)
  add(S.equipment.torso)
  add(S.equipment.hands)
  add(S.equipment.legs)
  add(S.equipment.feet)
  add(S.equipment.trinket1)
  add(S.equipment.trinket2)
  local L, R = S.equipment.handL, S.equipment.handR
  if L and R and L == R and isTwoHanded(L) then
    add(L)
  else
    add(L)
    add(R)
  end
  return c
end

local function copyPreservingShape(entry: any, id: string, newQty: number)
  if typeof(entry) == 'string' then
    return (newQty >= 1) and id or nil
  end
  if type(entry) == 'table' then
    if entry.id ~= nil or entry.qty ~= nil or entry.uid ~= nil then
      if newQty <= 0 then
        return nil
      end
      local t = table.clone(entry)
      if t.qty ~= nil then
        t.qty = newQty
      end
      return t
    end
    if newQty <= 0 then
      return nil
    end
    local t = {}
    for k, v in pairs(entry) do
      t[k] = v
    end
    t[id] = newQty
    return t
  end
  return nil
end

local function carriedMinusEquipped(plr: Player): { any }
  local S = stateFor[plr] or emptyState()
  local list = Inventory.getCarriedList(plr)
  if type(list) ~= 'table' then
    return {}
  end
  local need = equippedCountsOf(S)
  local out: { any } = {}

  for _, entry in ipairs(list) do
    local id: string? = nil
    local qty: number = 1
    if typeof(entry) == 'string' then
      id, qty = entry, 1
    elseif type(entry) == 'table' then
      if type(entry.id) == 'string' then
        id = entry.id
        qty = (type(entry.qty) == 'number') and entry.qty or 1
      else
        for k, v in pairs(entry) do
          if type(k) == 'string' then
            id = k
            if type(v) == 'number' then
              qty = v
            end
            break
          end
        end
      end
    end
    if id then
      local use = math.min(qty, need[id] or 0)
      local keepQty = qty - use
      if keepQty > 0 then
        local kept = copyPreservingShape(entry, id, keepQty)
        if kept then
          table.insert(out, kept)
        end
      end
      if use > 0 then
        need[id] = (need[id] or 0) - use
      end
    else
      table.insert(out, entry)
    end
  end
  return out
end

-- ========= Carried fingerprint & pushing =========
local carriedHash: { [Player]: string } = {}

local function carriedFingerprint(list: any): string
  if type(list) ~= 'table' then
    return 'nil'
  end
  local counts: { [string]: number } = {}
  for _, entry in ipairs(list) do
    if typeof(entry) == 'string' then
      counts[entry] = (counts[entry] or 0) + 1
    elseif type(entry) == 'table' then
      local id = entry.id :: any
      local qty = entry.qty :: any
      if type(id) ~= 'string' then
        for k, v in pairs(entry) do
          if type(k) == 'string' then
            id = k
            if type(v) == 'number' then
              qty = v
            end
            break
          end
        end
      end
      if type(id) == 'string' then
        counts[id] = (counts[id] or 0) + (type(qty) == 'number' and qty or 1)
      end
    end
  end
  local keys = {}
  for k, _ in pairs(counts) do
    table.insert(keys, k)
  end
  table.sort(keys)
  local parts = {}
  for _, k in ipairs(keys) do
    table.insert(parts, k .. ':' .. tostring(counts[k]))
  end
  return table.concat(parts, '|')
end

local function uidFor(plr: Player, id: string): string?
  local list = (Inventory.getCarriedList and Inventory.getCarriedList(plr)) or {}
  for _, inst in ipairs(list) do
    if type(inst) == 'table' and inst.id == id and inst.uid then
      return inst.uid
    end
  end
  return nil
end

local function buildHotbarUIDs(plr: Player): { [number]: { id: string, uid: string } }
  stateFor[plr] = stateFor[plr] or emptyState()
  local S = stateFor[plr]
  local out: { [number]: { id: string, uid: string } } = {}
  for i = 1, 4 do
    local id = S.hotbar[i]
    if id then
      out[i] = { id = id, uid = uidFor(plr, id) or ensureSlotUid(plr, i) }
    end
  end
  return out
end

-- helper: convert carried list -> { id => qty } map
local function toIdQtyMap(list: { any }): { [string]: number }
  local m: { [string]: number } = {}
  for _, entry in ipairs(list) do
    if typeof(entry) == 'string' then
      m[entry] = (m[entry] or 0) + 1
    elseif type(entry) == 'table' then
      local id = entry.id
      local qty = entry.qty
      if type(id) ~= 'string' then
        for k, v in pairs(entry) do
          if type(k) == 'string' then
            id = k
            if type(v) == 'number' then
              qty = v
            end
            break
          end
        end
      end
      if type(id) == 'string' then
        m[id] = (m[id] or 0) + (typeof(qty) == 'number' and qty or 1)
      end
    end
  end
  return m
end

local function makeSnapshot(plr: Player)
  local S = stateFor[plr] or emptyState()
  local carriedFiltered = carriedMinusEquipped(plr)
  local hotUID = buildHotbarUIDs(plr)

  return {
    -- current shape
    carried = carriedFiltered,
    equipment = S.equipment,
    hotbar = S.hotbar,
    uids = { hotbar = hotUID },

    -- ***** legacy/compat keys some older UIs expect *****
    carriedList = carriedFiltered, -- alias of carried
    carriedMap = toIdQtyMap(carriedFiltered), -- id=>qty map
    hotbarUID = hotUID, -- alias of uids.hotbar
    equip = S.equipment, -- alias of equipment
  }
end

-- Wire InventorySnapshot AFTER makeSnapshot exists
InventorySnapshot.OnServerInvoke = function(plr: Player)
  return makeSnapshot(plr)
end
-- Flat alias so both Remotes.RemoteFunction.InventorySnapshot AND Remotes.InventorySnapshot work
do
  local flat = Remotes:FindFirstChild 'InventorySnapshot'
  if not flat then
    local alias = Instance.new 'RemoteFunction'
    alias.Name = 'InventorySnapshot'
    alias.Parent = Remotes
    alias.OnServerInvoke = function(plr)
      return makeSnapshot(plr)
    end
  end
end

local function pushInventorySnapshot(plr: Player)
  InventoryNotice:FireClient(plr, 'snapshot', makeSnapshot(plr))
end

local function pushEquipState(plr: Player)
  local S = stateFor[plr] or emptyState()
  EquipChanged:FireClient(plr, {
    equipment = S.equipment,
    hotbar = S.hotbar,
    carried = carriedMinusEquipped(plr),
    uids = { hotbar = buildHotbarUIDs(plr) },
  })
  -- Back-compat broadcast
  pushInventorySnapshot(plr)
end

local function pushCarried(plr: Player)
  local filtered = carriedMinusEquipped(plr)
  InventoryNotice:FireClient(plr, 'carried_refresh', filtered)
  carriedHash[plr] = carriedFingerprint(filtered)
  -- Back-compat broadcast
  pushInventorySnapshot(plr)
end

local function pushAll(plr: Player)
  pushEquipState(plr)
  pushCarried(plr)
end

-- ========= Hand visuals (server) =========
local function modelNameFor(id: string): string
  local d = itemDef(id)
  return (d and (d.name or d.displayName)) or id
end

local function findByNameCI(container: Instance?, n: string): Instance?
  if not container then
    return nil
  end
  local target = STR.lower(n)
  for _, d in ipairs(container:GetDescendants()) do
    if STR.lower(d.Name) == target then
      return d
    end
  end
  return nil
end

local function modelContainers(): { Instance }
  local list = {}
  local SS = ServerStorage
  local RS2 = RS
  local ssW = SS:FindFirstChild 'Weapons'
  local ssI = SS:FindFirstChild 'Items'
  if ssW then
    table.insert(list, ssW)
  end
  if ssI then
    table.insert(list, ssI)
  end
  table.insert(list, SS)
  local rsModels = RS2:FindFirstChild 'Models'
  if rsModels then
    local rsW = rsModels:FindFirstChild 'Weapons'
    local rsI = rsModels:FindFirstChild 'Items'
    if rsW then
      table.insert(list, rsW)
    end
    if rsI then
      table.insert(list, rsI)
    end
    table.insert(list, rsModels)
  end
  return list
end

local function findTemplateFor(id: string): Instance?
  local d = itemDef(id)
  local cand = {} :: { string }
  local function add(s: any)
    if type(s) == 'string' and s ~= '' then
      table.insert(cand, s)
    end
  end
  add(d and (d :: any).modelName)
  add(d and (d.displayName or d.name))
  add(id)
  for _, name in ipairs(cand) do
    for _, c in ipairs(modelContainers()) do
      local hit = c:FindFirstChild(name) or findByNameCI(c, name)
      if hit then
        dbg(('findTemplateFor(%s) -> %s (%s)'):format(id, hit.Name, hit:GetFullName()))
        return hit
      end
    end
  end
  warn(
    ("[InventoryService] findTemplateFor('%s'): candidates {%s} not found."):format(
      id,
      table.concat(cand, ', ')
    )
  )
  return nil
end

local function firstBasePart(inst: Instance): BasePart?
  if inst:IsA 'Model' then
    if inst.PrimaryPart and inst.PrimaryPart:IsA 'BasePart' then
      return inst.PrimaryPart
    end
    for _, d in ipairs(inst:GetDescendants()) do
      if d:IsA 'BasePart' then
        return d
      end
    end
  elseif inst:IsA 'Tool' then
    local h = inst:FindFirstChild 'Handle'
    if h and h:IsA 'BasePart' then
      return h
    end
  elseif inst:IsA 'BasePart' then
    return inst
  end
  return nil
end

local function findHandPart(char: Model, side: 'L' | 'R'): BasePart?
  local p = char:FindFirstChild(side == 'L' and 'LeftHand' or 'RightHand')
  if p and p:IsA 'BasePart' then
    return p
  end
  p = char:FindFirstChild(side == 'L' and 'Left Arm' or 'Right Arm')
  if p and p:IsA 'BasePart' then
    return p
  end
  return nil
end

local function weldAllPartsToRoot(container: Instance, root: BasePart)
  for _, d in ipairs(container:GetDescendants()) do
    if d:IsA 'BasePart' then
      d.CanCollide, d.CanTouch, d.CanQuery = false, false, false
      d.Anchored, d.Massless = false, true
      if d ~= root then
        local w = Instance.new 'WeldConstraint'
        w.Part0 = d
        w.Part1 = root
        w.Parent = d
      end
    end
  end
end

local heldVisuals: { [Player]: { L: Model?, R: Model? } } = {}

local function clearHandVisual(plr: Player, side: 'L' | 'R')
  local bag = heldVisuals[plr]
  if bag then
    local m = (side == 'L') and bag.L or bag.R
    if m then
      m:Destroy()
    end
    if side == 'L' then
      bag.L = nil
    else
      bag.R = nil
    end
  end
end

local function attachToHand(
  char: Model,
  side: 'L' | 'R',
  template: Instance,
  itemId: string
): Model?
  local hand = findHandPart(char, side)
  if not hand then
    return nil
  end

  local containerParent: Instance = PARENT_VISUALS_IN_WORKSPACE and Workspace or char
  local clone = template:Clone()
  local container: Model

  if clone:IsA 'Tool' then
    container = Instance.new 'Model'
    container.Name = (template.Name or 'Item') .. '_Vis'
    container.Parent = containerParent
    for _, d in ipairs(clone:GetDescendants()) do
      if d:IsA 'BasePart' then
        d.Parent = container
      end
    end
    clone:Destroy()
  else
    if clone:IsA 'Model' then
      clone.Name = (template.Name or clone.Name) .. '_Vis'
      container = clone
      container.Parent = containerParent
    else
      container = Instance.new 'Model'
      container.Name = (template.Name or 'Item') .. '_Vis'
      clone.Parent = container
      container.Parent = containerParent
    end
  end

  local root = firstBasePart(container)
  if not root then
    warn('[InventoryService] attachToHand: no BasePart in template for', template.Name)
    container:Destroy()
    return nil
  end

  for _, d in ipairs(container:GetDescendants()) do
    if d:IsA 'BasePart' then
      d.Transparency = 0
      d.CanCollide = false
      d.CanTouch = false
      d.CanQuery = false
      d.Anchored = false
      d.Massless = true
    end
  end
  weldAllPartsToRoot(container, root)

  local gripCF = CFrame.new(0, -0.5, -0.2)
    * CFrame.Angles(0, math.rad((side == 'L') and 90 or -90), 0)
  do
    local def = itemDef(itemId)
    if def and typeof(def.grip) == 'CFrame' then
      gripCF = def.grip
    end
  end

  local targetCF = hand.CFrame * gripCF
  if container.PrimaryPart then
    container:PivotTo(targetCF)
  else
    root.CFrame = targetCF
  end

  local weld = Instance.new 'WeldConstraint'
  weld.Part0 = root
  weld.Part1 = hand
  weld.Parent = root
  return container
end

local function updateHandVisuals(plr: Player)
  local S = stateFor[plr]
  if not S then
    return
  end
  local char = plr.Character
  if not char then
    return
  end
  heldVisuals[plr] = heldVisuals[plr] or { L = nil, R = nil }
  local bag = heldVisuals[plr]
  local wantL = S.equipment.handL
  local wantR = S.equipment.handR
  if wantL and wantR and wantL == wantR and isTwoHanded(wantL) then
    wantL = nil
  end

  -- LEFT
  if not wantL then
    clearHandVisual(plr, 'L')
  else
    local targetName = (modelNameFor(wantL) .. '_Vis')
    if (not bag.L) or (STR.lower(bag.L.Name) ~= STR.lower(targetName)) then
      clearHandVisual(plr, 'L')
      local src = findTemplateFor(wantL)
      if not src then
        warn('[InventoryService] No hand template found for', wantL)
      else
        bag.L = attachToHand(char, 'L', src, wantL)
      end
    end
  end
  -- RIGHT
  if not wantR then
    clearHandVisual(plr, 'R')
  else
    local targetName = (modelNameFor(wantR) .. '_Vis')
    if (not bag.R) or (STR.lower(bag.R.Name) ~= STR.lower(targetName)) then
      clearHandVisual(plr, 'R')
      local src = findTemplateFor(wantR)
      if not src then
        warn('[InventoryService] No hand template found for', wantR)
      else
        bag.R = attachToHand(char, 'R', src, wantR)
      end
    end
  end
end

-- ========= Equip/Unequip helpers =========
local function itemIsHandBindable(id: string): boolean
  if typeof(ItemDB.IsHotbarBindable) == 'function' then
    local ok, res = pcall(ItemDB.IsHotbarBindable, id)
    if ok and res ~= nil then
      return res == true
    end
  end
  if typeof(ItemDB.IsBindable) == 'function' then
    local ok, res = pcall(ItemDB.IsBindable, id)
    if ok and res ~= nil then
      return res == true
    end
  end
  local def = itemDef(id)
  if not def then
    return false
  end
  if def.bindable == true or def.hotbar == true or (def :: any).canBind == true then
    return true
  end
  return equipSlotFor(def) == 'hand'
end

local function clearTwoHandIfHeld(S: EquipState)
  local l, r = S.equipment.handL, S.equipment.handR
  if (l and isTwoHanded(l)) or (r and isTwoHanded(r)) then
    S.equipment.handL = nil
    S.equipment.handR = nil
    return true
  end
  return false
end

local function equipHand(plr: Player, id: string, which: 'handL' | 'handR'): (boolean, string?)
  local S = stateFor[plr]
  if not isHandItem(id) then
    return false, 'not_hand_item'
  end
  if isTwoHanded(id) then
    S.equipment.handL = id
    S.equipment.handR = id
  else
    clearTwoHandIfHeld(S)
    S.equipment[which] = id
  end
  log(plr.Name .. ' equipped ' .. id .. ' in ' .. which)
  return true
end

local function clearHands(S: EquipState)
  if S.equipment.handL or S.equipment.handR then
    S.equipment.handL = nil
    S.equipment.handR = nil
    return true
  end
  return false
end

local function dedupeHotbarId(S: EquipState, id: string, keepIdx: number?)
  for i = 1, 4 do
    if i ~= keepIdx and S.hotbar[i] == id then
      S.hotbar[i] = nil
    end
  end
end

local function bindToHotbar(S: EquipState, id: string, idx: number): (boolean, string?)
  if not itemIsHandBindable(id) then
    return false, 'not_bindable'
  end
  dedupeHotbarId(S, id, idx)
  if isTwoHanded(id) then
    if idx ~= 2 and idx ~= 3 then
      return false, '2H_requires_2_and_3'
    end
    S.hotbar[2], S.hotbar[3] = id, id
    if S.hotbar[1] == id then
      S.hotbar[1] = nil
    end
    if S.hotbar[4] == id then
      S.hotbar[4] = nil
    end
  else
    S.hotbar[idx] = id
    if idx == 2 and isTwoHanded(S.hotbar[3] or '') then
      S.hotbar[3] = nil
    end
    if idx == 3 and isTwoHanded(S.hotbar[2] or '') then
      S.hotbar[2] = nil
    end
  end
  return true
end

local function pushAndVisuals(plr: Player)
  pushAll(plr)
  updateHandVisuals(plr)
end

local function equipTarget(plr: Player, id: string, target: string): (boolean, string?)
  stateFor[plr] = stateFor[plr] or emptyState()
  local S = stateFor[plr]

  if type(target) ~= 'string' then
    return false, 'bad_target'
  end
  local t = STR.lower(target)

  -- hands
  if t == 'handl' or t == 'handr' then
    local ok, why = equipHand(plr, id, (t == 'handl') and 'handL' or 'handR')
    if ok then
      pushAndVisuals(plr)
    end
    return ok, why
  end

  -- armor / trinkets
  if validArmorSlots[t] then
    if not itemFitsArmorSlot(id, t) then
      return false, 'wrong_slot'
    end
    S.equipment[t] = id
    pushAndVisuals(plr)
    return true
  end

  -- hotbarX
  local num = STR.match(t, '^hotbar(%d+)$')
  local idx = num and tonumber(num) or nil
  if idx and idx >= 1 and idx <= 4 then
    local ok, why = bindToHotbar(S, id, idx)
    if ok then
      pushAll(plr)
      if AUTO_EQUIP_ON_FIRST_BIND and not S.equipment.handL and not S.equipment.handR then
        equipHand(plr, id, 'handR')
        pushAndVisuals(plr)
      end
    end
    return ok, why
  end

  return false, 'unknown_target'
end

local function unequipTarget(plr: Player, which: string): (boolean, string?)
  stateFor[plr] = stateFor[plr] or emptyState()
  local S = stateFor[plr]

  if type(which) ~= 'string' then
    return false, 'bad_target'
  end
  local t = STR.lower(which)

  if t == 'handl' or t == 'handr' then
    if
      (S.equipment.handL and isTwoHanded(S.equipment.handL))
      or (S.equipment.handR and isTwoHanded(S.equipment.handR))
    then
      S.equipment.handL, S.equipment.handR = nil, nil
    else
      S.equipment[t == 'handl' and 'handL' or 'handR'] = nil
    end
    pushAndVisuals(plr)
    return true
  end

  if validArmorSlots[t] then
    S.equipment[t] = nil
    pushAndVisuals(plr)
    return true
  end

  local num = STR.match(t, '^hotbar(%d+)$')
  local idx = num and tonumber(num) or nil
  if idx and idx >= 1 and idx <= 4 then
    if (idx == 2 or idx == 3) and isTwoHanded(S.hotbar[2] or S.hotbar[3] or '') then
      S.hotbar[2] = nil
      S.hotbar[3] = nil
      if uidByHotbar[plr] then
        uidByHotbar[plr][2] = nil
        uidByHotbar[plr][3] = nil
      end
    else
      S.hotbar[idx] = nil
      if uidByHotbar[plr] then
        uidByHotbar[plr][idx] = nil
      end
    end
    pushAll(plr)
    return true
  end

  return false, 'unknown_target'
end

-- ========= Hotbar press -> equip/toggle/clear =========
local function equipFromHotbar(plr: Player, idx: number)
  stateFor[plr] = stateFor[plr] or emptyState()
  local S = stateFor[plr]
  local id = S.hotbar[idx]
  if not id then
    if clearHands(S) then
      log(plr.Name .. ' cleared hands via empty hotbar press')
    end
    return pushAndVisuals(plr)
  end

  local def = itemDef(id)
  local slot = (def and def.equip and def.equip.slot)
    or (def and def.equipSlot)
    or (def and def.slot)
  slot = (type(slot) == 'string') and STR.lower(slot) or nil

  if slot == 'hand' then
    local already = (isTwoHanded(id) and S.equipment.handL == id and S.equipment.handR == id)
      or ((idx <= 2) and S.equipment.handL == id)
      or ((idx >= 3) and S.equipment.handR == id)

    if already then
      clearHands(S)
      log(plr.Name .. ' toggled off ' .. id .. ' from hotbar ' .. idx)
      return pushAndVisuals(plr)
    end

    if isTwoHanded(id) then
      S.equipment.handL = id
      S.equipment.handR = id
    else
      clearTwoHandIfHeld(S)
      if idx <= 2 then
        S.equipment.handL = id
      else
        S.equipment.handR = id
      end
    end

    log(plr.Name .. ' equipped ' .. id .. ' via hotbar ' .. idx)
    return pushAndVisuals(plr)
  end

  if slot == 'trinket' then
    if not S.equipment.trinket1 then
      S.equipment.trinket1 = id
    elseif S.equipment.trinket1 ~= id then
      S.equipment.trinket2 = id
    else
      S.equipment.trinket1 = nil
    end
    return pushAndVisuals(plr)
  end

  if slot and validArmorSlots[slot] then
    S.equipment[slot] = id
    return pushAndVisuals(plr)
  end
end

local function slotWasDrivingHands(S: EquipState, slotIndex: number): boolean
  local old = S.hotbar[slotIndex]
  if not old then
    return false
  end
  if isTwoHanded(old) then
    return S.equipment.handL == old and S.equipment.handR == old
  else
    return (slotIndex <= 2 and S.equipment.handL == old)
      or (slotIndex >= 3 and S.equipment.handR == old)
  end
end

-- ========= RPCs / Events =========
StashQuery.OnServerInvoke = function(plr: Player)
  return Inventory.getStashList(plr)
end
CarriedQuery.OnServerInvoke = function(plr: Player)
  return Inventory.getCarriedList(plr)
end

EquipmentQuery.OnServerInvoke = function(plr: Player)
  stateFor[plr] = stateFor[plr] or emptyState()
  local S = stateFor[plr]
  return {
    equipment = S.equipment,
    hotbar = S.hotbar,
    carried = carriedMinusEquipped(plr),
    uids = { hotbar = buildHotbarUIDs(plr) },
  }
end

EquipmentUIDQuery.OnServerInvoke = function(plr: Player)
  return {
    equipment = (stateFor[plr] or emptyState()).equipment,
    hotbarUID = buildHotbarUIDs(plr),
    carried = carriedMinusEquipped(plr),
  }
end

InventorySnapshot.OnServerInvoke = function(plr: Player) -- back-compat fetch under Remotes/RemoteFunction
  return makeSnapshot(plr)
end

EquipRequest.OnServerInvoke = function(plr: Player, id: string, target: string)
  if type(id) ~= 'string' or type(target) ~= 'string' then
    return false, 'bad_args'
  end
  local ok, why = equipTarget(plr, id, target)
  if not ok then
    warn('[EquipRequest] failed:', plr.Name, id, '->', target, why)
  end
  return ok, why
end

UnequipRequest.OnServerInvoke = function(plr: Player, which: string)
  if type(which) ~= 'string' then
    return false, 'bad_args'
  end
  local ok, why = unequipTarget(plr, which)
  if not ok then
    warn('[UnequipRequest] failed:', plr.Name, which, why)
  end
  return ok, why
end

HotbarSet.OnServerInvoke = function(plr: Player, slotIndex: number, id: string?)
  local which = 'hotbar' .. tostring(slotIndex)
  stateFor[plr] = stateFor[plr] or emptyState()
  local S = stateFor[plr]

  if id == nil then
    local ok, why = unequipTarget(plr, which)
    if not ok then
      warn('[HotbarSet] clear failed:', plr.Name, which, why)
    end
    return ok, why
  else
    local wasDriving = slotWasDrivingHands(S, slotIndex)
    local ok, why = equipTarget(plr, id, which)
    if ok then
      print(('[Hotbar] %s bound %s to slot %d'):format(plr.Name, id, slotIndex))
      if wasDriving then
        equipFromHotbar(plr, slotIndex)
      end
      -- Optional debug
      do
        local DB = ItemDB
        local rep = (typeof(DB.BindabilityReport) == 'function') and DB.BindabilityReport(id) or nil
        local okJson, repJson = pcall(function()
          return HttpService:JSONEncode(rep)
        end)
        local build = (
          DB
          and (
            DB.__build
            or (
              RS:FindFirstChild 'Modules'
              and RS.Modules:FindFirstChild 'ItemDB'
              and RS.Modules.ItemDB:GetAttribute 'ItemDBBuild'
            )
          )
        ) or '?'
        warn(
          ('[HotbarSet][debug] build=%s plr=%s id=%s slot=%s report=%s'):format(
            tostring(build),
            tostring(plr and plr.Name),
            tostring(id),
            tostring(which),
            okJson and repJson or 'nil'
          )
        )
      end
    else
      warn('[HotbarSet] bind failed:', plr.Name, id, '->', which, why)
    end
    return ok, why
  end
end

HotbarUse.OnServerEvent:Connect(function(plr: Player, idx: number)
  if typeof(idx) ~= 'number' then
    return
  end
  stateFor[plr] = stateFor[plr] or emptyState()
  if idx == 0 then
    if clearHands(stateFor[plr]) then
      log(plr.Name .. ' cleared hands via HotbarUse(0)')
    end
    return pushAndVisuals(plr)
  end
  if idx >= 1 and idx <= 4 then
    equipFromHotbar(plr, idx)
  end
end)

StashWithdraw.OnServerEvent:Connect(function(plr: Player, id: string, qty: number)
  if type(id) ~= 'string' or type(qty) ~= 'number' then
    return
  end
  local ok = Inventory.withdraw(plr, id, qty)
  InventoryNotice:FireClient(plr, 'stash_refresh', Inventory.getStashList(plr))
  if ok then
    InventoryNotice:FireClient(plr, 'withdrawn', { id = id, qty = qty })
    reconcileCarryAttrs(plr, 'withdraw')
    pushAll(plr)
  end
end)

-- ========= Mutation wrappers (centralize UI & weight pushes) =========
local function afterMutation(plr: any, reason: string)
  if typeof(plr) == 'Instance' and plr:IsA 'Player' then
    reconcileCarryAttrs(plr, reason)
    pushAll(plr)
  end
end

local function wrapMutator(name: string)
  local f = (Inventory :: any)[name]
  if type(f) ~= 'function' then
    return
  end
  (Inventory :: any)[name] = function(...)
    local results = table.pack(f(...)) -- keep original returns
    local plr = select(1, ...)
    afterMutation(plr, name)
    return table.unpack(results, 1, results.n)
  end
end

for _, n in ipairs {
  'addItem',
  'Give',
  'withdraw',
  'MoveToStash',
  'addCarried',
  'removeCarried',
  'equip',
  'unequip',
  'setHotbar',
} do
  wrapMutator(n)
end

-- If Inventory exposes a change signal or callback, hook it so pickups/chests push instantly.
local function hookInventorySignals()
  local okSignal, signal = pcall(function()
    return (Inventory :: any).Changed
  end)
  if okSignal and typeof(signal) == 'RBXScriptSignal' then
    signal:Connect(function(plr: Player)
      reconcileCarryAttrs(plr, 'inventory_changed_signal')
      pushAll(plr)
    end)
  end
  if typeof((Inventory :: any).onChanged) == 'function' then
    pcall(function()
      (Inventory :: any).onChanged(function(plr: Player)
        reconcileCarryAttrs(plr, 'inventory_changed_cb')
        pushAll(plr)
      end)
    end)
  end
  local rem = RS:FindFirstChild 'Remotes'
  local invChanged = rem and rem:FindFirstChild 'InventoryChanged'
  if invChanged and invChanged:IsA 'RemoteEvent' then
    invChanged.OnServerEvent:Connect(function(plr: Player)
      reconcileCarryAttrs(plr, 'inventory_changed_remote')
      pushAll(plr)
    end)
  end
end
hookInventorySignals()

-- ========= Lifecycle =========
local function onPlayerAdded(plr: Player)
  stateFor[plr] = emptyState()
  reconcileCarryAttrs(plr, 'join')
  carriedHash[plr] = carriedFingerprint(carriedMinusEquipped(plr))
  plr.CharacterAdded:Connect(function()
    task.defer(function()
      pushAll(plr)
      updateHandVisuals(plr)
    end)
  end)
  -- ensure clients that fetch immediately have data
  task.defer(function()
    pushAll(plr)
  end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do
  onPlayerAdded(p)
end

Players.PlayerRemoving:Connect(function(plr: Player)
  local bag = heldVisuals[plr]
  if bag then
    if bag.L then
      bag.L:Destroy()
    end
    if bag.R then
      bag.R:Destroy()
    end
  end
  heldVisuals[plr] = nil
  stateFor[plr] = nil
  uidByHotbar[plr] = nil
  carriedHash[plr] = nil
end)

-- periodic carry sync + auto refresh
local ACCUM, PERIOD = 0, 0.4
RunService.Heartbeat:Connect(function(dt)
  ACCUM += dt
  if ACCUM < PERIOD then
    return
  end
  ACCUM -= PERIOD
  for _, plr in ipairs(Players:GetPlayers()) do
    if plr.Parent then
      reconcileCarryAttrs(plr, 'tick')
      local filtered = carriedMinusEquipped(plr)
      local fp = carriedFingerprint(filtered)
      if carriedHash[plr] ~= fp then
        InventoryNotice:FireClient(plr, 'carried_refresh', filtered)
        carriedHash[plr] = fp
        pushInventorySnapshot(plr)
      end
    end
  end
end)

print '[InventoryService] Ready (equip filters carried; unified pushes; hotbar toggling & empty clears).'

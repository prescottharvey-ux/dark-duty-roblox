--!strict
-- 4-slot hotbar, resilient to snapshot/event variations. Optional durability bars.

local Players = game:GetService 'Players'
local RS = game:GetService 'ReplicatedStorage'
local CAS = game:GetService 'ContextActionService'
local UIS = game:GetService 'UserInputService'
local Http = game:GetService 'HttpService'

local me = Players.LocalPlayer

-- ===== ItemDB (for names/two-handed info) =====
local ItemDB: any = (function()
  local ok, mod = pcall(function()
    return require(RS:WaitForChild('Modules'):WaitForChild 'ItemDB')
  end)
  return ok and mod or {}
end)()

local function getItemDef(id: string?): any
  if not id then
    return nil
  end
  if typeof(ItemDB) == 'table' then
    local m = (typeof(ItemDB.GetItem) == 'function') and ItemDB.GetItem(id) or ItemDB[id]
    return m
  end
  return nil
end

local function isTwoHanded(def: any): boolean
  if not def then
    return false
  end
  if typeof(def) == 'table' then
    if typeof(def.equip) == 'table' and def.equip.twoHanded ~= nil then
      return def.equip.twoHanded == true
    end
    if def.twoHanded ~= nil then
      return def.twoHanded == true
    end
  end
  return false
end

-- ===== Remotes (robust discovery; NO dependency on Remotes/Hotbar folder) =====
local Remotes = RS:FindFirstChild 'Remotes'
if not Remotes then
  warn '[HotbarHUD] ReplicatedStorage/Remotes missing; HUD disabled'
  return
end
local RFF = Remotes:FindFirstChild 'RemoteFunction'
local REF = Remotes:FindFirstChild 'RemoteEvent'

local EquipmentQuery: RemoteFunction? = RFF
    and (RFF:FindFirstChild 'EquipmentQuery' :: RemoteFunction?)
  or nil
local EquipRequest: RemoteFunction? = RFF
    and (RFF:FindFirstChild 'EquipRequest' :: RemoteFunction?)
  or nil
local UnequipRequest: RemoteFunction? = RFF
    and (RFF:FindFirstChild 'UnequipRequest' :: RemoteFunction?)
  or nil
local EquipmentUIDQuery: RemoteFunction? = RFF
    and (RFF:FindFirstChild 'EquipmentUIDQuery' :: RemoteFunction?)
  or nil

local EquipChanged: RemoteEvent? = REF and (REF:FindFirstChild 'EquipChanged' :: RemoteEvent?)
  or nil
local HotbarUse: RemoteEvent? = REF and (REF:FindFirstChild 'HotbarUse' :: RemoteEvent?) or nil

-- ===== Optional DurabilityUI (never blocks) =====
local DurUI: any = (function()
  local ok, mod = pcall(function()
    local mods = RS:FindFirstChild 'Modules'
    local ui = mods and mods:FindFirstChild 'UI'
    local d = ui and ui:FindFirstChild 'DurabilityUI'
    return d and require(d) or nil
  end)
  if ok and mod then
    return mod
  end
  warn '[HotbarHUD] DurabilityUI not found; durability bars disabled.'
  return { Attach = function() end, Detach = function() end, Set = function() end, Bind = function() end }
end)()

-- ===== UI scaffold =====
local gui = Instance.new 'ScreenGui'
gui.Name = 'HotbarHUD'
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 40
gui.Parent = me:WaitForChild 'PlayerGui'

local root = Instance.new 'Frame'
root.Name = 'Root'
root.AnchorPoint = Vector2.new(0.5, 1)
root.Position = UDim2.fromScale(0.5, 0.98)
root.Size = UDim2.fromOffset(420, 60)
root.BackgroundTransparency = 1
root.Parent = gui

local function mkSlot(idx: number, x: number): Frame
  local f = Instance.new 'Frame'
  f.Name = ('Slot%d'):format(idx)
  f.Size = UDim2.fromOffset(96, 44)
  f.Position = UDim2.fromOffset(x, 0)
  f.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
  f.BackgroundTransparency = 0.10
  f.BorderSizePixel = 0
  f.Parent = root

  local key = Instance.new 'TextLabel'
  key.Name = 'Key'
  key.Size = UDim2.fromOffset(18, 18)
  key.Position = UDim2.fromOffset(6, 4)
  key.BackgroundTransparency = 1
  key.Font = Enum.Font.GothamBold
  key.TextScaled = true
  key.TextColor3 = Color3.fromRGB(200, 200, 200)
  key.Text = tostring(idx)
  key.Parent = f

  local name = Instance.new 'TextLabel'
  name.Name = 'Value'
  name.Size = UDim2.fromOffset(84, 18)
  name.Position = UDim2.fromOffset(6, 20)
  name.BackgroundTransparency = 1
  name.Font = Enum.Font.Gotham
  name.TextScaled = true
  name.TextWrapped = true
  name.TextColor3 = Color3.fromRGB(255, 255, 255)
  name.Text = '-'
  name.Parent = f

  local r = Instance.new 'UICorner'
  r.CornerRadius = UDim.new(0, 6)
  r.Parent = f

  return f
end

local slotGui: { [number]: Frame } = {
  [1] = mkSlot(1, 0),
  [2] = mkSlot(2, 106),
  [3] = mkSlot(3, 212),
  [4] = mkSlot(4, 318),
}

-- ===== State =====
type HotbarCell = string | { id: string, uid: string? }
type Snapshot = { equipment: { [string]: any }?, hotbar: { [number]: HotbarCell? }? }
local snap: Snapshot = { equipment = {}, hotbar = {} }
local slotBoundUid: { [number]: string? } = {}

-- ===== Helpers =====
local function itemName(id: string?): string
  if not id then
    return '-'
  end
  local def = getItemDef(id)
  return (def and (def.displayName or def.name)) or id
end

local function cellToIdAndUid(cell: HotbarCell?): (string?, string?)
  if cell == nil then
    return nil, nil
  end
  if typeof(cell) == 'string' then
    return cell :: string, nil
  end
  local t = cell :: any
  return t.id, t.uid
end

local function tint(cell: Frame, isActive: boolean?, isTwoHand: boolean?)
  if isActive then
    cell.BackgroundColor3 = isTwoHand and Color3.fromRGB(45, 70, 45) or Color3.fromRGB(35, 60, 35)
  else
    cell.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
  end
end

local function bindDurabilityIfUid(slotIndex: number, cell: Frame, uid: string?)
  if slotBoundUid[slotIndex] == uid then
    return
  end
  slotBoundUid[slotIndex] = uid
  if uid then
    pcall(function()
      DurUI.Bind(cell, uid, 1.0)
    end)
  else
    pcall(function()
      DurUI.Detach(cell)
    end)
  end
end

local function debugHotbar(prefix: string)
  local arr: { any } = {}
  for i = 1, 4 do
    local id, uid = cellToIdAndUid((snap.hotbar or {})[i])
    if id then
      table.insert(arr, uid and { id = id, uid = uid } or id)
    else
      table.insert(arr, nil)
    end
  end
  local ok, j = pcall(function()
    return Http:JSONEncode(arr)
  end)
  print(prefix, ok and j or '<json fail>')
end

-- Normalize any snapshot/event shape into snap.hotbar[1..4]
local function normalizeIntoSnap(from: any): boolean
  if typeof(from) ~= 'table' then
    return false
  end

  local function coerceCell(v: any): HotbarCell?
    if v == nil then
      return nil
    end
    if typeof(v) == 'string' then
      return v
    end
    if typeof(v) == 'table' then
      local id = v.id or v.itemId or v.name
      local uid = v.uid or v.instanceId
      if id then
        return uid and { id = id, uid = uid } or id
      end
    end
    return nil
  end

  local out: { [number]: HotbarCell? } = {}

  -- from.hotbar with numeric / string keys
  local hb = from.hotbar
  if typeof(hb) == 'table' then
    for i = 1, 4 do
      out[i] = out[i] or coerceCell(hb[i])
      out[i] = out[i] or coerceCell(hb[tostring(i)])
      out[i] = out[i] or coerceCell(hb['hotbar' .. i])
    end
  end

  -- flattened keys hotbar1..hotbar4
  for i = 1, 4 do
    out[i] = out[i] or coerceCell(from['hotbar' .. i])
  end

  -- sometimes embedded under equipment
  if typeof(from.equipment) == 'table' then
    for i = 1, 4 do
      out[i] = out[i] or coerceCell(from.equipment['hotbar' .. i])
    end
  end

  local anySet = false
  for i = 1, 4 do
    if out[i] ~= nil then
      anySet = true
    end
  end
  if anySet then
    snap.hotbar = out
    if typeof(from.equipment) == 'table' then
      snap.equipment = from.equipment
    end
    return true
  end
  return false
end

local function refreshUI()
  for i = 1, 4 do
    local cell = slotGui[i]
    local lab = cell:FindFirstChild 'Value' :: TextLabel?
    local id, uid = cellToIdAndUid((snap.hotbar or {})[i])
    if lab then
      lab.Text = itemName(id)
    end

    local def = getItemDef(id)
    local twoHand = isTwoHanded(def)

    local eq = snap.equipment or {}
    local active = false
    if id then
      active = (eq.handL == id or eq.handR == id or eq.handLId == id or eq.handRId == id)
    end
    if uid then
      active = active or (eq.handLUid == uid or eq.handRUid == uid)
    end
    tint(cell, active, twoHand)

    bindDurabilityIfUid(i, cell, uid)
  end
  debugHotbar '[HotbarHUD] normalized hotbar ->'
end

local function fetch(retried: boolean?)
  -- Prefer UID-aware query if present
  if EquipmentUIDQuery then
    local ok, s = pcall(function()
      return (EquipmentUIDQuery :: RemoteFunction):InvokeServer()
    end)
    if ok and typeof(s) == 'table' and normalizeIntoSnap(s) then
      refreshUI()
      return
    end
  end
  -- Fallback
  if EquipmentQuery then
    local ok, s = pcall(function()
      return (EquipmentQuery :: RemoteFunction):InvokeServer()
    end)
    if ok and typeof(s) == 'table' and normalizeIntoSnap(s) then
      refreshUI()
      return
    end
  end
  warn '[HotbarHUD] fetch: snapshot not recognized or remotes missing.'
  if not retried then
    task.delay(0.6, function()
      fetch(true)
    end)
  end
end

-- ===== EquipChanged handling =====
if EquipChanged then
  (EquipChanged :: RemoteEvent).OnClientEvent:Connect(function(payload: any)
    if typeof(payload) == 'table' then
      -- A) Full snapshot
      if
        payload.hotbar
        or (payload.equipment and (payload.equipment.hotbar or payload.equipment.hotbar1))
      then
        if normalizeIntoSnap(payload) then
          refreshUI()
          return
        end
      end
      -- B) Minimal update {slot="hotbar1", id="...", uid?}
      local slotStr = payload.slot or payload.Slot
      if slotStr and type(slotStr) == 'string' then
        local n = tonumber(string.match(slotStr, 'hotbar(%d)'))
        if n and n >= 1 and n <= 4 then
          local id = payload.id
          local uid = payload.uid
          if (not id) and typeof(payload.report) == 'table' then
            id = payload.report.id or payload.report.itemId or payload.report.name
            uid = payload.report.uid or payload.report.instanceId
          end
          if id then
            (snap.hotbar or (function()
              snap.hotbar = {}
              return snap.hotbar
            end)())[n] = (
              uid and { id = id, uid = uid }
            ) or id
            refreshUI()
            return
          end
        end
      end
    end
    task.defer(function()
      fetch(true)
    end)
  end)
end

-- ===== Input & actions =====
local function controlsEnable()
  local pm = me:FindFirstChild 'PlayerScripts' and me.PlayerScripts:FindFirstChild 'PlayerModule'
  if pm and pm:IsA 'ModuleScript' then
    local ok, mod = pcall(require, pm)
    if ok and type(mod) == 'table' and mod.GetControls then
      local controls = mod:GetControls()
      if controls and controls.Enable then
        pcall(function()
          controls:Enable()
        end)
      end
    end
  end
end

local function typing(): boolean
  return UIS:GetFocusedTextBox() ~= nil
end

local function uiOpen(): boolean
  if typing() then
    return true
  end
  local pg = me:FindFirstChild 'PlayerGui'
  if not pg then
    return false
  end
  local a = pg:FindFirstChild 'StashUI'
  local b = pg:FindFirstChild 'PaperDollUI'
  return (a and a:IsA 'ScreenGui' and a.Enabled) or (b and b:IsA 'ScreenGui' and b.Enabled) or false
end

local lastUse: { [number]: number } = {}

local function clearHands()
  if UnequipRequest then
    pcall(function()
      (UnequipRequest :: RemoteFunction):InvokeServer 'handL'
    end)
    pcall(function()
      (UnequipRequest :: RemoteFunction):InvokeServer 'handR'
    end)
  elseif HotbarUse then
    (HotbarUse :: RemoteEvent):FireServer(0)
  end
  controlsEnable()
end

local function useSlot(i: number)
  local now = os.clock()
  if lastUse[i] and now - lastUse[i] < 0.12 then
    return
  end
  lastUse[i] = now
  if uiOpen() then
    return
  end

  local id, _uid = cellToIdAndUid((snap.hotbar or {})[i])
  if not id then
    clearHands()
    return
  end

  if HotbarUse then
    (HotbarUse :: RemoteEvent):FireServer(i)
    controlsEnable()
    return
  end

  -- Fallback: drive the old EquipRequest protocol if present
  local def = getItemDef(id)
  if not def then
    return
  end

  if def.equip and def.equip.slot == 'hand' then
    if isTwoHanded(def) then
      if EquipRequest then
        (EquipRequest :: RemoteFunction):InvokeServer(id, 'handL')
      end -- server can claim both
    else
      local target = (i <= 2) and 'handL' or 'handR'
      if EquipRequest then
        (EquipRequest :: RemoteFunction):InvokeServer(id, target)
      end
    end
  elseif def.equip then
    local slot = def.equip.slot
    if slot == 'trinket' then
      local cur = snap.equipment or {}
      local tslot = (cur.trinket1 == nil) and 'trinket1' or 'trinket2'
      if EquipRequest then
        (EquipRequest :: RemoteFunction):InvokeServer(id, tslot)
      end
    else
      if EquipRequest then
        (EquipRequest :: RemoteFunction):InvokeServer(id, slot)
      end
    end
  end
  controlsEnable()
end

local ACTION = 'HotbarUseKeys'
pcall(function()
  CAS:UnbindAction(ACTION)
end)

local function hotbarAction(_: string, state: Enum.UserInputState, input: InputObject)
  if state ~= Enum.UserInputState.Begin then
    return Enum.ContextActionResult.Pass
  end
  if uiOpen() then
    return Enum.ContextActionResult.Pass
  end
  local kc = input.KeyCode
  if kc == Enum.KeyCode.One then
    useSlot(1)
    return Enum.ContextActionResult.Sink
  end
  if kc == Enum.KeyCode.Two then
    useSlot(2)
    return Enum.ContextActionResult.Sink
  end
  if kc == Enum.KeyCode.Three then
    useSlot(3)
    return Enum.ContextActionResult.Sink
  end
  if kc == Enum.KeyCode.Four then
    useSlot(4)
    return Enum.ContextActionResult.Sink
  end
  return Enum.ContextActionResult.Pass
end

local function bindKeys()
  local ok = pcall(function()
    if CAS.BindActionAtPriority then
      CAS:BindActionAtPriority(
        ACTION,
        hotbarAction,
        false, -- don't consume movement
        Enum.ContextActionPriority.Low.Value,
        Enum.KeyCode.One,
        Enum.KeyCode.Two,
        Enum.KeyCode.Three,
        Enum.KeyCode.Four
      )
    else
      CAS:BindAction(
        ACTION,
        hotbarAction,
        false,
        Enum.KeyCode.One,
        Enum.KeyCode.Two,
        Enum.KeyCode.Three,
        Enum.KeyCode.Four
      )
    end
  end)
  if not ok then
    warn '[HotbarHUD] keybind failed; will retry shortly'
    task.delay(1, bindKeys)
  end
end

print '[HotbarHUD] boot'
bindKeys()
task.defer(function()
  fetch(false)
end)

--!strict
-- PaperDoll UI – drag & drop between Carried ⇄ Armor ⇄ Hotbar (4 slots)
-- Double-click carried to equip smartly. Opens with I. Hides Stash if open.

local Players = game:GetService 'Players'
local RS = game:GetService 'ReplicatedStorage'
local UIS = game:GetService 'UserInputService'
local CAS = game:GetService 'ContextActionService'
local RunService = game:GetService 'RunService'

local me = Players.LocalPlayer

-- Prevent duplicate instances
do
  local pg = me:WaitForChild 'PlayerGui'
  local existing = pg:FindFirstChild 'PaperDollUI'
  if existing then
    existing.Enabled = true
    script:Destroy()
    return
  end
end

-- ---------- Modules + Remotes ----------
local ItemDB: any
do
  local ok, mod = pcall(function()
    return require(RS:WaitForChild('Modules'):WaitForChild 'ItemDB')
  end)
  ItemDB = ok and mod or {}
end

local Remotes = RS:WaitForChild('Remotes', 5)
if not Remotes then
  warn '[PaperDollUI] ReplicatedStorage/Remotes not found; UI will be inert'
  return
end
local RFF = Remotes:WaitForChild('RemoteFunction', 5)
local REF = Remotes:WaitForChild('RemoteEvent', 5)
if not RFF or not REF then
  warn '[PaperDollUI] Remote folders missing'
  return
end

local EquipmentQuery: RemoteFunction? = RFF:FindFirstChild 'EquipmentQuery' :: RemoteFunction?
local EquipmentUIDQuery: RemoteFunction? = RFF:FindFirstChild 'EquipmentUIDQuery' :: RemoteFunction?
local EquipRequest: RemoteFunction? = RFF:FindFirstChild 'EquipRequest' :: RemoteFunction?
local UnequipRequest: RemoteFunction? = RFF:FindFirstChild 'UnequipRequest' :: RemoteFunction?
local HotbarSet: RemoteFunction? = RFF:FindFirstChild 'HotbarSet' :: RemoteFunction?

local EquipChanged: RemoteEvent? = REF:FindFirstChild 'EquipChanged' :: RemoteEvent?

-- ---------- UI scaffold ----------
local gui = Instance.new 'ScreenGui'
gui.Name = 'PaperDollUI'
gui.ResetOnSpawn = false
gui.Enabled = false
gui.DisplayOrder = 60
gui.Parent = me:WaitForChild 'PlayerGui'

local panel = Instance.new 'Frame'
panel.AnchorPoint = Vector2.new(1, 0.5)
panel.Position = UDim2.fromScale(0.98, 0.5)
panel.Size = UDim2.fromOffset(420, 480)
panel.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
panel.BackgroundTransparency = 0.05
panel.Parent = gui

local header = Instance.new 'TextLabel'
header.Size = UDim2.new(1, -20, 0, 28)
header.Position = UDim2.fromOffset(10, 10)
header.BackgroundTransparency = 1
header.Font = Enum.Font.GothamBold
header.TextScaled = true
header.TextXAlignment = Enum.TextXAlignment.Left
header.TextColor3 = Color3.new(1, 1, 1)
header.Text = 'Equipment & Hotbar'
header.Parent = panel

local statusL = Instance.new 'TextLabel'
statusL.Size = UDim2.new(1, -20, 0, 18)
statusL.Position = UDim2.fromOffset(10, 40)
statusL.BackgroundTransparency = 1
statusL.Font = Enum.Font.Gotham
statusL.TextScaled = true
statusL.TextXAlignment = Enum.TextXAlignment.Left
statusL.TextColor3 = Color3.fromRGB(190, 190, 190)
statusL.Text = ''
statusL.Parent = panel

local function flashStatus(msg: string)
  statusL.Text = msg
  task.delay(1.25, function()
    if statusL and statusL.Parent then
      statusL.Text = ''
    end
  end)
end

-- carried (left column)
local carried = Instance.new 'ScrollingFrame'
carried.AnchorPoint = Vector2.new(1, 0)
carried.Position = UDim2.fromOffset(-10, 68)
carried.Size = UDim2.fromOffset(180, 402)
carried.BackgroundTransparency = 0.15
carried.AutomaticCanvasSize = Enum.AutomaticSize.Y
carried.CanvasSize = UDim2.new()
carried.Parent = panel

local carriedList = Instance.new 'UIListLayout'
carriedList.Padding = UDim.new(0, 6)
carriedList.Parent = carried

-- equipment (right column)
local equipFrame = Instance.new 'Frame'
equipFrame.Position = UDim2.fromOffset(200, 68)
equipFrame.Size = UDim2.fromOffset(210, 220)
equipFrame.BackgroundTransparency = 1
equipFrame.Parent = panel

local function equipRow(y: number, label: string, slot: string): Frame
  local r = Instance.new 'Frame'
  r.Name = 'slot_' .. slot
  r.Position = UDim2.fromOffset(0, y)
  r.Size = UDim2.fromOffset(210, 28)
  r.BackgroundColor3 = Color3.fromRGB(28, 28, 32)
  r.BackgroundTransparency = 0.05
  r.Active = true
  r.Parent = equipFrame

  local lab = Instance.new 'TextLabel'
  lab.Size = UDim2.fromOffset(90, 28)
  lab.BackgroundTransparency = 1
  lab.TextXAlignment = Enum.TextXAlignment.Left
  lab.Font = Enum.Font.Gotham
  lab.TextScaled = true
  lab.TextColor3 = Color3.fromRGB(220, 220, 220)
  lab.Text = label
  lab.Parent = r

  local val = Instance.new 'TextLabel'
  val.Name = 'Value'
  val.Position = UDim2.fromOffset(92, 0)
  val.Size = UDim2.fromOffset(118, 28)
  val.BackgroundTransparency = 1
  val.Font = Enum.Font.Gotham
  val.TextScaled = true
  val.TextColor3 = Color3.new(1, 1, 1)
  val.Text = '-'
  val.Parent = r

  return r
end

local rows = {
  head = equipRow(0, 'Head', 'head'),
  torso = equipRow(32, 'Torso', 'torso'),
  hands = equipRow(64, 'Gloves', 'hands'),
  legs = equipRow(96, 'Legs', 'legs'),
  feet = equipRow(128, 'Feet', 'feet'),
  trinket1 = equipRow(160, 'Trinket 1', 'trinket1'),
  trinket2 = equipRow(192, 'Trinket 2', 'trinket2'),
}

-- Hotbar (4)
local hotbar = Instance.new 'Frame'
hotbar.Position = UDim2.fromOffset(200, 300)
hotbar.Size = UDim2.fromOffset(210, 170)
hotbar.BackgroundTransparency = 1
hotbar.Parent = panel

local slotGui: { [number]: Frame } = {}
for i = 1, 4 do
  local cell = Instance.new 'Frame'
  cell.Active = true
  cell.Name = 'hotbar' .. i
  cell.Size = UDim2.fromOffset(96, 40)
  cell.Position = UDim2.fromOffset(((i - 1) % 2) * 106, math.floor((i - 1) / 2) * 48)
  cell.BackgroundColor3 = Color3.fromRGB(28, 28, 32)
  cell.BackgroundTransparency = 0.05
  cell.Parent = hotbar

  local k = Instance.new 'TextLabel'
  k.Size = UDim2.fromOffset(16, 16)
  k.Position = UDim2.fromOffset(6, 4)
  k.BackgroundTransparency = 1
  k.Font = Enum.Font.GothamBold
  k.TextScaled = true
  k.TextColor3 = Color3.fromRGB(200, 200, 200)
  k.Text = tostring(i)
  k.Parent = cell

  local name = Instance.new 'TextLabel'
  name.Name = 'Value'
  name.Position = UDim2.fromOffset(6, 20)
  name.Size = UDim2.fromOffset(84, 18)
  name.BackgroundTransparency = 1
  name.Font = Enum.Font.Gotham
  name.TextScaled = true
  name.TextColor3 = Color3.new(1, 1, 1)
  name.Text = '-'
  name.Parent = cell

  slotGui[i] = cell
end

-- ---------- State & helpers ----------
type HotbarCell = string | { id: string, uid: string? }
type Snapshot = {
  equipment: { [string]: any }?,
  hotbar: { [number]: HotbarCell? }?,
  carried: { any }?,
}

local snap: Snapshot = { equipment = {}, hotbar = {}, carried = {} }

local function getItemDef(id: string?): any
  if not id then
    return nil
  end
  if typeof(ItemDB) == 'table' then
    local getter = (typeof(ItemDB.GetItem) == 'function') and ItemDB.GetItem(id)
      or (ItemDB :: any)[id]
    return getter
  end
  return nil
end

local function itemDisplayName(id: string?): string
  if not id then
    return '-'
  end
  local def = getItemDef(id)
  return (def and (def.displayName or def.name)) or id
end

local function cellToId(cell: HotbarCell?): string?
  if cell == nil then
    return nil
  end
  if typeof(cell) == 'string' then
    return cell :: string
  end
  local t = cell :: any
  return t.id or t.itemId or t.name
end

local function setVal(container: Instance, text: string)
  local v = container:FindFirstChild 'Value'
  if v and v:IsA 'TextLabel' then
    v.Text = text
  end
end

-- Smart double-click equip
local function equipSmart(id: string)
  if not EquipRequest then
    return
  end
  local def = getItemDef(id)
  if not def then
    return
  end
  if def.equip and def.equip.slot == 'hand' then
    (EquipRequest :: RemoteFunction):InvokeServer(id, 'handL') -- server will claim both if 2H
  else
    local slot = def.equip and def.equip.slot
    if slot == 'trinket' then
      slot = 'trinket1'
    end
    if slot then
      (EquipRequest :: RemoteFunction):InvokeServer(id, slot)
    end
  end
end

-- ---------- Snapshot normalization (accepts many shapes) ----------
local function normalize(from: any): boolean
  if typeof(from) ~= 'table' then
    return false
  end

  -- normalize hotbar into indices 1..4
  local out: { [number]: HotbarCell? } = {}
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

  local hb = from.hotbar
  if typeof(hb) == 'table' then
    for i = 1, 4 do
      out[i] = out[i] or coerceCell(hb[i])
      out[i] = out[i] or coerceCell(hb[tostring(i)])
      out[i] = out[i] or coerceCell(hb['hotbar' .. i])
    end
  end
  for i = 1, 4 do
    out[i] = out[i] or coerceCell(from['hotbar' .. i])
  end
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
  end

  -- equipment
  if typeof(from.equipment) == 'table' then
    snap.equipment = from.equipment
  end

  -- carried list normalization (accepts {"dagger"} or {{id="dagger", qty=1}} etc.)
  if typeof(from.carried) == 'table' then
    local outC: { any } = {}
    for _, e in ipairs(from.carried) do
      if typeof(e) == 'string' then
        table.insert(outC, { id = e, qty = 1 })
      elseif typeof(e) == 'table' then
        local id = e.id or e.itemId or e.name
        local qty = e.qty or e.count or 1
        if not id then
          for k, v in pairs(e) do
            if typeof(k) == 'string' and typeof(v) == 'number' then
              id, qty = k, v
              break
            end
          end
        end
        if id then
          table.insert(outC, { id = id, qty = qty })
        end
      end
    end
    snap.carried = outC
  end

  return anySet or (typeof(from.equipment) == 'table') or (typeof(from.carried) == 'table')
end

-- ---------- UI refresh ----------
local function refreshUI()
  local eq = snap.equipment or {}

  setVal(rows.head, itemDisplayName(eq.head))
  setVal(rows.torso, itemDisplayName(eq.torso))
  setVal(rows.hands, itemDisplayName(eq.hands))
  setVal(rows.legs, itemDisplayName(eq.legs))
  setVal(rows.feet, itemDisplayName(eq.feet))
  setVal(rows.trinket1, itemDisplayName(eq.trinket1))
  setVal(rows.trinket2, itemDisplayName(eq.trinket2))

  for i = 1, 4 do
    local lab = slotGui[i] and slotGui[i]:FindFirstChild 'Value'
    if lab and lab:IsA 'TextLabel' then
      lab.Text = itemDisplayName(cellToId((snap.hotbar or {})[i]))
    end
  end

  -- rebuild carried list inside panel
  for _, c in ipairs(carried:GetChildren()) do
    if c:IsA 'GuiObject' and c ~= carriedList then
      c:Destroy()
    end
  end
  for _, e in ipairs(snap.carried or {}) do
    local id = e.id :: string?
    local qty = (e.qty :: number?) or 1
    if id then
      local btn = Instance.new 'TextButton'
      btn.Size = UDim2.new(1, -8, 0, 30)
      btn.Position = UDim2.fromOffset(4, 0)
      btn.BackgroundColor3 = Color3.fromRGB(36, 36, 36)
      btn.TextColor3 = Color3.fromRGB(240, 240, 240)
      btn.TextScaled = true
      btn.TextXAlignment = Enum.TextXAlignment.Left
      btn.Font = Enum.Font.Gotham
      btn.Text = string.format('%s  ×%d', itemDisplayName(id), qty)
      btn.Parent = carried
      btn:SetAttribute('id', id)

      -- double-click to equip smartly
      local lastClick = 0
      btn.Activated:Connect(function()
        local t = os.clock()
        if t - lastClick < 0.3 and id then
          equipSmart(id)
        end
        lastClick = t
      end)
    end
  end
end

local function fetch()
  -- Prefer UID-aware snapshot
  if EquipmentUIDQuery then
    local ok, s = pcall(function()
      return (EquipmentUIDQuery :: RemoteFunction):InvokeServer()
    end)
    if ok and typeof(s) == 'table' and normalize(s) then
      refreshUI()
      return
    end
  end
  if EquipmentQuery then
    local ok, s = pcall(function()
      return (EquipmentQuery :: RemoteFunction):InvokeServer()
    end)
    if ok and typeof(s) == 'table' and normalize(s) then
      refreshUI()
      return
    end
  end
  warn '[PaperDollUI] fetch: snapshot not recognized or remotes missing.'
end

if EquipChanged then
  (EquipChanged :: RemoteEvent).OnClientEvent:Connect(function(payload: any)
    if typeof(payload) == 'table' and normalize(payload) then
      refreshUI()
    else
      task.defer(fetch)
    end
  end)
end

-- ---------- Drag & drop ----------
type Drag = { id: string, source: 'carried' | 'slot' | 'hotbar', arg: any }
local dragging: Drag? = nil
local dragGhost: TextLabel? = nil

local function isInside(g: GuiObject, x: number, y: number): boolean
  local p = g.AbsolutePosition
  local s = g.AbsoluteSize
  return x >= p.X and x <= p.X + s.X and y >= p.Y and y <= p.Y + s.Y
end

local function startGhost(id: string)
  dragGhost = Instance.new 'TextLabel'
  dragGhost.Text = itemDisplayName(id)
  dragGhost.TextScaled = true
  dragGhost.Font = Enum.Font.GothamBold
  dragGhost.Size = UDim2.fromOffset(160, 28)
  dragGhost.BackgroundTransparency = 0.2
  dragGhost.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
  dragGhost.TextColor3 = Color3.new(1, 1, 1)
  dragGhost.ZIndex = 1000
  dragGhost.Parent = gui
end

local function clearDrag()
  dragging = nil
  if dragGhost then
    dragGhost:Destroy()
  end
  dragGhost = nil
end

local function beginDragCarried(id: string)
  dragging = { id = id, source = 'carried', arg = nil }
  startGhost(id)
end

local function beginDragSlot(slot: string)
  local id = (snap.equipment or {})[slot]
  if not id then
    return
  end
  dragging = { id = id, source = 'slot', arg = slot }
  startGhost(id)
end

local function beginDragHotbar(i: number)
  local id = cellToId((snap.hotbar or {})[i])
  if not id then
    return
  end
  dragging = { id = id, source = 'hotbar', arg = i }
  startGhost(id)
end

local function endDrag(dropX: number, dropY: number)
  if not dragging then
    return
  end
  local id, source, arg = dragging.id, dragging.source, dragging.arg

  -- Armor rows
  for slot, row in pairs(rows) do
    if isInside(row, dropX, dropY) then
      if not EquipRequest then
        return clearDrag()
      end
      local ok, success, why = pcall(function()
        return (EquipRequest :: RemoteFunction):InvokeServer(id, slot)
      end)
      if ok and success then
        flashStatus(('Equipped %s → %s'):format(itemDisplayName(id), slot))
      else
        flashStatus(('Equip failed: %s'):format(tostring(why or 'error')))
      end
      clearDrag()
      return
    end
  end

  -- Hotbar cells
  for i = 1, 4 do
    if isInside(slotGui[i], dropX, dropY) then
      if not HotbarSet then
        return clearDrag()
      end
      local ok, success, why = pcall(function()
        return (HotbarSet :: RemoteFunction):InvokeServer(i, id)
      end)
      if ok and success then
        flashStatus(('Bound %s → %d'):format(itemDisplayName(id), i))
      else
        flashStatus(('Bind failed: %s'):format(tostring(why or 'error')))
      end
      clearDrag()
      return
    end
  end

  -- Dropping onto the carried list area = unbind/unequip
  if isInside(carried, dropX, dropY) then
    if source == 'slot' then
      if UnequipRequest then
        pcall(function()
          (UnequipRequest :: RemoteFunction):InvokeServer(arg :: string)
        end)
      end
      flashStatus 'Unequipped'
    elseif source == 'hotbar' then
      if UnequipRequest then
        pcall(function()
          (UnequipRequest :: RemoteFunction):InvokeServer('hotbar' .. tostring(arg :: number))
        end)
      end
      flashStatus 'Unbound'
    else
      flashStatus 'Already in inventory'
    end
    clearDrag()
    return
  end

  flashStatus 'No drop target'
  clearDrag()
end

-- make carried rows draggable (created dynamically)
carried.ChildAdded:Connect(function(c)
  if c:IsA 'TextButton' then
    c.InputBegan:Connect(function(io)
      if io.UserInputType == Enum.UserInputType.MouseButton1 then
        local id = c:GetAttribute 'id'
        if type(id) == 'string' then
          beginDragCarried(id)
        end
      end
    end)
  end
end)

-- make armor rows draggable (to unequip)
for slot, row in pairs(rows) do
  row.InputBegan:Connect(function(io)
    if io.UserInputType == Enum.UserInputType.MouseButton1 then
      beginDragSlot(slot)
    end
  end)
end

-- make hotbar cells draggable (to unbind)
for i = 1, 4 do
  local cell = slotGui[i]
  cell.InputBegan:Connect(function(io)
    if io.UserInputType == Enum.UserInputType.MouseButton1 then
      beginDragHotbar(i)
    end
  end)
end

UIS.InputChanged:Connect(function(io)
  if dragGhost and (io.UserInputType == Enum.UserInputType.MouseMovement) then
    dragGhost.Position = UDim2.fromOffset(io.Position.X + 6, io.Position.Y + 6)
  end
end)
UIS.InputEnded:Connect(function(io)
  if dragging and io.UserInputType == Enum.UserInputType.MouseButton1 then
    endDrag(io.Position.X, io.Position.Y)
  end
end)

-- ---------- open/close ----------
local prevMB = UIS.MouseBehavior
local prevMI = UIS.MouseIconEnabled
local unlockConn: RBXScriptConnection?

local function captureMouse()
  prevMB = UIS.MouseBehavior
  prevMI = UIS.MouseIconEnabled
  UIS.MouseBehavior = Enum.MouseBehavior.Default
  UIS.MouseIconEnabled = true
  if unlockConn then
    unlockConn:Disconnect()
  end
  unlockConn = RunService.RenderStepped:Connect(function()
    if UIS.MouseBehavior ~= Enum.MouseBehavior.Default then
      UIS.MouseBehavior = Enum.MouseBehavior.Default
    end
    if not UIS.MouseIconEnabled then
      UIS.MouseIconEnabled = true
    end
  end)
end
local function releaseMouse()
  if unlockConn then
    unlockConn:Disconnect()
    unlockConn = nil
  end
  UIS.MouseBehavior = prevMB
  UIS.MouseIconEnabled = prevMI
end

local function hideStashIfOpen()
  local pg = me:FindFirstChild 'PlayerGui'
  if not pg then
    return
  end
  local stash = pg:FindFirstChild 'StashUI'
  if stash and stash:IsA 'ScreenGui' then
    stash.Enabled = false
  end
end

local function setOpen(on: boolean)
  if gui.Enabled == on then
    return
  end
  gui.Enabled = on
  if on then
    hideStashIfOpen()
    captureMouse()
    fetch()
  else
    releaseMouse()
  end
end

-- Robust toggle (I)
local function toggleAction(_: string, state: Enum.UserInputState)
  if state == Enum.UserInputState.Begin and not UIS:GetFocusedTextBox() then
    setOpen(not gui.Enabled)
  end
  return Enum.ContextActionResult.Sink
end
CAS:BindAction('TogglePaperDoll', toggleAction, false, Enum.KeyCode.I)

UIS.InputBegan:Connect(function(io, _gpe)
  if UIS:GetFocusedTextBox() then
    return
  end
  if io.KeyCode == Enum.KeyCode.I then
    setOpen(not gui.Enabled)
  end
end)

-- Initial fill
task.defer(fetch)

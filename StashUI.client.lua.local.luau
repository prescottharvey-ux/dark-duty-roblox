--!strict
-- Stash/Inventory UI
-- Adds durability bars per row if the entry includes a UID.
-- Works with either aggregated entries {id, qty} (no bars) or per-instance entries {id, uid} (bars shown).

local Players = game:GetService 'Players'
local RS = game:GetService 'ReplicatedStorage'
local UIS = game:GetService 'UserInputService'
local RunService = game:GetService 'RunService'

local plr = Players.LocalPlayer

-- ===== Durability UI helper =====
local DurUI: any = nil
do
  local Modules = RS:WaitForChild 'Modules'
  local UIFolder = Modules:FindFirstChild 'UI'
  if UIFolder then
    local mod = UIFolder:FindFirstChild 'DurabilityUI'
    if mod and mod:IsA 'ModuleScript' then
      local ok, res = pcall(function()
        return require(mod)
      end)
      if ok then
        DurUI = res
      end
    end
  end
end

-- ===== EventBus (normalize to On/Fire; safe no-ops if missing) =====
local Bus
do
  local ok, mod = pcall(function()
    local EventsFolder = RS:WaitForChild 'Events'
    return require(EventsFolder:WaitForChild 'EventBus')
  end)
  if ok and mod then
    local function resolveOn(a, b, c)
      if type(a) == 'string' then
        return a, b
      else
        return b, c
      end
    end
    local function resolveFire(a, b, c)
      if type(a) == 'string' then
        return a, b
      else
        return b, c
      end
    end

    local onImpl = mod.On or mod.on or mod.subscribe or mod.Subscribe or mod.Connect
    local fireImpl = mod.Fire or mod.fire or mod.publish or mod.Publish or mod.Emit

    local shim = {}

    function shim.On(a, b, c)
      local topic, fn = resolveOn(a, b, c)
      if onImpl then
        if mod.On then
          return mod:On(topic, fn)
        end
        if mod.on then
          return mod:on(topic, fn)
        end
        if mod.subscribe then
          return mod.subscribe(topic, fn)
        end
        if mod.Subscribe then
          return mod.Subscribe(topic, fn)
        end
        if mod.Connect then
          return mod.Connect(topic, fn)
        end
      end
      return { Disconnect = function() end }
    end

    function shim.Fire(a, b, c)
      local topic, payload = resolveFire(a, b, c)
      if fireImpl then
        if mod.Fire then
          mod:Fire(topic, payload)
          return
        end
        if mod.fire then
          mod:fire(topic, payload)
          return
        end
        if mod.publish then
          mod.publish(topic, payload)
          return
        end
        if mod.Publish then
          mod.Publish(topic, payload)
          return
        end
        if mod.Emit then
          mod.Emit(topic, payload)
          return
        end
      end
    end

    function shim.Once(a, b, c)
      local topic, fn = resolveOn(a, b, c)
      local conn
      conn = shim.On(topic, function(...)
        if conn and (conn.Disconnect or conn.disconnect) then
          (conn.Disconnect or conn.disconnect)(conn)
        end
        fn(...)
      end)
      return conn
    end

    Bus = shim
  else
    Bus = {
      On = function(...)
        return { Disconnect = function() end }
      end,
      Fire = function(...) end,
      Once = function(...)
        return { Disconnect = function() end }
      end,
    }
  end
end

-- ===== ItemDB (for names) =====
local ItemDB = require(RS:WaitForChild('Modules'):WaitForChild 'ItemDB')

-- ===== Remotes =====
local Remotes = RS:WaitForChild 'Remotes'
local REF = Remotes:WaitForChild 'RemoteEvent'
local RFF = Remotes:WaitForChild 'RemoteFunction'

local NoticeRE: RemoteEvent = REF:WaitForChild 'InventoryNotice' :: RemoteEvent
local StashWithdraw: RemoteEvent = REF:WaitForChild 'StashWithdraw' :: RemoteEvent

local StashQueryRF: RemoteFunction = RFF:WaitForChild 'StashQuery' :: RemoteFunction
local CarriedQueryRF: RemoteFunction = RFF:WaitForChild 'CarriedQuery' :: RemoteFunction
local EquipRequest: RemoteFunction = RFF:WaitForChild 'EquipRequest' :: RemoteFunction

-- Optional, if you expose instance-level queries:
local CarriedQueryWithUids: RemoteFunction? =
  RFF:FindFirstChild 'CarriedQueryWithUids' :: RemoteFunction?

local WeightUpdateRE: RemoteEvent? = REF:FindFirstChild 'WeightUpdate' :: RemoteEvent?

-- ===== Helpers =====
local function equipSmart(id: string)
  local def = ItemDB.GetItem and ItemDB.GetItem(id) or ItemDB[id]
  if not def then
    return
  end
  if def.equip and def.equip.slot == 'hand' then
    EquipRequest:InvokeServer(id, 'handL')
  else
    local slot = def.equip and def.equip.slot
    if slot == 'trinket' then
      slot = 'trinket1'
    end
    if slot then
      EquipRequest:InvokeServer(id, slot)
    end
  end
end

-- ===== Mouse handling =====
local prevMouseBehavior = UIS.MouseBehavior
local prevMouseIcon = UIS.MouseIconEnabled
local unlockConn: RBXScriptConnection?

-- ===== UI scaffold =====
local gui = Instance.new 'ScreenGui'
gui.Name = 'StashUI'
gui.ResetOnSpawn = false
gui.Enabled = false
gui.DisplayOrder = 50
gui.Parent = plr:WaitForChild 'PlayerGui'

local frame = Instance.new 'Frame'
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.Position = UDim2.fromScale(0.36, 0.52)
frame.Size = UDim2.fromScale(0.36, 0.62)
frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
frame.BackgroundTransparency = 0.06
frame.Parent = gui

local scale = Instance.new('UIScale', frame)
local function rescale()
  local cam = workspace.CurrentCamera
  local v = cam and cam.ViewportSize or Vector2.new(1280, 720)
  scale.Scale = math.clamp(v.Y / 900, 0.8, 1.05)
end
rescale()
workspace:GetPropertyChangedSignal('CurrentCamera'):Connect(rescale)
if workspace.CurrentCamera then
  workspace.CurrentCamera:GetPropertyChangedSignal('ViewportSize'):Connect(rescale)
end

-- Header
local title = Instance.new 'TextLabel'
title.Name = 'Title'
title.Size = UDim2.new(1, -96, 0, 34)
title.Position = UDim2.fromOffset(12, 10)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextScaled = true
title.TextColor3 = Color3.new(1, 1, 1)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = 'Inventory (Carried)'
title.Parent = frame

-- Tabs
local tabs = Instance.new 'Frame'
tabs.Size = UDim2.fromOffset(180, 30)
tabs.Position = UDim2.new(1, -192, 0, 12)
tabs.BackgroundTransparency = 1
tabs.Parent = frame

local function mkTab(text: string, x: number)
  local b = Instance.new 'TextButton'
  b.Size = UDim2.fromOffset(86, 30)
  b.Position = UDim2.fromOffset(x, 0)
  b.Text = text
  b.TextScaled = true
  b.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
  b.BackgroundTransparency = 0.15
  b.Parent = tabs
  return b
end
local tabCarried = mkTab('Carried', 0)
local tabStash = mkTab('Stash', 94)

local closeBtn = Instance.new 'TextButton'
closeBtn.Size = UDim2.fromOffset(28, 28)
closeBtn.Position = UDim2.new(1, -40, 0, 12)
closeBtn.Text = '✕'
closeBtn.TextScaled = true
closeBtn.BackgroundTransparency = 0.15
closeBtn.Parent = frame

-- List area
local scroller = Instance.new 'ScrollingFrame'
scroller.Position = UDim2.fromOffset(12, 50)
scroller.Size = UDim2.new(1, -24, 1, -112)
scroller.CanvasSize = UDim2.new(0, 0, 0, 0)
scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroller.BackgroundTransparency = 0.2
scroller.ScrollBarThickness = 6
scroller.Parent = frame

local uiList = Instance.new 'UIListLayout'
uiList.Padding = UDim.new(0, 6)
uiList.Parent = scroller

-- Weight bar
local weightFrame = Instance.new 'Frame'
weightFrame.Size = UDim2.new(1, -24, 0, 38)
weightFrame.Position = UDim2.new(0, 12, 1, -46)
weightFrame.BackgroundTransparency = 1
weightFrame.Parent = frame

local weightLabel = Instance.new 'TextLabel'
weightLabel.Size = UDim2.new(1, 0, 0, 16)
weightLabel.Position = UDim2.fromOffset(0, 0)
weightLabel.BackgroundTransparency = 1
weightLabel.Font = Enum.Font.Gotham
weightLabel.TextScaled = true
weightLabel.TextColor3 = Color3.fromRGB(230, 230, 230)
weightLabel.TextXAlignment = Enum.TextXAlignment.Left
weightLabel.Text = 'Weight: 0 / 0'
weightLabel.Parent = weightFrame

local barBG = Instance.new 'Frame'
barBG.Size = UDim2.new(1, 0, 0, 14)
barBG.Position = UDim2.fromOffset(0, 20)
barBG.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
barBG.BorderSizePixel = 0
barBG.Parent = weightFrame

local barFill = Instance.new 'Frame'
barFill.Size = UDim2.new(0, 0, 1, 0)
barFill.BackgroundColor3 = Color3.fromRGB(95, 170, 95)
barFill.BorderSizePixel = 0
barFill.Parent = barBG

-- ===== State =====
export type ItemEntry = { id: string, qty: number?, uid: string? }
local currentMode: 'carried' | 'stash' = 'carried'

local function itemName(id: string): string
  local def = (ItemDB.GetItem and ItemDB.GetItem(id)) or ItemDB[id]
  return (def and (def.name or def.displayName)) or id
end

local function setTitleForMode()
  title.Text = currentMode == 'carried' and 'Inventory (Carried)' or 'Inventory (Stash)'
  tabCarried.BackgroundColor3 = currentMode == 'carried' and Color3.fromRGB(80, 80, 80)
    or Color3.fromRGB(40, 40, 40)
  tabStash.BackgroundColor3 = currentMode == 'stash' and Color3.fromRGB(80, 80, 80)
    or Color3.fromRGB(40, 40, 40)
end

local function showEmpty()
  local row = Instance.new 'TextLabel'
  row.Size = UDim2.new(1, -10, 0, 28)
  row.BackgroundTransparency = 1
  row.TextScaled = true
  row.Font = Enum.Font.Gotham
  row.TextColor3 = Color3.fromRGB(200, 200, 200)
  row.Text = '— No items —'
  row.Parent = scroller
end

-- Build one row; binds durability bar if entry.uid exists
local function makeRow(entry: ItemEntry, mode: 'carried' | 'stash'): GuiObject
  if mode == 'carried' then
    local row = Instance.new 'TextButton'
    row.Size = UDim2.new(1, -8, 0, 30)
    row.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    row.BackgroundTransparency = 0.15
    row.Text = ''
    row:SetAttribute('id', entry.id)
    if entry.uid then
      row:SetAttribute('uid', entry.uid)
    end

    local nameL = Instance.new 'TextLabel'
    nameL.Size = UDim2.new(1, -16, 1, 0)
    nameL.Position = UDim2.fromOffset(8, 0)
    nameL.BackgroundTransparency = 1
    nameL.TextXAlignment = Enum.TextXAlignment.Left
    nameL.Font = Enum.Font.Gotham
    nameL.TextScaled = true
    nameL.TextColor3 = Color3.new(1, 1, 1)
    local qty = entry.qty or 1
    nameL.Text = qty > 1 and string.format('%s  ×%d', itemName(entry.id), qty)
      or itemName(entry.id)
    nameL.Parent = row

    -- Bind durability if this is a single instance (uid present)
    if entry.uid then
      DurUI.Bind(row, entry.uid)
    end

    local lastClick = 0
    row.Activated:Connect(function()
      local t = os.clock()
      if t - lastClick < 0.3 then
        equipSmart(entry.id)
      end
      lastClick = t
    end)

    return row
  end

  -- STASH mode: frame + withdraw buttons (usually aggregated, no UIDs)
  local row = Instance.new 'Frame'
  row.Size = UDim2.new(1, -8, 0, 30)
  row.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
  row.BackgroundTransparency = 0.15

  local nameL = Instance.new 'TextLabel'
  nameL.Size = UDim2.new(1, -160, 1, 0)
  nameL.Position = UDim2.fromOffset(8, 0)
  nameL.BackgroundTransparency = 1
  nameL.TextXAlignment = Enum.TextXAlignment.Left
  nameL.Font = Enum.Font.Gotham
  nameL.TextScaled = true
  nameL.TextColor3 = Color3.new(1, 1, 1)
  nameL.Text = string.format('%s  ×%d', itemName(entry.id), entry.qty or 1)
  nameL.Parent = row

  local w1 = Instance.new 'TextButton'
  w1.Size = UDim2.fromOffset(60, 24)
  w1.Position = UDim2.new(1, -140, 0.5, -12)
  w1.Text = 'Take 1'
  w1.TextScaled = true
  w1.BackgroundTransparency = 0.15
  w1.Parent = row
  w1.MouseButton1Click:Connect(function()
    StashWithdraw:FireServer(entry.id, 1)
  end)

  local w5 = Instance.new 'TextButton'
  w5.Size = UDim2.fromOffset(60, 24)
  w5.Position = UDim2.new(1, -70, 0.5, -12)
  w5.Text = 'Take 5'
  w5.TextScaled = true
  w5.BackgroundTransparency = 0.15
  w5.Parent = row
  w5.MouseButton1Click:Connect(function()
    StashWithdraw:FireServer(entry.id, 5)
  end)

  return row
end

local function clearList()
  for _, c in ipairs(scroller:GetChildren()) do
    if c ~= uiList and c:IsA 'GuiObject' then
      c:Destroy()
    end
  end
end

local function refresh(list: { ItemEntry }?, mode: 'carried' | 'stash')
  clearList()
  local arr = list or {}
  if #arr == 0 then
    showEmpty()
    return
  end
  for _, e in ipairs(arr) do
    makeRow(e, mode).Parent = scroller
  end
end

-- ===== Fetch =====
local function fetch(mode: 'carried' | 'stash'): { ItemEntry }
  if mode == 'carried' then
    -- Prefer instance-level query if available (includes uid)
    if CarriedQueryWithUids then
      local ok, list = pcall(function()
        return CarriedQueryWithUids:InvokeServer()
      end)
      if ok and typeof(list) == 'table' then
        return list :: any
      end
    end
    local ok, list = pcall(function()
      return CarriedQueryRF:InvokeServer()
    end)
    if ok and typeof(list) == 'table' then
      return list :: any
    end
  else
    local ok, list = pcall(function()
      return StashQueryRF:InvokeServer()
    end)
    if ok and typeof(list) == 'table' then
      return list :: any
    end
  end
  return {}
end

-- ===== Weight sync =====
local function updateWeightUI()
  local w = (plr:GetAttribute 'CarryWeight' or 0) :: number
  local mx = (plr:GetAttribute 'MaxCarry' or 0) :: number
  weightLabel.Text = string.format('Weight: %.1f / %.1f', w, mx)
  local frac = (mx > 0) and math.clamp(w / mx, 0, 1) or 0
  barFill.Size = UDim2.new(frac, 0, 1, 0)
  barFill.BackgroundColor3 = (frac >= 1.0) and Color3.fromRGB(190, 90, 90)
    or Color3.fromRGB(95, 170, 95)
end

plr:GetAttributeChangedSignal('CarryWeight'):Connect(updateWeightUI)
plr:GetAttributeChangedSignal('MaxCarry'):Connect(updateWeightUI)
if WeightUpdateRE then
  WeightUpdateRE.OnClientEvent:Connect(function(_w: number?)
    updateWeightUI()
  end)
end

-- ===== Open/Close =====
local isOpen = false
local function setTitleForModeAndRefresh()
  setTitleForMode()
  refresh(fetch(currentMode), currentMode)
end

local function show()
  if isOpen then
    return
  end
  isOpen = true
  gui.Enabled = true

  prevMouseBehavior = UIS.MouseBehavior
  prevMouseIcon = UIS.MouseIconEnabled
  UIS.MouseBehavior = Enum.MouseBehavior.Default
  UIS.MouseIconEnabled = true

  unlockConn = RunService.RenderStepped:Connect(function()
    if UIS.MouseBehavior ~= Enum.MouseBehavior.Default then
      UIS.MouseBehavior = Enum.MouseBehavior.Default
    end
    if not UIS.MouseIconEnabled then
      UIS.MouseIconEnabled = true
    end
  end)

  setTitleForModeAndRefresh()
  updateWeightUI()
  Bus:Fire('ui:modal', true)
end

local function hide()
  if not isOpen then
    return
  end
  isOpen = false
  gui.Enabled = false
  if unlockConn then
    unlockConn:Disconnect()
    unlockConn = nil
  end
  UIS.MouseBehavior = prevMouseBehavior
  UIS.MouseIconEnabled = prevMouseIcon
  Bus:Fire('ui:modal', false)
end

local closeBtn = frame:FindFirstChildOfClass 'TextButton' or Instance.new 'TextButton'
closeBtn.MouseButton1Click:Connect(hide)
UIS.InputBegan:Connect(function(io, gp)
  if gp then
    return
  end
  if io.KeyCode == Enum.KeyCode.Escape then
    hide()
  end
end)

tabCarried.MouseButton1Click:Connect(function()
  if currentMode ~= 'carried' then
    currentMode = 'carried'
    setTitleForModeAndRefresh()
  end
end)
tabStash.MouseButton1Click:Connect(function()
  if currentMode ~= 'stash' then
    currentMode = 'stash'
    setTitleForModeAndRefresh()
  end
end)

-- Server pushes
local NoticeRE = NoticeRE
NoticeRE.OnClientEvent:Connect(function(tag: string, data: any)
  if not isOpen then
    return
  end
  if tag == 'carried_refresh' and currentMode == 'carried' then
    refresh((data or {}) :: any, 'carried')
  elseif tag == 'stash_refresh' and currentMode == 'stash' then
    refresh((data or {}) :: any, 'stash')
  elseif tag == 'withdrawn' and data then
    pcall(function()
      game.StarterGui:SetCore('SendNotification', {
        Title = 'Stash',
        Text = string.format('Withdrew %s ×%d', itemName(data.id or 'item'), data.qty or 1),
        Duration = 2,
      })
    end)
  end
end)

-- Bus toggle (K should publish/Fire "stash:toggle")
Bus:On('stash:toggle', function()
  if isOpen then
    hide()
  else
    show()
  end
end)

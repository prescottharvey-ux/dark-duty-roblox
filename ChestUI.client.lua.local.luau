--!strict
local RS = game:GetService 'ReplicatedStorage'
local UIS = game:GetService 'UserInputService'
local PLRS = game:GetService 'Players'
local me = PLRS.LocalPlayer

local ItemDB = require(RS:WaitForChild('Modules'):WaitForChild 'ItemDB')
local ChestOfferRE =
  RS:WaitForChild('Remotes'):WaitForChild('RemoteEvent'):WaitForChild 'ChestOffer'
local ChestTakeRE = RS.Remotes.RemoteEvent:WaitForChild 'ChestTake'
local ChestTakeAllRE = RS.Remotes.RemoteEvent:WaitForChild 'ChestTakeAll'
local ChestNoticeRE = RS.Remotes.RemoteEvent:WaitForChild 'ChestNotice'

local prevMouseBehavior = UIS.MouseBehavior
local prevMouseIcon = UIS.MouseIconEnabled
local currentChestId: string? = nil
local rows: { TextButton } = {}

local rarityColor = {
  Common = Color3.fromRGB(200, 200, 200),
  Uncommon = Color3.fromRGB(120, 200, 120),
  Rare = Color3.fromRGB(120, 160, 255),
  Epic = Color3.fromRGB(180, 120, 255),
  Legendary = Color3.fromRGB(255, 200, 70),
}

local function labelFor(id: string, qty: number): (string, Color3)
  -- Use ItemDB.GetItem when available; fall back to table index.
  local def = (type(ItemDB.GetItem) == 'function') and ItemDB.GetItem(id) or ItemDB[id]
  local name = (def and (def.displayName or def.name)) or id
  local rar = (def and def.rarity) or 'Common'
  local c = rarityColor[rar] or Color3.fromRGB(200, 200, 200)
  return string.format('%s  x%d  (%s)', name, qty, rar), c
end

-- GUI scaffold
local gui = Instance.new 'ScreenGui'
gui.Name = 'ChestGUI'
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 50
gui.Enabled = false
gui.Parent = me:WaitForChild 'PlayerGui'

-- modal blocker to ensure clicks work
local blocker = Instance.new 'TextButton'
blocker.BackgroundTransparency = 0.35
blocker.BackgroundColor3 = Color3.new(0, 0, 0)
blocker.AutoButtonColor = false
blocker.Modal = true
blocker.Text = ''
blocker.Size = UDim2.fromScale(1, 1)
blocker.Parent = gui

local frame = Instance.new 'Frame'
frame.Size = UDim2.fromScale(0.44, 0.46)
frame.Position = UDim2.fromScale(0.5, 0.5)
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
frame.Parent = gui

local title = Instance.new 'TextLabel'
title.Text = 'Chest Loot'
title.Size = UDim2.fromScale(0.6, 0.18)
title.BackgroundTransparency = 1
title.TextScaled = true
title.Font = Enum.Font.GothamBold
title.TextColor3 = Color3.new(1, 1, 1)
title.Parent = frame

-- weight HUD
local capacity = 25.0 -- default; server can override via WeightUpdate
local weightText = Instance.new 'TextLabel'
weightText.Name = 'Weight'
weightText.Size = UDim2.fromScale(0.4, 0.18)
weightText.Position = UDim2.fromScale(0.6, 0) -- right side of header
weightText.BackgroundTransparency = 1
weightText.TextScaled = true
weightText.Font = Enum.Font.Gotham
weightText.TextXAlignment = Enum.TextXAlignment.Right
weightText.TextColor3 = Color3.fromRGB(220, 220, 220)
weightText.Parent = frame

local function setWeight(w: number)
  local pct = math.clamp(w / capacity, 0, 1)
  local r = 200 + math.floor(55 * pct) -- 200→255
  local g = 220 - math.floor(180 * pct) -- 220→40
  weightText.TextColor3 = Color3.fromRGB(r, g, 70)
  weightText.Text = string.format('Weight: %.1f / %.1f', w, capacity)
end

-- listen for server updates (supports optional MaxCarry param)
local WeightUpdateRE = RS.Remotes.RemoteEvent:WaitForChild 'WeightUpdate'
WeightUpdateRE.OnClientEvent:Connect(function(w: number, max: number?)
  if typeof(max) == 'number' and max > 0 then
    capacity = max
  end
  setWeight(w or 0)
end)

local takeAll = Instance.new 'TextButton'
takeAll.Text = 'Take All'
takeAll.Size = UDim2.fromScale(0.2, 0.18)
takeAll.Position = UDim2.fromScale(0.6, 0)
takeAll.BackgroundTransparency = 0.2
takeAll.TextScaled = true
takeAll.Parent = frame

local close = Instance.new 'TextButton'
close.Text = 'Close'
close.Size = UDim2.fromScale(0.2, 0.18)
close.Position = UDim2.fromScale(0.8, 0)
close.BackgroundTransparency = 0.2
close.TextScaled = true
close.Parent = frame

local list = Instance.new 'Frame'
list.Position = UDim2.fromScale(0, 0.2)
list.Size = UDim2.fromScale(1, 0.8)
list.BackgroundTransparency = 1
list.Parent = frame
local layout = Instance.new 'UIListLayout'
layout.Padding = UDim.new(0, 6)
layout.Parent = list

-- notice toast
local toast = Instance.new 'TextLabel'
toast.BackgroundTransparency = 1
toast.TextScaled = true
toast.Font = Enum.Font.GothamSemibold
toast.TextColor3 = Color3.new(1, 1, 1)
toast.Size = UDim2.fromScale(1, 0.08)
toast.Position = UDim2.fromScale(0, 0.92)
toast.Parent = gui
toast.Visible = false

local function showNotice(msg: string)
  toast.Text = msg
  toast.Visible = true
  task.delay(2.0, function()
    toast.Visible = false
  end)
end

local function clearList()
  for _, r in ipairs(rows) do
    r:Destroy()
  end
  table.clear(rows)
end

local function openUI(chestId: string)
  currentChestId = chestId
  gui.Enabled = true
  prevMouseBehavior = UIS.MouseBehavior
  prevMouseIcon = UIS.MouseIconEnabled
  UIS.MouseBehavior = Enum.MouseBehavior.Default
  UIS.MouseIconEnabled = true
  -- start from 0 until server sends actual weight
  setWeight(0)
end

local function closeUI()
  gui.Enabled = false
  clearList()
  currentChestId = nil
  UIS.MouseBehavior = prevMouseBehavior
  UIS.MouseIconEnabled = prevMouseIcon
end

close.MouseButton1Click:Connect(closeUI)
blocker.MouseButton1Click:Connect(closeUI)
takeAll.MouseButton1Click:Connect(function()
  if not currentChestId then
    return
  end
  ChestTakeAllRE:FireServer(currentChestId)
end)
UIS.InputBegan:Connect(function(input, gp)
  if gp then
    return
  end
  if input.KeyCode == Enum.KeyCode.Escape then
    closeUI()
  end
end)

local function addRow(idx: number, id: string, qty: number, chestId: string)
  local label, color = labelFor(id, qty)
  local b = Instance.new 'TextButton'
  b.Size = UDim2.new(1, -12, 0, 38)
  b.Position = UDim2.fromOffset(6, 0)
  b.TextXAlignment = Enum.TextXAlignment.Left
  b.TextScaled = true
  b.Font = Enum.Font.Gotham
  b.TextColor3 = color
  b.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
  b.Text = label
  b.Parent = list
  rows[idx] = b
  b.MouseButton1Click:Connect(function()
    if currentChestId ~= chestId then
      return
    end
    ChestTakeRE:FireServer(chestId, idx)
    b.AutoButtonColor = false
    b.Text = b.Text .. '  — TAKEN'
    b.Active = false
  end)
end

ChestOfferRE.OnClientEvent:Connect(function(chestId: string, payload: any)
  -- taken confirmation (don’t reopen)
  if typeof(payload) == 'table' and payload.takenIndex ~= nil then
    local i = payload.takenIndex :: number
    if rows[i] then
      rows[i].AutoButtonColor = false
      rows[i].Text = rows[i].Text .. '  — TAKEN'
      rows[i].Active = false
    end
    return
  end
  -- new offer
  openUI(chestId)
  clearList()
  for i, entry in ipairs(payload :: { any }) do
    addRow(i, entry.id, entry.qty, chestId)
  end
end)

ChestNoticeRE.OnClientEvent:Connect(function(msg: string)
  showNotice(msg)
end)

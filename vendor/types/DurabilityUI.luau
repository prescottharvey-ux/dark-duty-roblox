-- ReplicatedStorage/Modules/UI/DurabilityUI
--!strict
-- Minimal, resilient durability bar helper.
-- API:
--   Attach(parent, uid, pct?)  -> creates (or reuses) a bar on `parent`, binds it to `uid`
--   Detach(parent)             -> removes the bar from `parent`
--   Set(uid, pct)              -> updates fill for that uid [0..1]
--   Bind(parent, uid, pct?)    -> alias of Attach
--   Unbind(uid)                -> forget mapping (won’t destroy UI directly)
--   DestroyAll()               -> removes all bars created by this module

local DurabilityUI = {}

-- uid -> Fill frame
local barsByUid: { [string]: Frame } = {}
-- slot frame -> uid (to clean up/rebind correctly)
local slotUid: { [Instance]: string } = {}

local function colorFor(p: number): Color3
  -- Green (1.0) -> Yellow (0.5) -> Red (0.0)
  local t = math.clamp(p, 0, 1)
  local r = (t >= 0.5) and (2 - 2 * t) or 1
  local g = (t >= 0.5) and 1 or (2 * t)
  return Color3.fromRGB(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), 0)
end

local function ensureBar(parent: Instance): Frame
  local bar = parent:FindFirstChild 'Durability' :: Frame?
  if not bar then
    bar = Instance.new 'Frame'
    bar.Name = 'Durability'
    bar.AnchorPoint = Vector2.new(0.5, 1)
    bar.Position = UDim2.new(0.5, 0, 1, -2) -- bottom of the slot
    bar.Size = UDim2.new(0.9, 0, 0, 4)
    bar.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    bar.BackgroundTransparency = 0.2
    bar.BorderSizePixel = 0
    bar.ZIndex = 2
    bar.Parent = parent

    local fill = Instance.new 'Frame'
    fill.Name = 'Fill'
    fill.Size = UDim2.new(1, 0, 1, 0) -- start full
    fill.BackgroundColor3 = colorFor(1)
    fill.BorderSizePixel = 0
    fill.ZIndex = 3
    fill.Parent = bar

    local r1 = Instance.new 'UICorner'
    r1.CornerRadius = UDim.new(0, 2)
    r1.Parent = bar
    local r2 = Instance.new 'UICorner'
    r2.CornerRadius = UDim.new(0, 2)
    r2.Parent = fill
  end
  return bar
end

local function fillFrom(parent: Instance): Frame?
  local bar = parent:FindFirstChild 'Durability' :: Frame?
  if not bar then
    return nil
  end
  return bar:FindFirstChild 'Fill' :: Frame?
end

function DurabilityUI.Attach(slotGui: Instance, uid: string, pct: number?)
  local bar = ensureBar(slotGui)
  local fill = bar:FindFirstChild 'Fill' :: Frame
  slotUid[slotGui] = uid
  barsByUid[uid] = fill
  DurabilityUI.Set(uid, pct or 1.0)
end

function DurabilityUI.Bind(slotGui: Instance, uid: string, pct: number?)
  DurabilityUI.Attach(slotGui, uid, pct)
end

function DurabilityUI.Detach(slotGui: Instance)
  -- remove only the visual on this parent; keep uid mapping unless it points here
  local uid = slotUid[slotGui]
  slotUid[slotGui] = nil
  local bar = slotGui:FindFirstChild 'Durability'
  if bar then
    bar:Destroy()
  end
  -- if any uid was pointing to this Fill, forget it
  if uid and barsByUid[uid] and not barsByUid[uid].Parent then
    barsByUid[uid] = nil
  end
end

function DurabilityUI.Unbind(uid: string)
  barsByUid[uid] = nil
end

function DurabilityUI.Set(uid: string, pct: number)
  local fill = barsByUid[uid]
  if fill and fill.Parent then
    local p = math.clamp(pct or 0, 0, 1)
    fill.Size = UDim2.new(p, 0, 1, 0)
    fill.BackgroundColor3 = colorFor(p)
  end
end

function DurabilityUI.DestroyAll()
  for parent, _ in pairs(slotUid) do
    local bar = parent:FindFirstChild 'Durability'
    if bar then
      bar:Destroy()
    end
  end
  table.clear(slotUid)
  table.clear(barsByUid)
end

return DurabilityUI

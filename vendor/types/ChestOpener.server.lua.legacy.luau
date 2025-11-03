--!strict
-- ServerScriptService/World/ChestOpener.server.lua
-- Rolls chest loot using Loot/ItemDB and auto-grants it server-side.
-- Keeps ChestOffer/ChestTake/ChestTakeAll/ChestNotice remotes for future UI.

local RS = game:GetService 'ReplicatedStorage'
local SSS = game:GetService 'ServerScriptService'
local PPS = game:GetService 'ProximityPromptService'
local Workspace = game:GetService 'Workspace'

--======== Require helpers / modules ========--
local function safeRequire(fn: () -> any)
  local ok, mod = pcall(fn)
  if ok then
    return mod
  end
  return nil
end

local Require = safeRequire(function()
  return require(RS:WaitForChild('Modules'):WaitForChild 'Require')
end)
local Loot = (Require and Require.Module and Require.Module 'Loot')
  or safeRequire(function()
    return require(RS.Modules:WaitForChild 'Loot')
  end)
local Bus = (Require and Require.Bus and Require.Bus()) or {} -- tolerate EventBus missing

local Inventory = safeRequire(function()
  return require(SSS:WaitForChild('Inventory'):WaitForChild 'Public')
end)
if not Inventory then
  error '[ChestOpener] Inventory Service missing (ServerScriptService/Inventory/Public)'
end

local Dungeon = safeRequire(function()
  return require(SSS:WaitForChild('Dungeon'):WaitForChild 'Public')
end)

--======== Remotes (ensure they exist) ========--
local Remotes = RS:FindFirstChild 'Remotes' or Instance.new 'Folder'
Remotes.Name = 'Remotes'
Remotes.Parent = RS
local REF = Remotes:FindFirstChild 'RemoteEvent' or Instance.new 'Folder'
REF.Name = 'RemoteEvent'
REF.Parent = Remotes

local function ensureEvent(name: string): RemoteEvent
  local f = REF:FindFirstChild(name)
  if f and f:IsA 'RemoteEvent' then
    return f
  end
  local e = Instance.new 'RemoteEvent'
  e.Name = name
  e.Parent = REF
  return e
end

local ChestOfferRE = ensureEvent 'ChestOffer'
local ChestTakeRE = ensureEvent 'ChestTake'
local ChestTakeAllRE = ensureEvent 'ChestTakeAll'
local ChestNoticeRE = ensureEvent 'ChestNotice'
local WeightUpdateRE = ensureEvent 'WeightUpdate'

--======== Config / tuning ========--
local PROMPT_HOLD = 0.6
local PROMPT_RANGE = 14
local CLICK_RANGE = 24
local MAX_CARRY = 25.0
local ALWAYS_AUTO_GRANT = true

-- Egg: match ItemDB id exactly
local EGG_ITEM_ID = 'MonsterEgg'
local EGG_DROP_CHANCE = 0.0001
local EGG_ZONE_MULT = 1.0

--======== Prompt defaults ========--
PPS.Enabled = true
PPS.MaxPromptsVisible = 8

--======== ItemDB-backed helpers ========--
local function weightOf(id: string): number
  if type(Inventory.weightOf) == 'function' then
    local ok, w = pcall(Inventory.weightOf, id)
    if ok and type(w) == 'number' then
      return w
    end
  end
  if Require and Require.Module then
    local okDB, ItemDB = pcall(Require.Module, 'ItemDB')
    if okDB and ItemDB and type(ItemDB.WeightOf) == 'function' then
      local ok, w = pcall(ItemDB.WeightOf, id)
      if ok and type(w) == 'number' then
        return w
      end
    end
  end
  return 1.0
end

local function currentWeight(p: Player): number
  if type(Inventory.getWeight) == 'function' then
    local ok, w = pcall(Inventory.getWeight, p)
    if ok and type(w) == 'number' then
      return w
    end
  end
  return 0
end

local function canAdd(p: Player, id: string, qty: number): (boolean, number, number)
  local now = currentWeight(p)
  local add = weightOf(id) * qty
  return (now + add) <= MAX_CARRY, now, add
end

local function pingWeight(p: Player)
  local ok, w = pcall(function()
    return type(Inventory.getWeight) == 'function' and Inventory.getWeight(p) or nil
  end)
  if ok and type(w) == 'number' then
    WeightUpdateRE:FireClient(p, w)
  end
end

-- Push a carried snapshot so UI updates immediately
local function pushCarried(plr: Player)
  local rem = RS:FindFirstChild 'Remotes'
  local ref = rem and rem:FindFirstChild 'RemoteEvent'
  local Notice = ref and ref:FindFirstChild 'InventoryNotice'
  if Notice and Notice:IsA 'RemoteEvent' and type(Inventory.getCarriedList) == 'function' then
    local ok, list = pcall(Inventory.getCarriedList, plr)
    if ok then
      (Notice :: RemoteEvent):FireClient(plr, 'carried_refresh', list)
    end
  end
end

--======== Zone detection ========--
local function zoneOf(pos: Vector3): string
  if Dungeon and type(Dungeon.currentZoneOf) == 'function' then
    local ok, z = pcall(Dungeon.currentZoneOf, pos)
    if ok and type(z) == 'number' then
      return 'Z' .. tostring(z)
    end
  end
  return 'Z1'
end

--======== Offer types / state ========--
export type OfferEntry = { id: string, qty: number }
export type Offer = { owner: Player, items: { OfferEntry }, taken: { [number]: boolean } }
local offers: { [string]: Offer } = {}

--======== Loot roll ========--
local function rollOfferFor(pos: Vector3): ({ OfferEntry }, string)
  local zKey = zoneOf(pos)
  local ids: { string }
  if Loot and type(Loot.RollGear) == 'function' then
    ids = Loot.RollGear(zKey, 3)
  else
    ids = { 'dagger', 'torch', 'shield_wood' } -- fallback
  end

  local rolled: { OfferEntry } = {}
  for _, id in ipairs(ids) do
    table.insert(rolled, { id = id, qty = 1 })
  end

  if Loot and type(Loot.Validate) == 'function' and Loot.Validate(EGG_ITEM_ID) then
    if math.random() < (EGG_DROP_CHANCE * EGG_ZONE_MULT) then
      table.insert(rolled, { id = EGG_ITEM_ID, qty = 1 })
    end
  end

  return rolled, zKey
end

--======== Noise emitter ========--
local function emitNoise(pos: Vector3, loud: number)
  local payload = { pos = pos, loudness = loud, source = 'chest_open' }
  if type(Bus.publish) == 'function' then
    Bus.publish('noise.emitted', payload)
  elseif type(Bus.Fire) == 'function' then
    Bus:Fire('noise.emitted', payload)
  end
end

--======== Grant loot ========--
local function inventoryGive(p: Player, id: string, qty: number): boolean
  if type(Inventory.give) == 'function' then
    local ok, res = pcall(Inventory.give, p, id, qty)
    return ok and (res ~= false)
  end
  if type(Inventory.addItem) == 'function' then
    local ok, res = pcall(Inventory.addItem, p, id, qty)
    return ok and (res ~= false)
  end
  return false
end

-- returns: tookIdx, skippedIdx
local function grantChestLoot(p: Player, items: { OfferEntry }): ({ number }, { number })
  local took, skipped = {}, {}
  for i, e in ipairs(items) do
    local can = select(1, canAdd(p, e.id, e.qty))
    if can and inventoryGive(p, e.id, e.qty) then
      table.insert(took, i)
      print(('[ChestOpener] Awarded %s x%d to %s'):format(e.id, e.qty, p.Name))
    else
      table.insert(skipped, i)
      if not can then
        warn(('[ChestOpener] Skipped %s x%d — too heavy for %s'):format(e.id, e.qty, p.Name))
      else
        warn(('[ChestOpener] Failed to award %s x%d to %s'):format(e.id, e.qty, p.Name))
      end
    end
  end
  pingWeight(p)
  return took, skipped
end

--======== Send offer (and auto-grant) ========--
local function sendOfferTo(p: Player, chestModel: Model, how: string)
  local items, zKey = rollOfferFor(chestModel:GetPivot().Position)
  offers[chestModel.Name] = { owner = p, items = items, taken = {} }

  print(
    ('[ChestOpener] %s → offer to %s on %s (%d items, zone %s)'):format(
      how,
      p.Name,
      chestModel.Name,
      #items,
      zKey
    )
  )

  -- Send initial rows (so a future UI can show them)
  ChestOfferRE:FireClient(p, chestModel.Name, items)

  if ALWAYS_AUTO_GRANT then
    local tookIdx, skippedIdx = grantChestLoot(p, items)

    -- Mark each taken row so client can label "TAKEN"
    for _, i in ipairs(tookIdx) do
      offers[chestModel.Name].taken[i] = true
      ChestOfferRE:FireClient(p, chestModel.Name, { takenIndex = i })
      task.wait()
    end

    -- Toasts
    if #tookIdx == 0 and #skippedIdx > 0 then
      ChestNoticeRE:FireClient(p, 'No items taken — you’re at carry limit.')
    elseif #skippedIdx > 0 then
      ChestNoticeRE:FireClient(p, ('Took %d; %d didn’t fit.'):format(#tookIdx, #skippedIdx))
    else
      ChestNoticeRE:FireClient(
        p,
        ('Took %d item%s.'):format(#tookIdx, (#tookIdx == 1) and '' or 's')
      )
    end

    -- Make the carried list update instantly
    pushCarried(p)
  end

  -- Noise
  local root: BasePart? = (
    p.Character and p.Character:FindFirstChild 'HumanoidRootPart'
  ) :: BasePart?
  emitNoise(root and root.Position or chestModel:GetPivot().Position, 0.6)
end

--======== Chest hookup / prompts ========--
local function findMainPart(m: Model): BasePart?
  local h = m:FindFirstChild 'Handle'
  if h and h:IsA 'BasePart' then
    return h
  end
  for _, d in ipairs(m:GetDescendants()) do
    if d:IsA 'BasePart' then
      return d
    end
  end
  return nil
end

local function attachPromptTo(part: BasePart, model: Model)
  local prompt = part:FindFirstChildOfClass 'ProximityPrompt' or Instance.new 'ProximityPrompt'
  prompt.ActionText = 'Open Chest'
  prompt.ObjectText = model.Name
  prompt.HoldDuration = PROMPT_HOLD
  prompt.RequiresLineOfSight = false
  prompt.MaxActivationDistance = PROMPT_RANGE
  prompt.KeyboardKeyCode = Enum.KeyCode.E
  prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
  prompt.Enabled = true
  prompt.Parent = part

  local click = part:FindFirstChildOfClass 'ClickDetector' or Instance.new 'ClickDetector'
  click.MaxActivationDistance = CLICK_RANGE
  click.Parent = part

  local function openFor(plr: Player)
    -- single-use guard per chest
    if model:GetAttribute 'Opened' then
      return
    end
    model:SetAttribute('Opened', true)

    -- distance guard
    local root: BasePart? = (
      plr.Character and plr.Character:FindFirstChild 'HumanoidRootPart'
    ) :: BasePart?
    if root and (root.Position - model:GetPivot().Position).Magnitude > (PROMPT_RANGE + 2) then
      return
    end

    sendOfferTo(plr, model, 'Open')
    prompt.Enabled = false
  end

  prompt.Triggered:Connect(openFor)
  click.MouseClick:Connect(openFor)
end

local function hookChest(m: Model)
  local part = findMainPart(m)
  if not part then
    warn('[ChestOpener] No BasePart in', m:GetFullName())
    return
  end
  print(('[ChestOpener] Hooked %s → %s'):format(m:GetFullName(), part:GetFullName()))
  attachPromptTo(part, m)
end

-- Boot
local CH: Folder = (Workspace:FindFirstChild 'Chests' or Instance.new('Folder', Workspace)) :: any
CH.Name = 'Chests'
for _, c in ipairs(CH:GetChildren()) do
  if c:IsA 'Model' then
    hookChest(c)
  end
end
CH.ChildAdded:Connect(function(c)
  if c:IsA 'Model' then
    task.defer(hookChest, c)
  end
end)

--======== Legacy take / take-all handlers (for when ALWAYS_AUTO_GRANT=false) ========--
local function allTaken(off: Offer): boolean
  for i = 1, #off.items do
    if not off.taken[i] then
      return false
    end
  end
  return true
end

ChestTakeRE.OnServerEvent:Connect(function(plr: Player, chestId: string, idx: number)
  if ALWAYS_AUTO_GRANT then
    return
  end
  local off = offers[chestId]
  if not off or off.owner ~= plr then
    return
  end
  if off.taken[idx] then
    return
  end
  local e = off.items[idx]
  if not e then
    return
  end

  local can, now, add = canAdd(plr, e.id, e.qty)
  if not can then
    ChestNoticeRE:FireClient(
      plr,
      ('Too heavy to take %s (%.1f + %.1f > %.1f)'):format(e.id, now, add, MAX_CARRY)
    )
    return
  end

  if inventoryGive(plr, e.id, e.qty) then
    off.taken[idx] = true
    ChestOfferRE:FireClient(plr, chestId, { takenIndex = idx })
    pingWeight(plr)
    pushCarried(plr)
    if allTaken(off) then
      offers[chestId] = nil
    end
  end
end)

ChestTakeAllRE.OnServerEvent:Connect(function(plr: Player, chestId: string)
  if ALWAYS_AUTO_GRANT then
    return
  end
  local off = offers[chestId]
  if not off or off.owner ~= plr then
    return
  end
  local took: { number } = {}
  local skipped = 0

  for i, entry in ipairs(off.items) do
    if not off.taken[i] then
      if not select(1, canAdd(plr, entry.id, entry.qty)) then
        skipped += 1
      else
        if inventoryGive(plr, entry.id, entry.qty) then
          off.taken[i] = true
          table.insert(took, i)
        end
      end
    end
  end

  for _, i in ipairs(took) do
    ChestOfferRE:FireClient(plr, chestId, { takenIndex = i })
    task.wait()
  end

  if #took == 0 and skipped > 0 then
    ChestNoticeRE:FireClient(plr, 'No items taken — you’re at carry limit.')
  elseif skipped > 0 then
    ChestNoticeRE:FireClient(plr, ('Took %d; %d didn’t fit.'):format(#took, skipped))
  end

  pingWeight(plr)
  pushCarried(plr)
  if allTaken(off) then
    offers[chestId] = nil
  end
end)

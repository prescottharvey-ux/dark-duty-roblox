--!strict
-- ServerScriptService/Durability/DurabilityService.server.lua
-- Server-authoritative durability with weapons/armor/use/burn + repairs.

local Players = game:GetService 'Players'
local RS = game:GetService 'ReplicatedStorage'
local SSS = game:GetService 'ServerScriptService'

-- ==== Remotes scaffold =======================================================
local Remotes = RS:FindFirstChild 'Remotes' or Instance.new('Folder', RS)
Remotes.Name = 'Remotes'
local DurFolder = Remotes:FindFirstChild 'Durability' or Instance.new('Folder', Remotes)
DurFolder.Name = 'Durability'

local DurChanged = DurFolder:FindFirstChild 'Changed' :: RemoteEvent
if not DurChanged then
  DurChanged = Instance.new 'RemoteEvent'
  DurChanged.Name = 'Changed'
  DurChanged.Parent = DurFolder
end

local RepairQuoteRF = DurFolder:FindFirstChild 'RepairQuote' :: RemoteFunction
if not RepairQuoteRF then
  RepairQuoteRF = Instance.new 'RemoteFunction'
  RepairQuoteRF.Name = 'RepairQuote'
  RepairQuoteRF.Parent = DurFolder
end

local RepairAllRF = DurFolder:FindFirstChild 'RepairAllQuote' :: RemoteFunction
if not RepairAllRF then
  RepairAllRF = Instance.new 'RemoteFunction'
  RepairAllRF.Name = 'RepairAllQuote'
  RepairAllRF.Parent = DurFolder
end

local RepairDoRF = DurFolder:FindFirstChild 'RepairDo' :: RemoteFunction
if not RepairDoRF then
  RepairDoRF = Instance.new 'RemoteFunction'
  RepairDoRF.Name = 'RepairDo'
  RepairDoRF.Parent = DurFolder
end

local DurQueryRF = DurFolder:FindFirstChild 'Query' :: RemoteFunction
if not DurQueryRF then
  DurQueryRF = Instance.new 'RemoteFunction'
  DurQueryRF.Name = 'Query'
  DurQueryRF.Parent = DurFolder
end

-- ==== Optional deps ==========================================================
local ItemDB = require(RS:WaitForChild('Modules'):WaitForChild 'ItemDB')

local InventoryPublic: any
pcall(function()
  InventoryPublic = require(SSS:WaitForChild('Inventory'):WaitForChild 'Public')
end)

local Economy: any
pcall(function()
  Economy = require(SSS:WaitForChild 'Economy')
end)

-- ==== Types / tuning =========================================================
type DurState = { cur: number, max: number, zero: boolean? }

local RAR_MULT = { Common = 1.0, Uncommon = 1.15, Rare = 1.4, Epic = 1.85, Legendary = 2.5 }
local REPAIR_FRACTION_OF_NEW = 0.55
local SYNTH_PRICE_BY_RAR = { Common = 60, Uncommon = 120, Rare = 260, Epic = 520, Legendary = 900 }

local DEFAULTS = {
  weapon = { max = 120, costs = { swing = 1, hit = 1 }, breaksWhenZero = false },
  armor = { max = 200, perDamage = 0.08, breaksWhenZero = false },
  burn = { max = 600, burnPerSecond = 1, breaksWhenZero = true },
  use = { max = 20, useCost = 1, breaksWhenZero = true },
}

-- Burners[userId][uid] = { last=os.clock() }
local Burners: { [number]: { [string]: { last: number } } } = {}

-- ==== Helpers ================================================================
local function clamp(x: number, a: number, b: number)
  return math.max(a, math.min(b, x))
end

local function itemOf(id: string)
  local asAny = ItemDB :: any
  if asAny.GetItem then
    return asAny.GetItem(id)
  end
  return asAny.All()[id]
end

local function rarityOf(id: string): string
  local it = itemOf(id)
  return (it and it.rarity) or 'Common'
end

local function priceOfNew(id: string): number
  local it = itemOf(id)
  local p = it and (it.price or it.sellValue)
  if typeof(p) == 'number' then
    return p :: number
  end
  return SYNTH_PRICE_BY_RAR[rarityOf(id)] or 100
end

local function ensureTemplate(id: string, hintType: string?): table
  local it = itemOf(id)
  if it and it.durability then
    -- clone so we never mutate DB data
    return table.clone(it.durability)
  end
  local t = hintType or 'use'
  return table.clone(DEFAULTS[t] or DEFAULTS.use)
end

local function getItemInstance(plr: Player, uid: string)
  if not InventoryPublic then
    return nil
  end
  local ok, inst = pcall(function()
    -- prefer explicit helper
    if InventoryPublic.FindItemByUid then
      return InventoryPublic.FindItemByUid(InventoryPublic, plr, uid)
    end
    -- fallback: some inventories expose FindByUid
    if InventoryPublic.FindByUid then
      return InventoryPublic.FindByUid(InventoryPublic, plr, uid)
    end
    return nil
  end)
  if ok then
    return inst
  end
  return nil
end

local function readState(inst: any, templ: table): DurState
  inst.meta = inst.meta or {}
  local ds = inst.meta.dur
  if not ds then
    ds = { cur = templ.max, max = templ.max, zero = false }
    inst.meta.dur = ds
  end
  if not ds.max then
    ds.max = templ.max
  end
  if ds.cur > ds.max then
    ds.cur = ds.max
  end
  ds.zero = (ds.cur <= 0)
  return ds
end

local function writeAndReplicate(plr: Player, inst: any, ds: DurState, reason: string)
  inst.meta.dur = ds
  DurChanged:FireClient(
    plr,
    { uid = inst.uid, id = inst.id, cur = ds.cur, max = ds.max, zero = ds.zero, reason = reason }
  )
end

-- ==== Core service ===========================================================
local Service = {}

function Service.Degrade(
  plr: Player,
  uid: string,
  amount: number,
  hintType: string?,
  reason: string?
): boolean
  if not plr or not uid or not amount or amount <= 0 then
    return false
  end
  local inst = getItemInstance(plr, uid)
  if not inst then
    return false
  end
  local templ = ensureTemplate(inst.id, hintType)
  local ds = readState(inst, templ)
  if ds.zero then
    return true
  end

  ds.cur = clamp(ds.cur - amount, 0, ds.max)
  ds.zero = (ds.cur <= 0)
  writeAndReplicate(plr, inst, ds, reason or 'degrade')
  if ds.zero and templ.breaksWhenZero and InventoryPublic and InventoryPublic.Unequip then
    pcall(function()
      InventoryPublic.Unequip(InventoryPublic, plr, uid)
    end)
  end
  return true
end

function Service.OnWeaponSwing(plr: Player, uid: string, id: string)
  local t = ensureTemplate(id, 'weapon')
  local cost = (t.costs and t.costs.swing) or 1
  return Service.Degrade(plr, uid, cost, 'weapon', 'swing')
end

function Service.OnWeaponHit(plr: Player, uid: string, id: string)
  local t = ensureTemplate(id, 'weapon')
  local cost = (t.costs and t.costs.hit) or 1
  return Service.Degrade(plr, uid, cost, 'weapon', 'hit')
end

function Service.OnItemUse(plr: Player, uid: string, id: string)
  local t = ensureTemplate(id, 'use')
  local cost = t.useCost or 1
  return Service.Degrade(plr, uid, cost, 'use', 'use')
end

function Service.OnDamageTaken(plr: Player, dmg: number, equippedArmorUids: { string }?)
  if dmg <= 0 then
    return
  end
  local armorUids = equippedArmorUids
  if not armorUids and InventoryPublic and InventoryPublic.GetEquippedByType then
    local ok, arr = pcall(InventoryPublic.GetEquippedByType, InventoryPublic, plr, 'armor')
    armorUids = (ok and arr) or {}
  end
  armorUids = armorUids or {}
  for _, uid in ipairs(armorUids) do
    local inst = getItemInstance(plr, uid)
    if inst then
      local t = ensureTemplate(inst.id, 'armor')
      local wear = math.max(1, math.floor(dmg * (t.perDamage or 0.08)))
      Service.Degrade(plr, uid, wear, 'armor', 'damage')
    end
  end
end

function Service.SetLit(plr: Player, uid: string, id: string, isLit: boolean)
  local u = plr.UserId
  Burners[u] = Burners[u] or {}
  if not isLit then
    Burners[u][uid] = nil
    return
  end
  Burners[u][uid] = { last = os.clock() }
end

function Service.Get(plr: Player, uid: string): DurState?
  local inst = getItemInstance(plr, uid)
  if not inst then
    return nil
  end
  local t = ensureTemplate(inst.id, nil)
  return readState(inst, t)
end

-- ==== Repairs ================================================================
local function rarityMult(id: string): number
  return RAR_MULT[rarityOf(id)] or 1.0
end

local function repairQuoteFor(plr: Player, uid: string)
  local inst = getItemInstance(plr, uid)
  if not inst then
    return nil
  end
  local t = ensureTemplate(inst.id, nil)
  local ds = readState(inst, t)
  if ds.cur >= ds.max then
    return { uid = uid, id = inst.id, cur = ds.cur, max = ds.max, missing = 0, cost = 0 }
  end
  local newPrice = priceOfNew(inst.id)
  local missing = ds.max - ds.cur
  local baseCost = (missing / ds.max) * (newPrice * REPAIR_FRACTION_OF_NEW) * rarityMult(inst.id)
  local cost = math.ceil(baseCost)
  local cap = math.floor(newPrice * 0.8)
  if cost > cap then
    cost = cap
  end
  return { uid = uid, id = inst.id, cur = ds.cur, max = ds.max, missing = missing, cost = cost }
end

local function debit(plr: Player, amount: number): boolean
  if amount <= 0 then
    return true
  end
  if Economy and Economy.TryDebit then
    return Economy:TryDebit(plr, amount, 'Repair') == true
  end
  local ls = plr:FindFirstChild 'leaderstats'
  local coins = ls and ls:FindFirstChild 'Coins'
  if coins and coins.Value >= amount then
    coins.Value -= amount
    return true
  end
  return false
end

local function doRepair(plr: Player, uid: string): boolean
  local q = repairQuoteFor(plr, uid)
  if not q or q.cost <= 0 then
    return q ~= nil
  end
  if not debit(plr, q.cost) then
    return false
  end
  local inst = getItemInstance(plr, uid)
  if not inst then
    return false
  end
  local t = ensureTemplate(inst.id, nil)
  local ds = readState(inst, t)
  ds.cur = ds.max
  ds.zero = false
  writeAndReplicate(plr, inst, ds, 'repair')
  return true
end

-- === Expose for Public.lua (no remotes) =====================================
local S: any = Service
S._repairQuoteFor = repairQuoteFor

function S._repairAllFor(plr: Player)
  local out = {}
  if InventoryPublic and InventoryPublic.ListAllItems then
    local ok, items = pcall(InventoryPublic.ListAllItems, InventoryPublic, plr)
    if ok and items then
      for _, inst in ipairs(items) do
        local q = repairQuoteFor(plr, inst.uid)
        if q and q.cost > 0 then
          table.insert(out, q)
        end
      end
    end
  end
  return out
end

function S._repairDo(plr: Player, uidOrAll: any)
  if uidOrAll == 'ALL' then
    local all = S._repairAllFor(plr) :: { any }
    local spent = 0
    for _, q in ipairs(all) do
      if doRepair(plr, q.uid) then
        spent += q.cost
      end
    end
    return { ok = true, spent = spent }
  else
    return { ok = doRepair(plr, tostring(uidOrAll)) }
  end
end

-- ==== Heartbeat for burn items ==============================================
task.spawn(function()
  while true do
    task.wait(1)
    local now = os.clock()
    for _, plr in ipairs(Players:GetPlayers()) do
      local bag = Burners[plr.UserId]
      if bag then
        for uid, rec in pairs(bag) do
          local inst = getItemInstance(plr, uid)
          if inst then
            local t = ensureTemplate(inst.id, 'burn')
            local elapsed = math.max(0, now - (rec.last or now))
            rec.last = now
            local burn = math.max(1, math.floor(elapsed * (t.burnPerSecond or 1)))
            Service.Degrade(plr, uid, burn, 'burn', 'burn')
          end
        end
      end
    end
  end
end)

-- ==== Fallback: wear armor on HealthChanged =================================
local function watchChar(plr: Player, char: Model)
  local hum = char:FindFirstChildOfClass 'Humanoid'
  if not hum then
    return
  end
  local last = hum.Health
  hum.HealthChanged:Connect(function(h)
    if h < last then
      Service.OnDamageTaken(plr, last - h)
    end
    last = h
  end)
end
Players.PlayerAdded:Connect(function(plr)
  plr.CharacterAdded:Connect(function(c)
    watchChar(plr, c)
  end)
end)
for _, p in ipairs(Players:GetPlayers()) do
  if p.Character then
    watchChar(p, p.Character)
  end
end

-- ==== Remotes handlers =======================================================
DurQueryRF.OnServerInvoke = function(plr: Player, uid: string)
  local inst = getItemInstance(plr, uid)
  if not inst then
    return nil
  end
  local ds = Service.Get(plr, uid)
  return ds and { uid = uid, id = inst.id, cur = ds.cur, max = ds.max, zero = ds.zero } or nil
end

RepairQuoteRF.OnServerInvoke = function(plr: Player, uid: string)
  return repairQuoteFor(plr, uid)
end

RepairAllRF.OnServerInvoke = function(plr: Player)
  return S._repairAllFor(plr)
end

RepairDoRF.OnServerInvoke = function(plr: Player, uidOrAll: any)
  return S._repairDo(plr, uidOrAll)
end

return Service

-- ServerScriptService/Combat/NPCDamage.server.lua
--!strict

local RS = game:GetService 'ReplicatedStorage'
local Debris = game:GetService 'Debris'
local RunService = game:GetService 'RunService'
local Players = game:GetService 'Players'
local Workspace = game:GetService 'Workspace'
local SSS = game:GetService 'ServerScriptService'
local CS = game:GetService 'CollectionService'

-- ========= tuning =========
local DROP_AFTER_DIED_DELAY = 0.10
local WATCHDOG_DELAY = 0.35
local POST_DROP_DESPAWN = 0.35
local DIED_FALLBACK_WINDOW = 1.00
local STICKY_WINDOW = 1.5
local ASSIST_RADIUS = 35
local HIT_FUSE = 0.18

-- ========= logging =========
local DEBUG = true
local function log(...)
  if DEBUG then
    print('[NPCDamage]', ...)
  end
end
local function warnf(...)
  warn('[NPCDamage]', ...)
end
log 'Booting…'

-- ========= EventBus (original behavior; ok if present) =========
local okBus, Bus = pcall(function()
  local Events = RS:WaitForChild 'Events'
  return require(Events:WaitForChild 'EventBus')
end)
if not okBus then
  warn '[NPCDamage] EventBus not found; combat.hit subscription will be inactive.'
  Bus = nil
end
local function busOn(topic: string, fn: (...any) -> ()): RBXScriptConnection?
  if not Bus then
    return nil
  end
  if typeof(Bus.On) == 'function' then
    return Bus.On(topic, fn)
  end
  if typeof(Bus.Connect) == 'function' then
    return Bus.Connect(topic, fn)
  end
  if typeof(Bus.subscribe) == 'function' then
    return Bus.subscribe(topic, fn)
  end
  if typeof(Bus.Subscribe) == 'function' then
    return Bus.Subscribe(topic, fn)
  end
  warn '[NPCDamage] EventBus has no known subscribe method.'
  return nil
end

-- ========= ItemDB (safe), Inventory (Public API) =========
local okItemDB, ItemDB = pcall(function()
  return require(RS:WaitForChild('Modules'):WaitForChild 'ItemDB')
end)

local Inventory = require(SSS:WaitForChild('Inventory'):WaitForChild 'Public')

local function carriedListFor(plr: Player): { { id: string, qty: number } }
  if typeof((Inventory :: any).getCarriedList) == 'function' then
    return (Inventory :: any).getCarriedList(plr)
  end
  local list = {}
  if typeof((Inventory :: any).getCarried) == 'function' then
    local map = (Inventory :: any).getCarried(plr)
    for id, qty in pairs(map) do
      table.insert(list, { id = id, qty = qty })
    end
    table.sort(list, function(a, b)
      return a.id < b.id
    end)
  end
  return list
end

-- ===== immediate UI sync helpers (carried + weight) =====
local Remotes
do
  Remotes = RS:FindFirstChild 'Remotes' or Instance.new 'Folder'
  Remotes.Name = 'Remotes'
  Remotes.Parent = RS
  local REF = Remotes:FindFirstChild 'RemoteEvent' or Instance.new 'Folder'
  REF.Name = 'RemoteEvent'
  REF.Parent = Remotes
  local function ensureEvent(n: string): RemoteEvent
    local f = REF:FindFirstChild(n)
    if f and f:IsA 'RemoteEvent' then
      return f
    end
    local e = Instance.new 'RemoteEvent'
    e.Name = n
    e.Parent = REF
    return e
  end
  ensureEvent 'InventoryNotice' -- make sure it exists once
  ensureEvent 'WeightUpdate'
end

local function pushCarried(plr: Player)
  local REF = Remotes:FindFirstChild 'RemoteEvent'
  local Notice = REF and REF:FindFirstChild 'InventoryNotice'
  if Notice and Notice:IsA 'RemoteEvent' then
    Notice:FireClient(plr, 'carried_refresh', carriedListFor(plr))
  end
end

local function pingWeight(plr: Player)
  if typeof((Inventory :: any).getWeight) == 'function' then
    local ok, w = pcall((Inventory :: any).getWeight, plr)
    if ok and type(w) == 'number' then
      local REF = Remotes:FindFirstChild 'RemoteEvent'
      local WU = REF and REF:FindFirstChild 'WeightUpdate'
      if WU and WU:IsA 'RemoteEvent' then
        (WU :: RemoteEvent):FireClient(plr, w)
      end
    end
  end
end

-- ========= helpers =========
local function getAllItemDefs(): { [string]: any }
  if not okItemDB then
    return {}
  end
  for _, api in ipairs { 'All', 'GetAll' } do
    local f = (ItemDB :: any)[api]
    if typeof(f) == 'function' then
      local ok, t = pcall(f)
      if ok and type(t) == 'table' then
        return t
      end
    end
  end
  for _, key in ipairs { 'Data', 'Items', 'Defs' } do
    local v = (ItemDB :: any)[key]
    if type(v) == 'table' then
      return v
    end
  end
  return {}
end

local function getRoot(m: Model): BasePart?
  return m.PrimaryPart or m:FindFirstChild 'HumanoidRootPart' or m:FindFirstChildWhichIsA 'BasePart'
end

local function isPlayerCharacter(m: Model): boolean
  return Players:GetPlayerFromCharacter(m) ~= nil
end

local function isDamageableNPC(m: Model): boolean
  return (
    m
    and m:IsA 'Model'
    and not isPlayerCharacter(m)
    and m:FindFirstChildOfClass 'Humanoid' ~= nil
  )
end

local function resolveHumanoidTarget(inst: Instance?): (Model?, Humanoid?)
  if not inst then
    return nil, nil
  end
  local model: Model? = inst:IsA 'Model' and inst or inst:FindFirstAncestorOfClass 'Model'
  if not model or not isDamageableNPC(model) then
    return nil, nil
  end
  local hum = model:FindFirstChildOfClass 'Humanoid'
  if not hum or hum.Health <= 0 then
    return nil, nil
  end
  return model, hum
end

local function getPosition(inst: Instance?): Vector3?
  if not inst then
    return nil
  end
  if inst:IsA 'BasePart' then
    return inst.Position
  end
  local m = inst:IsA 'Model' and inst or inst:FindFirstAncestorOfClass 'Model'
  if m then
    local pp = m.PrimaryPart or m:FindFirstChildWhichIsA 'BasePart'
    return pp and pp.Position or nil
  end
  return nil
end

local function nearestNPC(from: Vector3, radius: number): (Model?, Humanoid?)
  local bestDist, bestModel, bestHum = math.huge, nil, nil
  for _, d in ipairs(Workspace:GetDescendants()) do
    if d:IsA 'Model' and isDamageableNPC(d) then
      local hum = d:FindFirstChildOfClass 'Humanoid'
      if hum and hum.Health > 0 then
        local pp = d.PrimaryPart or d:FindFirstChildWhichIsA 'BasePart'
        if pp then
          local dist = (pp.Position - from).Magnitude
          if dist < radius and dist < bestDist then
            bestDist, bestModel, bestHum = dist, d, hum
          end
        end
      end
    end
  end
  return bestModel, bestHum
end

local function hitFlash(m: Model)
  for _, p in ipairs(m:GetDescendants()) do
    if p:IsA 'BasePart' then
      local old = p.Color
      p.Color = Color3.fromRGB(255, 120, 120)
      task.delay(0.08, function()
        if p and p.Parent then
          p.Color = old
        end
      end)
    end
  end
end

local function stagger(hum: Humanoid?)
  if not hum or hum.Health <= 0 then
    return
  end
  local old = hum.WalkSpeed
  hum.WalkSpeed = math.max(4, old * 0.4)
  task.delay(0.15, function()
    if hum and hum.Parent then
      hum.WalkSpeed = old
    end
  end)
end

-- ========= loot service detection (public beacon + fallbacks) =========
local function lootServicePresentNow(): boolean
  if SSS:GetAttribute 'LootOnDeathPresent' then
    return true
  end
  local f = SSS:FindFirstChild 'Services'
  if f and f:FindFirstChild 'LootOnDeath' then
    return true
  end
  for _, d in ipairs(SSS:GetDescendants()) do
    if (d:IsA 'Script' or d:IsA 'ModuleScript') and tostring(d.Name):find 'LootOnDeath' then
      return true
    end
  end
  return false
end

local LOOT_SERVICE_PRESENT = lootServicePresentNow()
local FORCE_INTERNAL_DROPS = script:GetAttribute 'UseInternalDrops' == true
local ENABLE_INTERNAL_DROPS = FORCE_INTERNAL_DROPS or not LOOT_SERVICE_PRESENT
log('Loot service present =', LOOT_SERVICE_PRESENT, 'Internal drops =', ENABLE_INTERNAL_DROPS)

task.defer(function()
  task.wait(0.5)
  if not LOOT_SERVICE_PRESENT and lootServicePresentNow() and not FORCE_INTERNAL_DROPS then
    LOOT_SERVICE_PRESENT = true
    ENABLE_INTERNAL_DROPS = false
    log 'Detected LootOnDeath post-boot; disabling internal drops'
  end
end)

-- ========= internal dropper =========
local function pickDrop(): { { id: string, qty: number } }
  local defs = getAllItemDefs()
  local function anyBy(r: string): string?
    local pool = {}
    for id, def in pairs(defs) do
      if type(def) == 'table' and ((def.rarity == r) or (def.Rarity == r)) then
        table.insert(pool, id)
      end
    end
    return (#pool > 0) and pool[math.random(1, #pool)] or nil
  end
  local out = {}
  table.insert(out, { id = anyBy 'Common' or 'coin_pouch', qty = 1 })
  if math.random() < 0.35 then
    table.insert(out, { id = anyBy 'Uncommon' or 'bandage', qty = 1 })
  end
  return out
end

local function safeDisplayName(id: string): string
  if okItemDB and typeof(ItemDB.DisplayName) == 'function' then
    local ok, dn = pcall(ItemDB.DisplayName, id)
    if ok and typeof(dn) == 'string' then
      return dn
    end
  end
  return id
end

-- force=true bypasses ENABLE_INTERNAL_DROPS (used by watchdog failover)
local function spawnPickup(pos: Vector3, items: { { id: string, qty: number } }, force: boolean?)
  if not (ENABLE_INTERNAL_DROPS or force) then
    return
  end
  log('Spawning pickup at', pos)
  local part = Instance.new 'Part'
  part.Name = 'Pickup'
  part.Size = Vector3.new(1.25, 1.25, 1.25)
  part.Shape = Enum.PartType.Ball
  part.Material = Enum.Material.Neon
  part.Color = Color3.fromRGB(255, 220, 80)
  part.Anchored = true
  part.CanCollide = false
  part.Position = pos + Vector3.new(0, 1.2, 0)
  part.Parent = Workspace

  local light = Instance.new 'PointLight'
  light.Range = 18
  light.Brightness = 3
  light.Parent = part

  local prompt = Instance.new 'ProximityPrompt'
  prompt.ActionText = 'Take Loot'
  prompt.ObjectText = (#items == 1) and safeDisplayName(items[1].id) or 'Loot'
  prompt.HoldDuration = 0.4
  prompt.RequiresLineOfSight = false
  prompt.MaxActivationDistance = 12
  prompt.Parent = part

  prompt.Triggered:Connect(function(plr: Player)
    log('Pickup taken by', plr.Name)

    -- Give items
    if typeof((Inventory :: any).Give) == 'function' then
      for _, e in ipairs(items) do
        if e and e.id and e.qty then
          (Inventory :: any).Give(plr, e.id, e.qty)
        end
      end
    elseif typeof((Inventory :: any).addItem) == 'function' then
      for _, e in ipairs(items) do
        if e and e.id and e.qty then
          (Inventory :: any).addItem(plr, e.id, e.qty)
        end
      end
    end

    -- Immediate client updates (carried + weight)
    pushCarried(plr)
    pingWeight(plr)

    part:Destroy()
  end)

  Debris:AddItem(part, 90)
end

-- ========= death wiring & watchdog =========
local wired: { [Humanoid]: boolean } = {}
local lastPos: { [Humanoid]: Vector3 } = {}
local dropped: { [Humanoid]: boolean } = {} -- internal drop performed
local watchdogArmed: { [Humanoid]: boolean } = {}

local function computeBestPos(model: Model, hum: Humanoid, atPos: Vector3?): Vector3
  local root = (model and model.Parent) and getRoot(model) or nil
  return atPos
    or (root and root.Position)
    or lastPos[hum]
    or (model and model:GetPivot().Position)
    or Vector3.new(0, 5, 0)
end

local function doInternalDrop(model: Model, hum: Humanoid, atPos: Vector3?, force: boolean?)
  if dropped[hum] then
    return
  end
  dropped[hum] = true
  local pos = computeBestPos(model, hum, atPos)
  spawnPickup(pos, pickDrop(), force)
  if not force then
    task.delay(POST_DROP_DESPAWN, function()
      if model and model.Parent then
        model:Destroy()
      end
    end)
  end
end

local function wireDeath(model: Model, hum: Humanoid)
  if wired[hum] then
    return
  end
  wired[hum] = true
  log('Wiring Died for', model:GetFullName())

  -- Track last known position
  local trackConn: RBXScriptConnection?
  trackConn = RunService.Heartbeat:Connect(function()
    if not hum.Parent then
      if trackConn then
        trackConn:Disconnect()
      end
      return
    end
    local r = getRoot(model)
    if r then
      lastPos[hum] = r.Position
    end
  end)

  hum.Died:Connect(function()
    if trackConn then
      trackConn:Disconnect()
    end

    if ENABLE_INTERNAL_DROPS then
      task.delay(DROP_AFTER_DIED_DELAY, function()
        doInternalDrop(model, hum, nil, false)
      end)
    end

    if not watchdogArmed[hum] then
      watchdogArmed[hum] = true
      task.delay(WATCHDOG_DELAY, function()
        if model and not model:GetAttribute 'LootDone' and not dropped[hum] then
          warn '[NPCDamage] Loot service missed this death; failing over'
          model:SetAttribute('LootDone', true)
          doInternalDrop(model, hum, nil, true)
        end
      end)
    end
  end)

  model.AncestryChanged:Connect(function(_, parent)
    if parent == nil then
      if not (model:GetAttribute 'LootDone') and not dropped[hum] then
        warn '[NPCDamage] Model removed before Died; enforcing drop'
        model:SetAttribute('LootDone', true)
        doInternalDrop(model, hum, lastPos[hum], true)
      end
    end
  end)
end

-- Hook all NPC humanoids
local function considerHumanoid(hum: Humanoid)
  local model = hum.Parent
  if not (model and model:IsA 'Model') then
    return
  end
  if isPlayerCharacter(model) then
    return
  end
  if not isDamageableNPC(model) then
    return
  end

  if not CS:HasTag(model, 'Enemy') then
    CS:AddTag(model, 'Enemy')
  end
  if model:GetAttribute 'Zone' == nil then
    model:SetAttribute('Zone', 'Z1')
  end

  wireDeath(model, hum)
  log('Auto-wired Died for', model:GetFullName())
end

for _, d in ipairs(Workspace:GetDescendants()) do
  if d:IsA 'Humanoid' then
    considerHumanoid(d)
  end
end
Workspace.DescendantAdded:Connect(function(inst)
  if inst:IsA 'Humanoid' then
    considerHumanoid(inst)
  end
end)

-- ========= Bus-driven hit handling =========
log 'Subscribing to combat.hit …'
if Bus then
  local lastForAttacker: { [number]: { model: Model, hum: Humanoid, t: number } } = {}
  local lastHitAtByAttacker: { [number]: number } = {}

  busOn('combat.hit', function(e: any)
    -- Normalize
    local damage: number?
    local target: Instance?
    local attacker: Player?
    if type(e) == 'table' then
      damage = tonumber(e.damage) or tonumber(e.dmg)
      target = e.target
      attacker = e.attacker
    else
      damage = tonumber(e)
    end
    if damage then
      log('hit event damage =', damage)
    end

    -- Resolve target
    local model, hum = resolveHumanoidTarget(target)

    -- Sticky last target
    if not (model and hum) and attacker then
      local rec = lastForAttacker[attacker.UserId]
      if rec and (os.clock() - rec.t) <= STICKY_WINDOW and rec.hum and rec.hum.Health > 0 then
        model, hum = rec.model, rec.hum
      end
    end

    -- Nearest assist
    if not (model and hum) then
      local refPos: Vector3? = getPosition(target)
      if not refPos and attacker and attacker.Character then
        local hrp = attacker.Character:FindFirstChild 'HumanoidRootPart'
        refPos = hrp and hrp.Position or nil
      end
      if refPos then
        model, hum = nearestNPC(refPos, ASSIST_RADIUS)
      end
    end

    if not (model and hum) then
      warnf 'No NPC resolved for hit'
      return
    end

    -- Remember last good target
    if attacker then
      lastForAttacker[attacker.UserId] = { model = model, hum = hum, t = os.clock() }
    end

    -- Per-attacker fuse
    local attackerId = attacker and attacker.UserId or 0
    if attackerId ~= 0 then
      local now = os.clock()
      local prev = lastHitAtByAttacker[attackerId]
      if prev and (now - prev) < HIT_FUSE then
        log('Fuse: skip extra hit for attacker', attackerId)
        return
      end
      lastHitAtByAttacker[attackerId] = now
    end

    -- Killer attribution & helpful public fields
    if attacker then
      model:SetAttribute('LastHitUserId', attacker.UserId)
      model:SetAttribute('LastHitAt', os.time())
      local creator = hum:FindFirstChild 'creator'
      if not creator then
        creator = Instance.new 'ObjectValue'
        creator.Name = 'creator'
        creator.Parent = hum
      end
      creator.Value = attacker
    end
    if not CS:HasTag(model, 'Enemy') then
      CS:AddTag(model, 'Enemy')
    end
    if model:GetAttribute 'Zone' == nil then
      model:SetAttribute('Zone', 'Z1')
    end

    -- Ensure death is wired
    wireDeath(model, hum)

    -- VFX + damage
    hitFlash(model)
    stagger(hum)

    local dmg = (damage and damage > 0) and damage or 10
    local wouldKill = (hum.Health - dmg) <= 0

    local hitPos = getPosition(target)
    local attackerPos
    if attacker and attacker.Character then
      local hrp = attacker.Character:FindFirstChild 'HumanoidRootPart'
      attackerPos = hrp and hrp.Position or nil
    end
    local root = getRoot(model)
    local fallbackPos = hitPos or (root and root.Position) or attackerPos

    log(
      'Applying damage',
      dmg,
      'to',
      model:GetFullName(),
      'HP=',
      hum.Health,
      '->',
      math.max(0, hum.Health - dmg)
    )
    hum:TakeDamage(dmg)
    print('[NPCDamage] post-HP =', hum.Health)

    -- Internal-mode safety fallback
    if ENABLE_INTERNAL_DROPS and wouldKill then
      task.spawn(function()
        local t0 = os.clock()
        while os.clock() - t0 < DIED_FALLBACK_WINDOW do
          if dropped[hum] then
            return
          end
          if hum.Health <= 0 then
            return
          end
          RunService.Heartbeat:Wait()
        end
        if hum.Health <= 0 and not dropped[hum] then
          doInternalDrop(model, hum, fallbackPos, false)
        end
      end)
    end
  end)
end

log 'Ready.'

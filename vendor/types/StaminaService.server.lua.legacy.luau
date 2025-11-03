--!strict
-- Server authoritative stamina
-- Phase-0 hardened + Sneak + Noise + Telemetry + Intent fuse + Encumbrance
-- + Encumbrance speed penalties for Sprint/Sneak/Walk + Debug attrs
-- + Per-weapon swing cost from ItemDB weight (with overrides)
-- + Jump stamina cost (once per takeoff, encumbrance-aware)
-- + Exhaustion penalty window (0 stamina ⇒ 4s: half-speed, no jump/spend; regen only if sneaking)

local Players = game:GetService 'Players'
local RunService = game:GetService 'RunService'
local RS = game:GetService 'ReplicatedStorage'

-- ========= Remotes (create up-front so clients never hang) =========
local Remotes = RS:FindFirstChild 'Remotes' or Instance.new('Folder', RS)
Remotes.Name = 'Remotes'
local StamFolder = Remotes:FindFirstChild 'Stamina' or Instance.new('Folder', Remotes)
StamFolder.Name = 'Stamina'
local IntentsRE = StamFolder:FindFirstChild 'Intents' or Instance.new('RemoteEvent', StamFolder)
IntentsRE.Name = 'Intents'
local NoticeRE = StamFolder:FindFirstChild 'Notice' or Instance.new('RemoteEvent', StamFolder)
NoticeRE.Name = 'Notice'

print '[StaminaService] Boot: remotes ready at ReplicatedStorage/Remotes/Stamina'

-- ========= Defaults (used if config missing) =========
local DEFAULT = {
  Max = 100,
  TickRate = 10,
  RegenDelay = 0.6,

  Costs = {
    SprintPerSec = 15,
    BlockPerSec = 3,
    SwingFlat = 12,
    JumpFlat = 8, -- stamina per jump
    Weapon = {}, -- e.g. { dagger=6, longsword=16 }
    WeightToSwing = { Base = 6, PerUnit = 2.0, Min = 5, Max = 30 },
  },

  Regen = { Walk = 2, Idle = 3, Sneak = 8 },

  Thresholds = {
    MinToSprint = 10,
    MinToSwing = 8,
    MinToBlock = 5,
    MinToJump = 6,
  },

  Intents = { Sprinting = 'Sprinting', Sneaking = 'Sneaking', Blocking = 'Blocking' },

  UseServerSprintSpeed = true,
  Speeds = { Walk = 16, Sneak = 11, Sprint = 22 },

  Noise = { Idle = 0.20, Walk = 1.00, Sneak = 0.40, Sprint = 1.70 },

  Debug = {
    PrintTelemetryEvery = 0,
    PrintSpeedChanges = false,
    JumpFuse = 0.20, -- fuse to avoid double-billing per jump
  },

  Encumbrance = {
    Enabled = true,
    WeightAttr = 'CarryWeight',
    MaxCarryAttr = 'MaxCarry',
    MaxCarry = 40,

    DrainScale = 0.50,
    RegenScale = 0.40,
    MinRegenScalar = 0.25,
    MaxDrainScalar = 2.00,

    Apply = {
      Sprint = true,
      Block = true,
      Swing = false, -- leave swings unscaled by default (readability)
      Jump = true,
    },

    -- Encumbrance speed penalties (scaled by carried ratio)
    SpeedPenaltySprint = 0.25,
    SpeedPenaltySneak = 0.15,
    SpeedPenaltyWalk = 0.10,
    MinSprintSpeedFrac = 0.60,
    MinSneakSpeedFrac = 0.50,
    MinWalkSpeedFrac = 0.70,
  },

  Exhaustion = {
    PenaltySeconds = 4.0, -- how long the half-speed penalty lasts
    SlowFrac = 0.50, -- 50% of encumbered walk speed
    RegenOnlyWhenSneak = true, -- during penalty, regen allowed only if sneaking
    BlockJump = true, -- block jumping during penalty
    BlockSpend = true, -- block stamina spending during penalty (swing/skills)
  },
}

-- ========= Config loader (robust merge) =========
local function shallowMerge(dst, src)
  for k, v in pairs(src) do
    if type(v) == 'table' and type(dst[k]) == 'table' then
      for k2, v2 in pairs(v) do
        dst[k][k2] = v2
      end
    else
      dst[k] = v
    end
  end
  return dst
end

local Config: any = table.clone(DEFAULT)
do
  local mod: ModuleScript? = nil
  local cfgFolder = RS:FindFirstChild 'Config'
  if cfgFolder and cfgFolder:FindFirstChild 'StaminaConfig' then
    mod = cfgFolder:FindFirstChild 'StaminaConfig' :: ModuleScript
  else
    for _, d in ipairs(RS:GetDescendants()) do
      if d:IsA 'ModuleScript' and d.Name == 'StaminaConfig' then
        mod = d
        break
      end
    end
  end
  if mod then
    local ok, t = pcall(require, mod)
    if ok and type(t) == 'table' then
      Config = shallowMerge(table.clone(DEFAULT), t)
      print(('[StaminaService] Loaded StaminaConfig from %s'):format(mod:GetFullName()))
    else
      warn('[StaminaService] Failed to require StaminaConfig; using defaults. Error:', t)
    end
  else
    warn '[StaminaService] StaminaConfig not found; using defaults.'
  end
end

-- ========= Optional ItemDB (for weapon weights) =========
local ItemDB: any = nil
do
  local m = RS:FindFirstChild 'Modules'
  if m and m:FindFirstChild 'ItemDB' then
    local ok, tbl = pcall(function()
      return require(m.ItemDB)
    end)
    if ok and type(tbl) == 'table' then
      ItemDB = tbl
    else
      warn '[StaminaService] ItemDB present but failed to require; swing costs will use fallback.'
    end
  else
    warn '[StaminaService] ReplicatedStorage/Modules/ItemDB not found; swing costs will use fallback.'
  end
end

-- ========= Tunables (after config) =========
local TICK_DT = 1 / (Config.TickRate or DEFAULT.TickRate)
local REGEN_DELAY = Config.RegenDelay or DEFAULT.RegenDelay
local COST = Config.Costs or DEFAULT.Costs
local REGEN = Config.Regen or DEFAULT.Regen
local THR = Config.Thresholds or DEFAULT.Thresholds
local INT = Config.Intents or DEFAULT.Intents
local SPEEDS = Config.Speeds or DEFAULT.Speeds
local NOISE = Config.Noise or DEFAULT.Noise
local ENC = (Config.Encumbrance or DEFAULT.Encumbrance)
local DBG = (Config.Debug or DEFAULT.Debug)
local EXH = (Config.Exhaustion or DEFAULT.Exhaustion)
local USE_SERVER_SPRINT_SPEED = (Config.UseServerSprintSpeed ~= false)

-- ========= Types / State =========
type Flags = { [string]: boolean }
type Telemetry = {
  sprintSec: number,
  blockSec: number,
  timesZero: number,
  spendEvents: number,
  byReason: { [string]: number },
  avgWeightRatioSum: number,
  avgWeightRatioT: number,
  lastPrintAt: number,
}
type PerPlayer = {
  humanoid: Humanoid?,
  stamina: number,
  max: number,
  flags: Flags,
  lastSpendT: number,
  enabled: boolean,
  exhausted: boolean,
  penaltyUntil: number,
  telemetry: Telemetry,
  lastSpeedTarget: number?,
  lastJumpAt: number?,
}
local State: { [Player]: PerPlayer } = {}
local lastIntentAt: { [Player]: number } = {} -- fuse

-- ========= Utils =========
local function clamp(x: number, a: number, b: number): number
  if x < a then
    return a
  end
  if x > b then
    return b
  end
  return x
end
local function setAttr(p: Player, name: string, value: any)
  if p:GetAttribute(name) ~= value then
    p:SetAttribute(name, value)
  end
end

-- Penalty helpers
local function penaltyActive(pp: PerPlayer): boolean
  return pp.exhausted and (time() < pp.penaltyUntil)
end
local function startPenalty(p: Player, pp: PerPlayer)
  pp.exhausted = true
  pp.penaltyUntil = time() + (EXH.PenaltySeconds or 4.0)
  setAttr(p, 'ExhaustedUntil', pp.penaltyUntil)
  setAttr(p, 'IsExhausted', true)
  pp.telemetry.timesZero += 1
  NoticeRE:FireClient(p, 'Exhausted')
end
local function endPenalty(p: Player, pp: PerPlayer)
  pp.exhausted = false
  pp.penaltyUntil = 0
  setAttr(p, 'IsExhausted', false)
  NoticeRE:FireClient(p, 'ExhaustionRecovered')
end

local function applySpend(p: Player, pp: PerPlayer, amount: number)
  local prev = pp.stamina
  pp.stamina = clamp(prev - amount, 0, pp.max)
  pp.lastSpendT = time()
  if prev > 0 and pp.stamina <= 0 then
    startPenalty(p, pp)
  end
end

local function regenAllowedBase(pp: PerPlayer): boolean
  return (time() - pp.lastSpendT) >= REGEN_DELAY
end
local function regenAllowed(pp: PerPlayer): boolean
  if penaltyActive(pp) and EXH.RegenOnlyWhenSneak then
    return pp.flags[INT.Sneaking] and regenAllowedBase(pp)
  end
  return regenAllowedBase(pp)
end

local function isMoving(pp: PerPlayer): boolean
  local hum = pp.humanoid
  return hum ~= nil and hum.MoveDirection.Magnitude > 0.01
end

-- Encumbrance helpers
local function readWeightAttrs(p: Player): (number, number)
  local weight = p:GetAttribute(ENC.WeightAttr or 'CarryWeight')
  local maxCar = p:GetAttribute(ENC.MaxCarryAttr or 'MaxCarry')
    or ENC.MaxCarry
    or DEFAULT.Encumbrance.MaxCarry
  if typeof(weight) ~= 'number' then
    weight = 0
  end
  if typeof(maxCar) ~= 'number' or maxCar <= 0 then
    maxCar = ENC.MaxCarry or DEFAULT.Encumbrance.MaxCarry
  end
  return weight, maxCar
end
local function encumbranceScalars(p: Player): (number, number, number)
  if not ENC.Enabled then
    return 0, 1.0, 1.0
  end
  local weight, maxCar = readWeightAttrs(p)
  local ratio = clamp(weight / math.max(1, maxCar), 0, 2)
  local drainMul = clamp(1 + ratio * (ENC.DrainScale or 0.5), 0.0, ENC.MaxDrainScalar or 2.0)
  local regenMul = clamp(1 - ratio * (ENC.RegenScale or 0.4), ENC.MinRegenScalar or 0.25, 1.0)
  return ratio, drainMul, regenMul
end

-- Speed penalty helper (sprint/sneak/walk)
type Role = 'sprint' | 'sneak' | 'walk'
local function applyEncumbranceSpeed(targetSpeed: number, role: Role, ratio: number): number
  if not ENC.Enabled then
    return targetSpeed
  end
  local r = clamp(ratio, 0, 1)
  if role == 'sprint' then
    local mul = clamp(1 - (ENC.SpeedPenaltySprint or 0.25) * r, ENC.MinSprintSpeedFrac or 0.60, 1.0)
    return targetSpeed * mul
  elseif role == 'sneak' then
    local mul = clamp(1 - (ENC.SpeedPenaltySneak or 0.15) * r, ENC.MinSneakSpeedFrac or 0.50, 1.0)
    return targetSpeed * mul
  else
    local mul = clamp(1 - (ENC.SpeedPenaltyWalk or 0.10) * r, ENC.MinWalkSpeedFrac or 0.70, 1.0)
    return targetSpeed * mul
  end
end

-- ========= Per-weapon swing cost (ItemDB weight) =========
local function getItemWeight(itemId: string): number?
  if not ItemDB then
    return nil
  end
  local ok, res = pcall(function()
    if typeof(ItemDB.GetItem) == 'function' then
      local item = ItemDB.GetItem(itemId)
      if item and typeof(item) == 'table' then
        return item.weight or item.Weight
      end
    end
    local entry = ItemDB[itemId]
    if entry and typeof(entry) == 'table' then
      return entry.weight or entry.Weight
    end
    return nil
  end)
  if ok then
    return res
  else
    return nil
  end
end

local function swingCostForItem(itemId: string, drainMulForSwings: number?): number
  local override = (COST.Weapon or {})[itemId]
  if typeof(override) == 'number' then
    local t = COST.WeightToSwing or DEFAULT.Costs.WeightToSwing
    return clamp(override, t.Min or 0, t.Max or 1e9)
  end
  local weight = getItemWeight(itemId)
  local tun = COST.WeightToSwing or DEFAULT.Costs.WeightToSwing
  local cost = (weight and (tun.Base + tun.PerUnit * weight))
    or (COST.SwingFlat or DEFAULT.Costs.SwingFlat)
  cost = clamp(cost, tun.Min, tun.Max)
  if drainMulForSwings and ENC.Enabled and (ENC.Apply and ENC.Apply.Swing) then
    cost *= drainMulForSwings
  end
  return cost
end

-- ========= Public API =========
local StaminaService = {}

function StaminaService.Get(p: Player): (number, number)
  local pp = State[p]
  if not pp then
    return 0, Config.Max
  end
  return pp.stamina, pp.max
end

function StaminaService.CanAfford(p: Player, amount: number): boolean
  local pp = State[p]
  if not pp or not pp.enabled then
    return false
  end
  -- During penalty, disallow spending (even if sneaking)
  if penaltyActive(pp) and (EXH.BlockSpend ~= false) then
    return false
  end
  return pp.stamina >= amount
end

function StaminaService.TrySpend(p: Player, amount: number, reason: string?): (boolean, number)
  local pp = State[p]
  if not pp or not pp.enabled then
    return false, 0
  end
  if penaltyActive(pp) and (EXH.BlockSpend ~= false) then
    return false, pp.stamina
  end
  if pp.stamina < amount then
    return false, pp.stamina
  end
  applySpend(p, pp, amount)
  if reason and reason ~= '' then
    pp.telemetry.spendEvents += 1
    pp.telemetry.byReason[reason] = (pp.telemetry.byReason[reason] or 0) + 1
  end
  return true, pp.stamina
end

function StaminaService.SwingCost(itemId: string, p: Player?): number
  local drainMul: number? = nil
  if p and ENC.Enabled and (ENC.Apply and ENC.Apply.Swing) then
    local _, dMul = encumbranceScalars(p)
    drainMul = dMul
  end
  return swingCostForItem(itemId, drainMul)
end

function StaminaService.TrySpendSwing(p: Player, itemId: string, reason: string?): (boolean, number)
  local pp = State[p]
  if not pp or not pp.enabled then
    return false, 0
  end
  if penaltyActive(pp) and (EXH.BlockSpend ~= false) then
    return false, pp.stamina
  end
  local cost = StaminaService.SwingCost(itemId, p)
  setAttr(p, 'LastSwingCost', math.floor(cost + 0.5))
  if pp.stamina < cost then
    return false, pp.stamina
  end
  applySpend(p, pp, cost)
  if reason and reason ~= '' then
    pp.telemetry.spendEvents += 1
    pp.telemetry.byReason[reason] = (pp.telemetry.byReason[reason] or 0) + 1
  end
  return true, pp.stamina
end

function StaminaService.SetMax(p: Player, newMax: number)
  local pp = State[p]
  if not pp then
    return
  end
  pp.max = math.max(1, newMax)
  pp.stamina = clamp(pp.stamina, 0, pp.max)
end

function StaminaService.SetEnabled(p: Player, on: boolean)
  local pp = State[p]
  if not pp then
    return
  end
  pp.enabled = on
end

function StaminaService.Spend(p: Player, amountOrAction: any): (boolean, number)
  if typeof(amountOrAction) == 'number' then
    return StaminaService.TrySpend(p, amountOrAction, 'Spend')
  elseif typeof(amountOrAction) == 'string' then
    local map = { Attack = (COST.SwingFlat or DEFAULT.Costs.SwingFlat) }
    local amt = map[amountOrAction]
    if not amt then
      return false, (State[p] and State[p].stamina) or 0
    end
    return StaminaService.TrySpend(p, amt, amountOrAction)
  end
  return false, (State[p] and State[p].stamina) or 0
end

_G.StaminaService = StaminaService

-- ========= Player lifecycle =========
local function attachCharacter(p: Player, char: Model)
  local hum = char:WaitForChild 'Humanoid' :: Humanoid
  local pp = State[p]
  if not pp then
    return
  end

  pp.humanoid = hum
  hum:SetAttribute('BaseWalkSpeed', hum.WalkSpeed)

  pp.flags[INT.Sprinting] = false
  pp.flags[INT.Sneaking] = false
  pp.flags[INT.Blocking] = false

  setAttr(p, 'StaminaMax', pp.max)
  setAttr(p, 'Stamina', math.floor(pp.stamina + 0.5))
  setAttr(p, 'IsSprinting', false)
  setAttr(p, 'IsSneaking', false)
  setAttr(p, 'NoiseScalar', NOISE.Idle or 0.2)
  setAttr(p, 'IsExhausted', pp.exhausted)
  setAttr(p, 'ExhaustedUntil', pp.penaltyUntil)

  -- === Bill jump once at takeoff (blocked during penalty) ===
  hum.StateChanged:Connect(function(_, new)
    if new ~= Enum.HumanoidStateType.Jumping then
      return
    end
    if penaltyActive(pp) and (EXH.BlockJump ~= false) then
      hum.Jump = false
      return
    end

    local now = time()
    local fuse = (DBG and DBG.JumpFuse) or 0.20
    if pp.lastJumpAt and (now - pp.lastJumpAt) < fuse then
      return
    end

    -- Optional gate by threshold (comment out to allow jump anytime)
    if THR.MinToJump and pp.stamina < THR.MinToJump then
      hum.Jump = false
      return
    end

    pp.lastJumpAt = now

    local _, drainMul = encumbranceScalars(p)
    local cost = (COST.JumpFlat or DEFAULT.Costs.JumpFlat)
    if ENC.Enabled and (ENC.Apply and ENC.Apply.Jump) then
      cost *= drainMul
    end

    applySpend(p, pp, cost)
    pp.telemetry.spendEvents += 1
    pp.telemetry.byReason['Jump'] = (pp.telemetry.byReason['Jump'] or 0) + 1
  end)

  hum.Died:Once(function()
    if USE_SERVER_SPRINT_SPEED then
      hum.WalkSpeed = hum:GetAttribute 'BaseWalkSpeed' or SPEEDS.Walk
    end
  end)
end

local function initPlayer(p: Player)
  State[p] = {
    humanoid = nil,
    stamina = Config.Max or DEFAULT.Max,
    max = Config.Max or DEFAULT.Max,
    flags = {},
    lastSpendT = 0,
    enabled = true,
    exhausted = false,
    penaltyUntil = 0,
    telemetry = {
      sprintSec = 0,
      blockSec = 0,
      timesZero = 0,
      spendEvents = 0,
      byReason = {},
      avgWeightRatioSum = 0,
      avgWeightRatioT = 0,
      lastPrintAt = time(),
    },
    lastSpeedTarget = nil,
    lastJumpAt = 0,
  }
  setAttr(p, 'StaminaMax', Config.Max or DEFAULT.Max)
  setAttr(p, 'Stamina', Config.Max or DEFAULT.Max)
  setAttr(p, 'IsSprinting', false)
  setAttr(p, 'IsSneaking', false)
  setAttr(p, 'NoiseScalar', NOISE.Idle or 0.2)
  setAttr(p, 'IsExhausted', false)
  setAttr(p, 'ExhaustedUntil', 0)

  p.CharacterAdded:Connect(function(char)
    attachCharacter(p, char)
  end)
  if p.Character then
    task.defer(function()
      attachCharacter(p, p.Character :: Model)
    end)
  end

  -- auto dump after 3 minutes (dev aid)
  task.delay(180, function()
    local pp = State[p]
    if pp then
      local avgRatio = (pp.telemetry.avgWeightRatioT > 0)
          and (pp.telemetry.avgWeightRatioSum / pp.telemetry.avgWeightRatioT)
        or 0
      print(
        ('[Stamina/Tel:auto180s] %s avgRatio=%.2f spends=%d zeros=%d'):format(
          p.Name,
          avgRatio,
          pp.telemetry.spendEvents,
          pp.telemetry.timesZero
        )
      )
    end
  end)
end

local function cleanupPlayer(p: Player)
  local pp = State[p]
  if pp then
    local avgRatio = (pp.telemetry.avgWeightRatioT > 0)
        and (pp.telemetry.avgWeightRatioSum / pp.telemetry.avgWeightRatioT)
      or 0
    print(
      ('[Stamina/Tel:leave] %s avgRatio=%.2f spends=%d zeros=%d'):format(
        p.Name,
        avgRatio,
        pp.telemetry.spendEvents,
        pp.telemetry.timesZero
      )
    )
  end
  State[p] = nil
  lastIntentAt[p] = nil
end

Players.PlayerAdded:Connect(initPlayer)
Players.PlayerRemoving:Connect(cleanupPlayer)
for _, p in ipairs(Players:GetPlayers()) do
  initPlayer(p)
end

-- ========= Intents (with fuse) =========
IntentsRE.OnServerEvent:Connect(function(p: Player, intents: Flags)
  local now = time()
  local last = lastIntentAt[p] or 0
  if (now - last) < 0.05 then
    return
  end
  lastIntentAt[p] = now

  local pp = State[p]
  if not pp or not pp.enabled then
    return
  end

  -- remember previous to detect "turning on"
  local prevSprint = (pp.flags[INT.Sprinting] == true)
  local prevBlock = (pp.flags[INT.Blocking] == true)

  -- apply requested flags
  for k, v in pairs(intents) do
    pp.flags[k] = (v == true)
  end

  -- mutual exclusivity
  if pp.flags[INT.Sprinting] then
    pp.flags[INT.Sneaking] = false
  elseif pp.flags[INT.Sneaking] then
    pp.flags[INT.Sprinting] = false
  end

  -- block during penalty
  if penaltyActive(pp) then
    if pp.flags[INT.Sprinting] then
      pp.flags[INT.Sprinting] = false
      NoticeRE:FireClient(p, 'ForceStopSprint')
    end
    if pp.flags[INT.Blocking] then
      pp.flags[INT.Blocking] = false
      NoticeRE:FireClient(p, 'ForceStopBlock')
    end
  end

  -- gate ONLY when turning ON (allow draining below threshold once on)
  if
    not prevSprint
    and pp.flags[INT.Sprinting]
    and THR.MinToSprint
    and pp.stamina < THR.MinToSprint
  then
    pp.flags[INT.Sprinting] = false
    NoticeRE:FireClient(p, 'ForceStopSprint')
  end
  if
    not prevBlock
    and pp.flags[INT.Blocking]
    and THR.MinToBlock
    and pp.stamina < THR.MinToBlock
  then
    pp.flags[INT.Blocking] = false
    NoticeRE:FireClient(p, 'ForceStopBlock')
  end
end)

-- ========= Main tick =========
local dtAccum = 0
RunService.Heartbeat:Connect(function(dt)
  dtAccum += dt
  while dtAccum >= TICK_DT do
    dtAccum -= TICK_DT
    for p, pp in pairs(State) do
      if not pp.enabled then
        continue
      end

      local moving = isMoving(pp)
      local draining = false
      local spend = 0

      local ratio, drainMul, regenMul = encumbranceScalars(p)
      setAttr(p, 'CarryRatio', ratio)
      setAttr(p, 'EncumbranceDrain', drainMul)
      setAttr(p, 'EncumbranceRegen', regenMul)
      pp.telemetry.avgWeightRatioSum += ratio * TICK_DT
      pp.telemetry.avgWeightRatioT += TICK_DT

      local inPenalty = penaltyActive(pp)

      -- per-second drains (blocked during penalty)
      if not inPenalty then
        -- Sprint: if on & moving, ALWAYS drain (don't force-stop at threshold)
        if pp.flags[INT.Sprinting] and moving then
          draining = true
          local sprintDrain = (COST.SprintPerSec or DEFAULT.Costs.SprintPerSec)
          if ENC.Enabled and (ENC.Apply and ENC.Apply.Sprint) then
            sprintDrain *= drainMul
          end
          spend += sprintDrain * TICK_DT
        end
        -- Block: if on, ALWAYS drain (no auto-stop at threshold)
        if pp.flags[INT.Blocking] then
          draining = true
          local blockDrain = (COST.BlockPerSec or DEFAULT.Costs.BlockPerSec)
          if ENC.Enabled and (ENC.Apply and ENC.Apply.Block) then
            blockDrain *= drainMul
          end
          spend += blockDrain * TICK_DT
        end
      else
        -- force stop during penalty
        if pp.flags[INT.Sprinting] then
          pp.flags[INT.Sprinting] = false
          NoticeRE:FireClient(p, 'ForceStopSprint')
        end
        if pp.flags[INT.Blocking] then
          pp.flags[INT.Blocking] = false
          NoticeRE:FireClient(p, 'ForceStopBlock')
        end
      end

      -- telemetry
      if pp.flags[INT.Sprinting] then
        pp.telemetry.sprintSec += TICK_DT
      end
      if pp.flags[INT.Blocking] then
        pp.telemetry.blockSec += TICK_DT
      end

      if spend > 0 then
        applySpend(p, pp, spend)
      end

      -- regen (Sneak > Idle > Walk), scaled by encumbrance; restricted during penalty
      if not draining and regenAllowed(pp) then
        local baseRegen = (pp.flags[INT.Sneaking] and (REGEN.Sneak or DEFAULT.Regen.Sneak))
          or (not moving and (REGEN.Idle or DEFAULT.Regen.Idle))
          or (REGEN.Walk or DEFAULT.Regen.Walk)
        baseRegen *= (ENC.Enabled and regenMul) or 1.0
        pp.stamina = clamp(pp.stamina + baseRegen * TICK_DT, 0, pp.max)
      end

      -- penalty window end when time elapses
      if pp.exhausted and not inPenalty then
        endPenalty(p, pp)
      end

      -- server movement speed (encumbrance on walk; override during penalty)
      local hum = pp.humanoid
      if USE_SERVER_SPRINT_SPEED and hum then
        local baseWalk = hum:GetAttribute 'BaseWalkSpeed' or SPEEDS.Walk
        local encWalk = applyEncumbranceSpeed(baseWalk, 'walk', ratio)

        local target = encWalk
        if inPenalty then
          target = encWalk * (EXH.SlowFrac or 0.5)
        else
          if pp.flags[INT.Sprinting] and moving then
            target = applyEncumbranceSpeed(SPEEDS.Sprint or DEFAULT.Speeds.Sprint, 'sprint', ratio)
          elseif pp.flags[INT.Sneaking] and moving then
            local sneakBase = SPEEDS.Sneak or math.max(6, math.floor(baseWalk * 0.7 + 0.5))
            target = applyEncumbranceSpeed(sneakBase, 'sneak', ratio)
          end
        end

        if hum.WalkSpeed ~= target then
          hum.WalkSpeed = target
          setAttr(p, 'SpeedTarget', target)
          local penaltyVsWalk = encWalk > 0 and (1 - target / encWalk) or 0
          setAttr(p, 'SpeedPenalty', penaltyVsWalk)
          if DBG and DBG.PrintSpeedChanges then
            print(
              ('[Stamina/Speed] %s target=%.1f encWalk=%.1f ratio=%.2f exhausted=%s state=%s'):format(
                p.Name,
                target,
                encWalk,
                ratio,
                tostring(inPenalty),
                pp.flags[INT.Sprinting] and 'sprint'
                  or (pp.flags[INT.Sneaking] and 'sneak' or 'walk')
              )
            )
          end
          pp.lastSpeedTarget = target
        end
      end

      -- replicate attrs
      setAttr(p, 'Stamina', math.floor(pp.stamina + 0.5))
      setAttr(p, 'IsSprinting', (pp.flags[INT.Sprinting] and isMoving(pp)) and true or false)
      setAttr(
        p,
        'IsSneaking',
        (pp.flags[INT.Sneaking] and not pp.flags[INT.Sprinting]) and true or false
      )

      -- noise scalar
      local noise = (not isMoving(pp) and (NOISE.Idle or DEFAULT.Noise.Idle))
        or (pp.flags[INT.Sprinting] and (NOISE.Sprint or DEFAULT.Noise.Sprint))
        or (pp.flags[INT.Sneaking] and (NOISE.Sneak or DEFAULT.Noise.Sneak))
        or (NOISE.Walk or DEFAULT.Noise.Walk)
      setAttr(p, 'NoiseScalar', noise)

      -- periodic telemetry print
      if DBG and DBG.PrintTelemetryEvery and DBG.PrintTelemetryEvery > 0 then
        local nowT = time()
        if (nowT - pp.telemetry.lastPrintAt) >= DBG.PrintTelemetryEvery then
          pp.telemetry.lastPrintAt = nowT
          local avgRatio = (pp.telemetry.avgWeightRatioT > 0)
              and (pp.telemetry.avgWeightRatioSum / pp.telemetry.avgWeightRatioT)
            or 0
          print(
            ('[Stamina/Tel] %s sprintSec=%.1f blockSec=%.1f timesZero=%d spendEvents=%d avgRatio=%.2f'):format(
              p.Name,
              pp.telemetry.sprintSec,
              pp.telemetry.blockSec,
              pp.telemetry.timesZero,
              pp.telemetry.spendEvents,
              avgRatio
            )
          )
        end
      end
    end
  end
end)

print '[StaminaService] Ready (remotes present, _G export set)'
return StaminaService

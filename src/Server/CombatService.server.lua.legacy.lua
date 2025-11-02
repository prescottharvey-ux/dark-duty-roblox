-- ServerScriptService/Combat/CombatService.server.lua
--!strict
local RS = game:GetService 'ReplicatedStorage'
local Players = game:GetService 'Players'
local RunService = game:GetService 'RunService'
local SSS = game:GetService 'ServerScriptService'

-- ========== EventBus ==========
local Bus = require(RS:WaitForChild('Events'):WaitForChild 'EventBus')

-- ========== AnimIds (safe load; supports number or "rbxassetid://") ==========
local AnimOk, AnimIds = pcall(function()
  -- Give AnimIds up to 10s to exist to avoid the infinite-yield spam
  local folder = RS:WaitForChild('Modules'):WaitForChild 'Combat'
  local mod = folder:WaitForChild('AnimIds', 10)
  return require(mod)
end)
if not AnimOk or type(AnimIds) ~= 'table' then
  AnimIds = { Dagger = {}, Shield = {} }
end

local function toAssetId(v: any): string
  if typeof(v) == 'number' then
    return ('rbxassetid://%d'):format(v)
  elseif typeof(v) == 'string' then
    if v:sub(1, 13) == 'rbxassetid://' then
      return v
    end
    local q = string.match(v, '[%?&]id=(%d+)')
    if q then
      return 'rbxassetid://' .. q
    end
    return 'rbxassetid://' .. v
  end
  return ''
end

-- ========== Optional modules ==========
local Combat: any? = nil
do
  local ok, mod = pcall(function()
    return require(RS:WaitForChild('Modules'):WaitForChild('Combat'):WaitForChild 'Combat')
  end)
  if ok then
    Combat = mod
  end
end

-- Optional Inventory + Stamina (auto-detect)
local InventoryOk, Inventory = pcall(function()
  return require(SSS:WaitForChild('Inventory'):WaitForChild 'Public')
end)
local StaminaOk, Stamina = pcall(function()
  local folder = SSS:FindFirstChild 'Stamina' or SSS:FindFirstChild 'Systems'
  if folder and folder:FindFirstChild 'Public' then
    return require(folder.Public)
  end
  return nil
end)

-- ========== Options (preserve old behavior by default) ==========
local ENFORCE_FIXED_HANDS = false -- require correct slot: weapons/spellbooks=Right, shields/items=Left
local REQUIRE_SHIELD_FOR_BLOCK = false -- old behavior: blocking allowed without a shield

-- ========== Remotes (ensure) ==========
local Remotes = RS:FindFirstChild 'Remotes' or Instance.new 'Folder'
Remotes.Name = 'Remotes'
Remotes.Parent = RS
local REFolder = Remotes:FindFirstChild 'RemoteEvent' or Instance.new 'Folder'
REFolder.Name = 'RemoteEvent'
REFolder.Parent = Remotes
local RFCombat = REFolder:FindFirstChild 'Combat' or Instance.new 'Folder'
RFCombat.Name = 'Combat'
RFCombat.Parent = REFolder

local function ensureRE(parent: Instance, name: string): RemoteEvent
  local re = parent:FindFirstChild(name)
  if not re then
    re = Instance.new 'RemoteEvent'
    re.Name = name
    re.Parent = parent
  end
  return re :: RemoteEvent
end

local RE_StartBlock = ensureRE(RFCombat, 'StartBlock')
local RE_StopBlock = ensureRE(RFCombat, 'StopBlock')
local RE_DaggerAttack = ensureRE(RFCombat, 'DaggerAttack')
local RE_ForceBlockOff = ensureRE(RFCombat, 'ForceBlockOff')
local RE_ReplicateDagger = ensureRE(RFCombat, 'ReplicateDaggerSwing')
local RE_Debug = ensureRE(RFCombat, 'DebugMsg') -- optional

-- Client listener path is ReplicatedStorage.Remotes.RemoteEvent.DamageNumber
local DamageNumber = ensureRE(REFolder, 'DamageNumber')
local function showNumber(p: Player, worldPos: Vector3, amount: number)
  if typeof(amount) == 'number' and typeof(worldPos) == 'Vector3' then
    DamageNumber:FireClient(p, worldPos, amount)
  end
end
-- Optional helper if you ever want to fan-out:
local function showNumberAll(worldPos: Vector3, amount: number)
  if typeof(amount) == 'number' and typeof(worldPos) == 'Vector3' then
    DamageNumber:FireAllClients(worldPos, amount)
  end
end

-- ========== Tunables ==========
local DAGGER_STAB_COST = 8.0
local DAGGER_STAB_COOLDOWN = 0.45 -- seconds
local SHIELD_HOLD_DRAIN_PER_SEC = 2.0
local SHIELD_BLOCK_BONUS_COST = 10.0 -- extra spend on successful block
local DRAIN_TICK = 0.25 -- shield drain cadence

-- ========== Helpers ==========
local function itemHasTag(it: any, tag: string): boolean
  if not it then
    return false
  end
  local t = string.lower(tostring((it :: any).type or (it :: any).Type or ''))
  if t == tag then
    return true
  end
  local tags = (it :: any).tags or (it :: any).Tags
  if typeof(tags) == 'table' then
    for _, v in ipairs(tags :: { any }) do
      if string.lower(tostring(v)) == tag then
        return true
      end
    end
  end
  return false
end

local function isWeaponOrSpellbook(it: any): boolean
  if not it then
    return false
  end
  local t = string.lower(tostring((it :: any).type or (it :: any).Type or ''))
  if t == 'weapon' or t == 'dagger' or t == 'sword' or t == 'staff' or t == 'spellbook' then
    return true
  end
  return itemHasTag(it, 'weapon') or itemHasTag(it, 'spellbook') or itemHasTag(it, 'dagger')
end

-- returns true if any equipped item (optionally in specific hand) satisfies predicate
local function equippedSatisfies(
  plr: Player,
  wantHand: 'L' | 'R' | nil,
  predicate: (any) -> boolean
): boolean
  if not (InventoryOk and Inventory and typeof((Inventory :: any).GetEquipped) == 'function') then
    return false
  end
  local ok, eq = pcall((Inventory :: any).GetEquipped, plr)
  if not ok or type(eq) ~= 'table' then
    return false
  end

  -- Shape A: {handL=item, handR=item}
  if (eq :: any).handL or (eq :: any).handR then
    if wantHand == 'L' then
      return predicate((eq :: any).handL)
    elseif wantHand == 'R' then
      return predicate((eq :: any).handR)
    else
      return predicate((eq :: any).handL) or predicate((eq :: any).handR)
    end
  end

  -- Shape B: array of items with .slot/.hand
  for _, it in pairs(eq) do
    if type(it) == 'table' then
      local slot = string.lower(tostring((it :: any).slot or (it :: any).hand or ''))
      if wantHand == 'L' and not slot:find 'handl' then
        -- skip
      elseif wantHand == 'R' and not slot:find 'handr' then
        -- skip
      elseif predicate(it) then
        return true
      end
    end
  end
  return false
end

local function hasEquippedShield(plr: Player): boolean
  if not REQUIRE_SHIELD_FOR_BLOCK then
    return true
  end -- preserve old behavior
  if not InventoryOk then
    return false
  end
  if ENFORCE_FIXED_HANDS then
    return equippedSatisfies(plr, 'L', function(it)
      return itemHasTag(it, 'shield')
        or (string.lower(tostring(it and (it.type or it.Type) or '')) == 'shield')
    end)
  else
    return equippedSatisfies(plr, nil, function(it)
      return itemHasTag(it, 'shield')
        or (string.lower(tostring(it and (it.type or it.Type) or '')) == 'shield')
    end)
  end
end

local function hasEquippedDaggerOrWeapon(plr: Player): boolean
  if not InventoryOk then
    return true
  end -- allow tests without inventory
  if ENFORCE_FIXED_HANDS then
    return equippedSatisfies(plr, 'R', function(it)
      return isWeaponOrSpellbook(it)
    end)
  else
    return equippedSatisfies(plr, nil, function(it)
      return itemHasTag(it, 'dagger') or isWeaponOrSpellbook(it)
    end)
  end
end

local function getStamina(plr: Player): number
  if StaminaOk and Stamina and (Stamina :: any).Get then
    local ok, val = pcall(function()
      return (Stamina :: any).Get(plr)
    end)
    if ok and typeof(val) == 'number' then
      return val
    end
  end
  local char = plr.Character
  if char and char:GetAttribute 'Stamina' ~= nil then
    return (char:GetAttribute 'Stamina' :: any) :: number
  end
  return 100.0
end

local function canSpend(plr: Player, amt: number): boolean
  if StaminaOk and Stamina and (Stamina :: any).CanSpend then
    local ok, res = pcall(function()
      return (Stamina :: any).CanSpend(plr, amt)
    end)
    if ok then
      return res and true or false
    end
  end
  return getStamina(plr) >= amt
end

local function spend(plr: Player, amt: number)
  if amt <= 0 then
    return
  end
  if StaminaOk and Stamina and (Stamina :: any).Spend then
    pcall(function()
      (Stamina :: any).Spend(plr, amt)
    end)
  else
    local char = plr.Character
    if char then
      local cur = getStamina(plr)
      char:SetAttribute('Stamina', math.max(0, cur - amt))
    end
  end
end

local function loadAndPlay(
  char: Model,
  animIdAny: any,
  looped: boolean?,
  weight: number?
): AnimationTrack?
  local hum = char:FindFirstChildOfClass 'Humanoid'
  if not hum then
    return nil
  end
  local animator = hum:FindFirstChildOfClass 'Animator' or Instance.new('Animator', hum)
  local anim = Instance.new 'Animation'
  anim.AnimationId = toAssetId(animIdAny)
  if anim.AnimationId == '' then
    return nil
  end
  local track = animator:LoadAnimation(anim)
  if looped ~= nil then
    track.Looped = looped
  end
  track:Play(0.05, 1, weight or 1.0)
  return track
end

-- Try to fetch the current weapon id (for server-auth damage scaling)
local function currentWeaponId(plr: Player): string?
  if not (InventoryOk and Inventory and typeof((Inventory :: any).GetEquipped) == 'function') then
    return nil
  end
  local ok, eq = pcall((Inventory :: any).GetEquipped, plr)
  if not ok or type(eq) ~= 'table' then
    return nil
  end

  local function idFrom(it: any): string?
    if it == nil then
      return nil
    end
    if typeof(it) == 'string' then
      return it
    end
    if type(it) == 'table' then
      if typeof((it :: any).id) == 'string' then
        return (it :: any).id
      end
      if typeof((it :: any).Name) == 'string' then
        return (it :: any).Name
      end
    end
    return nil
  end

  -- Prefer handR if present
  if (eq :: any).handR or (eq :: any).handL then
    return idFrom((eq :: any).handR) or idFrom((eq :: any).handL)
  end

  -- Fallback: array shape, pick a hand item (prefer right if flagged)
  for _, it in pairs(eq) do
    if type(it) == 'table' then
      local slot = string.lower(tostring((it :: any).slot or (it :: any).hand or ''))
      if slot:find 'handr' or slot:find 'hand' then
        local id = idFrom(it)
        if id then
          return id
        end
      end
    end
  end
  return nil
end

-- ========== State ==========
type AnimBundle = { ShieldLoop: AnimationTrack? }
local Blocking: { [Player]: boolean } = {}
local DaggerCd: { [Player]: number } = {} -- os.clock() when next allowed
local AnimTracks: { [Player]: AnimBundle } = {}

local function setBlocking(plr: Player, isOn: boolean)
  Blocking[plr] = isOn
  local char = plr.Character
  if char then
    char:SetAttribute('IsBlocking', isOn)
  end
end

-- ========== Blocking drain loop ==========
task.spawn(function()
  while true do
    task.wait(DRAIN_TICK)
    for plr, isOn in pairs(Blocking) do
      if isOn then
        local cost = SHIELD_HOLD_DRAIN_PER_SEC * DRAIN_TICK
        if canSpend(plr, cost) then
          spend(plr, cost)
        else
          -- Out of stamina ⇒ force stop
          setBlocking(plr, false)
          RE_ForceBlockOff:FireClient(plr)
          local bundle = AnimTracks[plr]
          if bundle and bundle.ShieldLoop then
            pcall(function()
              (bundle.ShieldLoop :: AnimationTrack):Stop(0.1)
            end)
          end
        end
      end
    end
  end
end)

-- ========== EventBus helper + shield-bonus spend ==========
local function busOn(topic: string, fn: (...any) -> ()) -- tiny helper for EventBus variants
  for _, name in ipairs { 'On', 'Connect', 'Subscribe', 'subscribe' } do
    local f = (Bus :: any)[name]
    if typeof(f) == 'function' then
      f(topic, fn)
      return
    end
  end
end

-- Keep your original topic and add compatibility with "Combat:BlockedHit"
busOn('Combat:ShieldBlocked', function(plr: Player)
  if Blocking[plr] then
    spend(plr, SHIELD_BLOCK_BONUS_COST)
  end
end)
busOn('Combat:BlockedHit', function(payload)
  local plr = payload and ((payload :: any).Player :: Player?)
  if plr and Blocking[plr] then
    spend(plr, SHIELD_BLOCK_BONUS_COST)
  end
end)

-- ========== Remote handlers ==========
RE_StartBlock.OnServerEvent:Connect(function(plr: Player)
  if not plr.Character then
    return
  end
  if not hasEquippedShield(plr) then
    return
  end

  setBlocking(plr, true)
  local loopId = AnimIds.Shield
    and (AnimIds.Shield.BlockLoop or (AnimIds.Shield :: any).BlockLoopAsset)
  if loopId then
    local track = loadAndPlay(plr.Character, loopId, true, 1.0)
    AnimTracks[plr] = AnimTracks[plr] or {}
    AnimTracks[plr].ShieldLoop = track
  end
end)

RE_StopBlock.OnServerEvent:Connect(function(plr: Player)
  setBlocking(plr, false)
  local bundle = AnimTracks[plr]
  if bundle and bundle.ShieldLoop then
    pcall(function()
      (bundle.ShieldLoop :: AnimationTrack):Stop(0.1)
    end)
  end
end)

RE_DaggerAttack.OnServerEvent:Connect(function(plr: Player)
  if not plr.Character then
    return
  end
  if not hasEquippedDaggerOrWeapon(plr) then
    return
  end

  local now = os.clock()
  if (DaggerCd[plr] or 0) > now then
    return
  end
  if not canSpend(plr, DAGGER_STAB_COST) then
    return
  end

  DaggerCd[plr] = now + DAGGER_STAB_COOLDOWN
  spend(plr, DAGGER_STAB_COST)

  local stabId = AnimIds.Dagger and (AnimIds.Dagger.Stab or (AnimIds.Dagger :: any).StabAsset)
  if stabId then
    loadAndPlay(plr.Character, stabId, false, 1.0)
  end
  RE_ReplicateDagger:FireAllClients(plr)

  -- Optional: server-authoritative hit + damage numbers if Combat module present
  if Combat and typeof((Combat :: any).ApplyMelee) == 'function' then
    local weaponId = currentWeaponId(plr)
    local ok, res = pcall(function()
      -- Our Combat.ApplyMelee is backwards-compatible with (plr, weaponId) or (plr, nil, weaponId)
      return (Combat :: any).ApplyMelee(plr, weaponId)
    end)
    if ok and type(res) == 'table' then
      local pos = (res :: any).pos
      local dmg = (res :: any).dmg
      if typeof(pos) == 'Vector3' and typeof(dmg) == 'number' then
        showNumber(plr, pos, dmg)
      end
    end
  end
end)

-- ========== Auto-stop block on unequip or death ==========
local function maybeForceStop(plr: Player)
  if Blocking[plr] and not hasEquippedShield(plr) then
    setBlocking(plr, false)
    RE_ForceBlockOff:FireClient(plr)
    local bundle = AnimTracks[plr]
    if bundle and bundle.ShieldLoop then
      pcall(function()
        (bundle.ShieldLoop :: AnimationTrack):Stop(0.1)
      end)
    end
  end
end

-- Listen for equip changes (try common topic names)
for _, topic in ipairs {
  'Inventory:EquipChanged',
  'inventory.equip_changed',
  'inventory.equipped',
  'EquipChanged',
  'equip.changed',
} do
  busOn(topic, function(payload)
    local plr = payload and ((payload :: any).player or (payload :: any).Player)
    if typeof(plr) == 'Instance' then
      maybeForceStop(plr :: Player)
    end
  end)
end

-- Clear on death / cleanup on leave
local function hookCharacter(plr: Player, char: Model)
  char:SetAttribute('IsBlocking', false)
  local hum = char:FindFirstChildOfClass 'Humanoid'
  if hum then
    hum.Died:Connect(function()
      if Blocking[plr] then
        setBlocking(plr, false)
        local bundle = AnimTracks[plr]
        if bundle and bundle.ShieldLoop then
          pcall(function()
            (bundle.ShieldLoop :: AnimationTrack):Stop(0.1)
          end)
        end
      end
    end)
  end
end

Players.PlayerAdded:Connect(function(plr)
  plr.CharacterAdded:Connect(function(c)
    hookCharacter(plr, c)
  end)
  plr.CharacterRemoving:Connect(function()
    if Blocking[plr] then
      setBlocking(plr, false)
      local bundle = AnimTracks[plr]
      if bundle and bundle.ShieldLoop then
        pcall(function()
          (bundle.ShieldLoop :: AnimationTrack):Stop(0.1)
        end)
      end
    end
  end)
end)

Players.PlayerRemoving:Connect(function(plr)
  Blocking[plr] = nil
  DaggerCd[plr] = nil
  AnimTracks[plr] = nil
end)

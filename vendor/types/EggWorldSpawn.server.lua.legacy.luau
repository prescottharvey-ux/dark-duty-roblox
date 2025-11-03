-- ServerScriptService/Egg/EggWorldSpawn.server.lua
--!strict
local Players = game:GetService 'Players'
local RS = game:GetService 'ReplicatedStorage'
local RunService = game:GetService 'RunService'

-- ==== CONFIG ====
local EGG_ITEM_ID = 'MonsterEgg'
local SPAWN_MODE = 'near_spawner' -- "near_spawner" | "map_center"
local OFFSET = Vector3.new(4, 3, 0) -- 4 studs to the side, 3 studs up (avoid clipping)
local SPAWNED_ATTR = 'WorldEggSpawned'
local FORCE_RESPAWN_ON_BOOT = true -- for testing; clears the guard on server start
local LOG = true

-- ==== Remotes (toast optional) ====
local Remotes = RS:FindFirstChild 'Remotes' or Instance.new('Folder', RS)
do
  Remotes.Name = 'Remotes'
end
local REF = Remotes:FindFirstChild 'RemoteEvent' or Instance.new('Folder', Remotes)
do
  REF.Name = 'RemoteEvent'
end
local EggNotice = REF:FindFirstChild 'EggNotice' or Instance.new('RemoteEvent', REF)
do
  EggNotice.Name = 'EggNotice'
end

-- ==== Optional deps ====
local Inventory
do
  local ok, mod = pcall(function()
    return require(game.ServerScriptService:WaitForChild('Inventory'):WaitForChild 'Public')
  end)
  Inventory = ok and mod or nil
end

-- ==== Template (use existing model if present; otherwise build a placeholder) ====
local function ensureTemplate(): Model
  local models = RS:FindFirstChild 'Models' or Instance.new('Folder', RS)
  models.Name = 'Models'
  local egg = models:FindFirstChild 'EggPickup'
  if egg and egg:IsA 'Model' and egg.PrimaryPart then
    return egg
  end

  -- Build simple placeholder once
  local m = Instance.new 'Model'
  m.Name = 'EggPickup'
  local p = Instance.new 'Part'
  p.Name = 'Egg'
  p.Anchored = true
  p.CanCollide = true
  p.Material = Enum.Material.Neon
  p.Shape = Enum.PartType.Ball
  p.Size = Vector3.new(1.4, 2.0, 1.4)
  p.Color = Color3.fromRGB(255, 245, 170)
  p.Parent = m

  local prompt = Instance.new 'ProximityPrompt'
  prompt.Name = 'GrabPrompt'
  prompt.ActionText = 'Take Egg'
  prompt.ObjectText = 'Mysterious Egg'
  prompt.HoldDuration = 0.5
  prompt.RequiresLineOfSight = false
  prompt.MaxActivationDistance = 12
  prompt.Parent = p

  m.PrimaryPart = p
  m.Parent = models
  if LOG then
    print '[EggWorldSpawn] Created placeholder template at ReplicatedStorage/Models/EggPickup'
  end
  return m
end

-- Simple ground-finder so the egg rests above floor
local function placeOnGroundNear(pos: Vector3): Vector3
  local origin = pos + Vector3.new(0, 50, 0)
  local ray = RaycastParams.new()
  ray.FilterType = Enum.RaycastFilterType.Blacklist
  ray.FilterDescendantsInstances = {}
  local hit = workspace:Raycast(origin, Vector3.new(0, -200, 0), ray)
  if hit then
    return hit.Position + Vector3.new(0, 1.5, 0)
  end
  return pos
end

local function grant(plr: Player): boolean
  if not Inventory or typeof(Inventory.addItem) ~= 'function' then
    warn('[EggWorldSpawn] Inventory.addItem missing; cannot grant ', EGG_ITEM_ID)
    return false
  end
  Inventory.addItem(plr, EGG_ITEM_ID, 1)
  EggNotice:FireClient(plr, 'Picked up a Monster Egg!')
  return true
end

local function spawnAt(pos: Vector3)
  if workspace:GetAttribute(SPAWNED_ATTR) then
    if LOG then
      print('[EggWorldSpawn] Spawn guard set; skipping (', SPAWNED_ATTR, ')')
    end
    return
  end
  local template = ensureTemplate()
  local egg = template:Clone()
  egg:SetPrimaryPartCFrame(CFrame.new(placeOnGroundNear(pos)))
  egg.Parent = workspace
  workspace:SetAttribute(SPAWNED_ATTR, true)
  if LOG then
    print(
      ('[EggWorldSpawn] Spawned egg at (%.1f, %.1f, %.1f)'):format(
        egg.PrimaryPart.Position.X,
        egg.PrimaryPart.Position.Y,
        egg.PrimaryPart.Position.Z
      )
    )
  end

  local prompt = egg.PrimaryPart:FindFirstChildOfClass 'ProximityPrompt'
  if prompt then
    local claimed = false
    prompt.Triggered:Connect(function(plr: Player)
      if claimed then
        return
      end
      claimed = true
      if grant(plr) then
        egg:Destroy()
        workspace:SetAttribute(SPAWNED_ATTR, nil)
      else
        claimed = false
      end
    end)
  end
end

local function posNearSpawner(): Vector3
  -- 1) Actual SpawnLocation
  local spawnLoc = workspace:FindFirstChildOfClass 'SpawnLocation'
  if spawnLoc then
    if LOG then
      print('[EggWorldSpawn] Using SpawnLocation:', spawnLoc:GetFullName())
    end
    return spawnLoc.Position + OFFSET
  end
  -- 2) Common names
  for _, name in ipairs { 'PlayerSpawn', 'Spawn', 'SpawnPoint', 'Spawns' } do
    local inst = workspace:FindFirstChild(name, true)
    if inst and inst:IsA 'BasePart' then
      if LOG then
        print('[EggWorldSpawn] Using named spawn:', inst:GetFullName())
      end
      return inst.Position + OFFSET
    end
  end
  -- 3) First player's HRP when available
  local p = Players:GetPlayers()[1]
  if p and p.Character then
    local hrp = p.Character:FindFirstChild 'HumanoidRootPart' :: BasePart
    if hrp then
      if LOG then
        print "[EggWorldSpawn] Using first player's HRP"
      end
      return hrp.Position + OFFSET
    end
  end
  -- fallback
  if LOG then
    print '[EggWorldSpawn] Fallback to origin'
  end
  return Vector3.new(0, 6, 0)
end

local function mapCenterPos(): Vector3
  local map = workspace:FindFirstChild 'CurrentMap'
  if map and map:IsA 'Model' and map.PrimaryPart then
    if LOG then
      print '[EggWorldSpawn] Using CurrentMap.PrimaryPart'
    end
    return map.PrimaryPart.Position + Vector3.new(0, 3, 0)
  end
  if LOG then
    print '[EggWorldSpawn] No map center; using origin'
  end
  return Vector3.new(0, 6, 0)
end

local function spawnAccordingToMode()
  if SPAWN_MODE == 'map_center' then
    spawnAt(mapCenterPos())
  else
    spawnAt(posNearSpawner())
  end
end

-- ========== BOOT ==========
if FORCE_RESPAWN_ON_BOOT then
  workspace:SetAttribute(SPAWNED_ATTR, nil)
end

-- Spawn once when the first character appears (reliable in Studio)
Players.PlayerAdded:Connect(function(plr)
  plr.CharacterAdded:Connect(function()
    if not workspace:GetAttribute(SPAWNED_ATTR) then
      task.defer(spawnAccordingToMode)
    end
  end)
end)

-- Also try once on server boot
task.delay(1, function()
  if not workspace:GetAttribute(SPAWNED_ATTR) then
    spawnAccordingToMode()
  end
end)

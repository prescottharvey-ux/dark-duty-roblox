--!strict
-- Creates (if missing) a simple Dagger Tool and gives one to each player
-- in StarterGear + Backpack so it’s immediately equipable and persists.

local Players = game:GetService 'Players'
local ServerStorage = game:GetService 'ServerStorage'
local ReplicatedStorage = game:GetService 'ReplicatedStorage'
local StarterPack = game:GetService 'StarterPack'

local DAGGER_NAME = 'Dagger'
local FALLBACK_NAME = 'DebugSword'

local function findToolTemplate(name: string): Tool?
  -- Fast checks
  local candidates = {
    ServerStorage:FindFirstChild(name),
    ReplicatedStorage:FindFirstChild(name),
    StarterPack:FindFirstChild(name),
  }
  for _, inst in ipairs(candidates) do
    if inst and inst:IsA 'Tool' then
      return inst
    end
  end
  -- Wider searches (just in case)
  for _, d in ipairs(ServerStorage:GetDescendants()) do
    if d:IsA 'Tool' and d.Name == name then
      return d
    end
  end
  for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
    if d:IsA 'Tool' and d.Name == name then
      return d
    end
  end
  return nil
end

local function createBareDagger(): Tool
  -- Minimal, fully-equipable Tool w/ Handle.
  local tool = Instance.new 'Tool'
  tool.Name = DAGGER_NAME
  tool.RequiresHandle = true
  tool.CanBeDropped = true

  local handle = Instance.new 'Part'
  handle.Name = 'Handle'
  handle.Size = Vector3.new(0.2, 1.0, 0.2) -- thin + short blade
  handle.Massless = true
  handle.CanCollide = false
  handle.Anchored = false
  handle.TopSurface = Enum.SurfaceType.Smooth
  handle.BottomSurface = Enum.SurfaceType.Smooth
  handle.Color = Color3.fromRGB(200, 200, 200)
  handle.Parent = tool

  -- Optional: a very simple mesh “blade” look (safe to omit)
  local mesh = Instance.new 'SpecialMesh'
  mesh.MeshType = Enum.MeshType.Brick
  mesh.Scale = Vector3.new(0.5, 1.8, 0.5)
  mesh.Parent = handle

  -- Optional: tweak Grip so it’s held near one end of the handle
  tool.Grip = CFrame.new(0, -0.35, 0) * CFrame.Angles(0, math.rad(90), 0)

  tool.Parent = ServerStorage
  warn '[GiveStarterDagger] Created bare Dagger template in ServerStorage.'
  return tool
end

local function getOrCreateDaggerTemplate(): Tool
  -- Prefer a real Dagger…
  local dagger = findToolTemplate(DAGGER_NAME)
  if dagger then
    return dagger
  end

  -- …or clone DebugSword if present…
  local fallback = findToolTemplate(FALLBACK_NAME)
  if fallback then
    local clone = fallback:Clone()
    clone.Name = DAGGER_NAME
    clone.Parent = ServerStorage
    warn '[GiveStarterDagger] Created Dagger by cloning DebugSword.'
    return clone
  end

  -- …or finally synthesize a bare Tool.
  return createBareDagger()
end

local function ensureStarterGearHas(plr: Player, template: Tool)
  local starter = plr:FindFirstChild 'StarterGear'
  if starter and not starter:FindFirstChild(DAGGER_NAME) then
    template:Clone().Parent = starter
  end
end

local function ensureBackpackHas(plr: Player, template: Tool)
  local bp = plr:FindFirstChildOfClass 'Backpack'
  if bp and not bp:FindFirstChild(DAGGER_NAME) then
    template:Clone().Parent = bp
  end
end

local function giveDagger(plr: Player)
  local template = getOrCreateDaggerTemplate()
  ensureStarterGearHas(plr, template)
  ensureBackpackHas(plr, template)
end

Players.PlayerAdded:Connect(function(plr)
  giveDagger(plr)
  plr.CharacterAdded:Connect(function()
    -- Ensure a copy after respawn, too
    giveDagger(plr)
  end)
end)

for _, p in ipairs(Players:GetPlayers()) do
  giveDagger(p)
end

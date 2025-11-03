--!strict
local SSS = game:GetService 'ServerScriptService'
local RS = game:GetService 'ReplicatedStorage'
local Http = game:GetService 'HttpService'

-- For modules that truly need .new(), list them here.
-- Inventory is a singleton (NO .new()).
local FACTORY_PORTS: { [string]: boolean } = {
  Stamina = true,
  Economy = true,
  Locks = true,
  Extraction = true,
  Egg = true,
  Noise = true,
  Combat = true,
  Durability = true,
  Dungeon = true,
  -- Inventory = false (implicit)
}

local function loadPort(folderName: string)
  local folder = SSS:FindFirstChild(folderName)
  if not folder then
    warn('[Bootstrap] Missing folder:', folderName)
    return nil
  end
  local public = folder:FindFirstChild 'Public'
  if not public or not public:IsA 'ModuleScript' then
    warn(
      ('[Bootstrap] %s.Public must be a ModuleScript (found %s)'):format(
        folderName,
        public and public.ClassName or 'none'
      )
    )
    return nil
  end

  local okReq, modOrErr = pcall(require, public)
  if not okReq then
    warn(('[Bootstrap] require failed for %s.Public: %s'):format(folderName, tostring(modOrErr)))
    return nil
  end

  -- Only call .new() for services listed in FACTORY_PORTS and that actually expose a function
  if
    FACTORY_PORTS[folderName]
    and type(modOrErr) == 'table'
    and type(modOrErr.new) == 'function'
  then
    local okNew, portOrErr = pcall(modOrErr.new, modOrErr)
    if not okNew then
      warn(('[Bootstrap] .new() failed for %s.Public: %s'):format(folderName, tostring(portOrErr)))
      return nil
    end
    return portOrErr
  end

  -- Otherwise treat as singleton module (table of functions)
  return modOrErr
end

-- Load all ports
local Inventory = loadPort 'Inventory' -- singleton: NO .new()
local Stamina = loadPort 'Stamina'
local Economy = loadPort 'Economy'
local Locks = loadPort 'Locks'
local Extraction = loadPort 'Extraction'
local Egg = loadPort 'Egg'
local Noise = loadPort 'Noise'
local Combat = loadPort 'Combat'
local Durability = loadPort 'Durability'
local Dungeon = loadPort 'Dungeon'

-- (optional) make Inventory easy to reach for other legacy scripts
_G.Inventory = Inventory

print(
  '[Bootstrap] Loaded:',
  Http:JSONEncode {
    Inventory = Inventory ~= nil,
    Stamina = Stamina ~= nil,
    Economy = Economy ~= nil,
    Locks = Locks ~= nil,
    Extraction = Extraction ~= nil,
    Egg = Egg ~= nil,
    Noise = Noise ~= nil,
    Combat = Combat ~= nil,
    Durability = Durability ~= nil,
    Dungeon = Dungeon ~= nil,
  }
)

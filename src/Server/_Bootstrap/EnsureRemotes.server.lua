local RS = game:GetService 'ReplicatedStorage'

local Remotes = RS:FindFirstChild 'Remotes'
if not Remotes then
  Remotes = Instance.new 'Folder'
  Remotes.Name = 'Remotes'
  Remotes.Parent = RS
end

local REFolder = Remotes:FindFirstChild 'RemoteEvent' or Instance.new('Folder', Remotes)
REFolder.Name = 'RemoteEvent'
local RFFolder = Remotes:FindFirstChild 'RemoteFunction' or Instance.new('Folder', Remotes)
RFFolder.Name = 'RemoteFunction'

local function ensureRE(name)
  local re = REFolder:FindFirstChild(name)
  if not re then
    re = Instance.new 'RemoteEvent'
    re.Name = name
    re.Parent = REFolder
  end
  return re
end

local function ensureRF(name)
  local rf = RFFolder:FindFirstChild(name)
  if not rf then
    rf = Instance.new 'RemoteFunction'
    rf.Name = name
    rf.Parent = RFFolder
  end
  return rf
end

-- Combat client is waiting for this:
ensureRE 'DaggerAttack'

-- HotbarHUD / inventory UI usually wants a snapshot + change pushes
local rfSnapshot = ensureRF 'InventorySnapshot'
ensureRE 'InventoryChanged'

rfSnapshot.OnServerInvoke = function(plr)
  -- Return a minimal but sensible shape so the UI stops complaining.
  return {
    version = 1,
    hotbar = { [1] = nil, [2] = nil, [3] = nil, [4] = nil, [5] = nil },
    carried = {}, -- array of { id = "dagger", qty = 1 } etc.
    equipment = {}, -- map slots -> ids
    weight = 0,
    capacity = 12,
  }
end

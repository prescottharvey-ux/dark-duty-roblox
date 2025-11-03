--!strict
local RS = game:GetService 'ReplicatedStorage'
local Players = game:GetService 'Players'

-- Folders (make sure they exist once on the server)
local Remotes = RS:FindFirstChild 'Remotes' or Instance.new('Folder', RS)
do
  Remotes.Name = 'Remotes'
end
local RFF = Remotes:FindFirstChild 'RemoteFunction' or Instance.new('Folder', Remotes)
do
  RFF.Name = 'RemoteFunction'
end
local REF = Remotes:FindFirstChild 'RemoteEvent' or Instance.new('Folder', Remotes)
do
  REF.Name = 'RemoteEvent'
end

-- Remotes
local HatchRF = RFF:FindFirstChild 'EggHatch' or Instance.new('RemoteFunction', RFF)
do
  HatchRF.Name = 'EggHatch'
end
local HatchNoticeRE = REF:FindFirstChild 'EggNotice' or Instance.new('RemoteEvent', REF)
do
  HatchNoticeRE.Name = 'EggNotice'
end

-- Dependencies
local ItemDB = require(RS:WaitForChild('Modules'):WaitForChild 'ItemDB')
local Inventory =
  require(game:GetService('ServerScriptService'):WaitForChild('Inventory'):WaitForChild 'Public')

-- Simple baby roll (replace with your MonsterDB)
local BabyPool = { 'PetToken_CommonChick', 'PetToken_Slimelet', 'PetToken_Glowbug' }
local function rollBaby(): string
  return BabyPool[math.random(1, #BabyPool)]
end

-- Client calls this from the end-of-run UI to commit the hatch
HatchRF.OnServerInvoke = function(plr, eggItemId: string?)
  eggItemId = eggItemId or 'CommonEgg'
  -- Verify inventory has at least 1 egg carried/owned
  if typeof(Inventory.countOf) == 'function' and Inventory.countOf(plr, eggItemId) <= 0 then
    return false, 'No egg to hatch.'
  end
  -- Remove egg and grant pet token
  if typeof(Inventory.removeItem) == 'function' then
    Inventory.removeItem(plr, eggItemId, 1)
  else
    return false, 'removeItem unavailable'
  end
  local babyId = rollBaby()
  if typeof(Inventory.addItem) == 'function' then
    Inventory.addItem(plr, babyId, 1)
  else
    return false, 'addItem unavailable'
  end

  HatchNoticeRE:FireClient(plr, ('Your egg hatched: %s!'):format(babyId))
  return true, { babyId = babyId }
end

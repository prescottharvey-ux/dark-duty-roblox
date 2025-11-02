-- ServerScriptService/Services/EggService.server.lua
-- Server-authoritative single-slot incubator per player.

local Players = game:GetService 'Players'
local RS = game:GetService 'ReplicatedStorage'
local Remotes = RS:FindFirstChild 'Remotes' or Instance.new('Folder', RS)
Remotes.Name = 'Remotes'
local EggRems = Remotes:FindFirstChild 'Egg' or Instance.new('Folder', Remotes)
EggRems.Name = 'Egg'

local PlaceRF = EggRems:FindFirstChild 'PlaceInIncubator' or Instance.new('RemoteFunction', EggRems)
PlaceRF.Name = 'PlaceInIncubator'
local TakeRF = EggRems:FindFirstChild 'TakeFromIncubator' or Instance.new('RemoteFunction', EggRems)
TakeRF.Name = 'TakeFromIncubator'
local ClaimRF = EggRems:FindFirstChild 'ClaimHatch' or Instance.new('RemoteFunction', EggRems)
ClaimRF.Name = 'ClaimHatch'
local StatusRE = EggRems:FindFirstChild 'StatusChanged' or Instance.new('RemoteEvent', EggRems)
StatusRE.Name = 'StatusChanged'

local ItemDB = require(RS.Modules.ItemDB)
local InventoryService = require(script.Parent:WaitForChild 'InventoryService') -- already optional in your stack

-- Persisted per player (store in your profile/datastore with InventoryService payload)
local incubators = {} :: { [Player]: { itemId: string?, placedAt: number?, hatchAt: number? } }

local function now()
  return os.time()
end

local function broadcastStatus(plr)
  local slot = incubators[plr] or {}
  local remaining = slot.hatchAt and math.max(0, slot.hatchAt - now()) or nil
  StatusRE:FireClient(plr, {
    itemId = slot.itemId,
    placedAt = slot.placedAt,
    hatchAt = slot.hatchAt,
    remaining = remaining,
  })
end

local function validateEggItem(itemId)
  local def = ItemDB[itemId]
  return def and def.type == 'Egg' and def.hatchTimeSec and def.hatchTimeSec > 0
end

PlaceRF.OnServerInvoke = function(plr, invGuid)
  -- Take an egg from inventory and start timer if slot empty
  local slot = incubators[plr] or {}
  incubators[plr] = slot
  if slot.itemId then
    return false, 'Incubator occupied'
  end

  local item = InventoryService:PeekItem(plr, invGuid)
  if not item or not validateEggItem(item.itemId) then
    return false, 'Not an egg'
  end

  local ok, err = InventoryService:RemoveByGuid(plr, invGuid, 1)
  if not ok then
    return false, err or 'Remove failed'
  end

  local def = ItemDB[item.itemId]
  slot.itemId = item.itemId
  slot.placedAt = now()
  slot.hatchAt = slot.placedAt + def.hatchTimeSec

  -- TODO: persist slot via your profile schema

  broadcastStatus(plr)
  -- telemetry: EggPlaced
  return true
end

TakeRF.OnServerInvoke = function(plr)
  local slot = incubators[plr]
  if not slot or not slot.itemId then
    return false, 'Empty'
  end

  -- Return egg to inventory only if not hatched
  if now() >= (slot.hatchAt or 0) then
    return false, 'Already hatched; claim instead'
  end

  local ok, err = InventoryService:Add(plr, slot.itemId, 1)
  if not ok then
    return false, err or 'Add failed'
  end

  incubators[plr] = {} -- clear
  broadcastStatus(plr)
  -- telemetry: EggAbandoned
  return true
end

ClaimRF.OnServerInvoke = function(plr)
  local slot = incubators[plr]
  if not slot or not slot.itemId then
    return false, 'Empty'
  end
  if now() < (slot.hatchAt or math.huge) then
    return false, 'Not ready'
  end

  -- Reward pet token (Phase 0 cosmetic)
  local rewardId = 'PetToken_CommonChick'
  local ok, err = InventoryService:Add(plr, rewardId, 1)
  if not ok then
    return false, err or 'Add failed'
  end

  incubators[plr] = {}
  broadcastStatus(plr)
  -- telemetry: EggClaimed
  return true, rewardId
end

Players.PlayerAdded:Connect(function(plr)
  -- TODO: load incubator state from profile/datastore if present
  incubators[plr] = incubators[plr] or {}
  broadcastStatus(plr)
end)

Players.PlayerRemoving:Connect(function(plr)
  -- TODO: save incubator state
  incubators[plr] = nil
end)

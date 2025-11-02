--!strict
local Players = game:GetService 'Players'
local TextChatService = game:GetService 'TextChatService'
local Bus = require(game.ReplicatedStorage.Events.EventBus)

local ENEMIES = workspace:FindFirstChild 'Enemies'

local function firstEnemyModel(): Model?
  if not ENEMIES then
    return nil
  end
  for _, inst in ipairs(ENEMIES:GetChildren()) do
    if inst:IsA 'Model' and inst:GetAttribute 'HP' ~= nil then
      return inst
    end
  end
  return nil
end

local function handleCommand(plr: Player, text: string)
  text = string.lower(text)
  if text == '/hit' then
    local target = firstEnemyModel()
    if target then
      Bus.publish('combat.hit', { attacker = plr, target = target, damage = 20 })
      print('[Debug] /hit →', target.Name)
    else
      warn '[Debug] /hit: no enemy with HP found under workspace.Enemies'
    end
  elseif text == '/round' then
    -- optionally start the round timer
    local Extraction = require(game.ServerScriptService.Extraction.Public).new()
    Extraction.startRound()
    print '[Debug] /round → Extraction timer started'
  end
end

-- New chat system
if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
  local general = TextChatService:WaitForChild('TextChannels'):WaitForChild 'RBXGeneral'
  general.MessageReceived:Connect(function(message)
    local src = message.TextSource
    if not src then
      return
    end
    local plr = Players:GetPlayerByUserId(src.UserId)
    if plr then
      handleCommand(plr, message.Text)
    end
  end)
else
  -- Fallback: legacy Chat
  Players.PlayerAdded:Connect(function(plr)
    plr.Chatted:Connect(function(msg)
      handleCommand(plr, msg)
    end)
  end)
end

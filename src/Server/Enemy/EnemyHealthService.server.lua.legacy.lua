--!strict
local Bus = require(game.ReplicatedStorage.Events.EventBus)
local Economy = require(game.ServerScriptService.Economy.Public).new()
local DROP = { goblin = 5, skeleton = 3, rat = 0, bat = 0, minotaur = 0 }

local function enemyModelFrom(inst: Instance?): Model?
  if not inst then
    return nil
  end
  if inst:IsA 'Model' and inst:GetAttribute 'HP' ~= nil then
    return inst
  end
  return inst:FindFirstAncestorWhichIsA 'Model'
end

Bus.subscribe('combat.hit', function(e)
  local plr = e.attacker :: Player
  local m = enemyModelFrom(e.target)
  if not (m and m:GetAttribute 'HP' ~= nil) then
    return
  end
  local hp = (m:GetAttribute 'HP' :: number) - (tonumber(e.damage) or 0)
  m:SetAttribute('HP', hp)
  if hp <= 0 then
    local id = (m:GetAttribute 'EnemyId' :: string) or 'unknown'
    if (DROP[id] or 0) > 0 then
      Economy.grant(plr, DROP[id], 'enemy_kill:' .. id)
    end
    m:Destroy()
  end
end)

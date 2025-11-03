-- ReplicatedStorage/Modules/Combat/Combat.lua
local Combat = {}

-- server-side scripts call these; keep signatures stable
function Combat.ApplyMelee(attacker: Player, victim: Instance, data)
-- TODO: real damage rules; for now, fire a bus/event or print
return true
end

function Combat.ApplyNPCHit(npc: Instance, damage: number, source: string?)
-- TODO: real NPC damage; return remaining HP if you want
return true
end

return Combat

--!strict
-- Scales inbound noise using the emitter's NoiseScalar and rebroadcasts to AI.
-- In:  Bus.publish("noise.emitted", {pos=Vector3, loudness=number?, radius=number?, source=string?, actor=Player|Instance?})
-- Out: Bus.publish("ai.noise.heard", {pos=Vector3, radius=number, loudness=number, source=string?, actor:any})

local Players = game:GetService 'Players'
local RS = game:GetService 'ReplicatedStorage'
local Run = game:GetService 'RunService'

local Events = RS:FindFirstChild 'Events' or RS:FindFirstChild 'Modules' or RS
local Bus = require(Events:WaitForChild 'EventBus')

local DEFAULT_BASE_RADIUS = 35
local DEBUG = Run:IsStudio() -- spammy prints only in Studio

local function playerFromActor(actor: any): Player?
  if typeof(actor) ~= 'Instance' then
    return nil
  end
  if actor:IsA 'Player' then
    return actor
  end
  local plr = Players:GetPlayerFromCharacter(actor)
  if plr then
    return plr
  end
  local mdl = actor:FindFirstAncestorOfClass 'Model'
  if mdl then
    plr = Players:GetPlayerFromCharacter(mdl)
  end
  return plr
end

Bus.subscribe('noise.emitted', function(e: any)
  local pos = e and e.pos
  if typeof(pos) ~= 'Vector3' then
    return
  end

  local baseRadius = typeof(e.radius) == 'number' and e.radius or DEFAULT_BASE_RADIUS
  local loudness = typeof(e.loudness) == 'number' and e.loudness or 1

  local plr = playerFromActor(e.actor or e.player or e.sourceActor)
  local scalar = plr and (plr:GetAttribute 'NoiseScalar' or 1.0) or 1.0

  local effR = math.max(0, baseRadius * loudness * scalar)

  if DEBUG then
    local who = plr and plr.Name or tostring(e.actor)
    print(
      ('[NoiseRouter] src=%s actor=%s loud=%.2f scalar=%.2f baseR=%.1f -> effR=%.1f @ (%.1f,%.1f,%.1f)'):format(
        e.source or 'noise',
        who,
        loudness,
        scalar,
        baseRadius,
        effR,
        pos.X,
        pos.Y,
        pos.Z
      )
    )
  end

  Bus.publish('ai.noise.heard', {
    pos = pos,
    radius = effR,
    loudness = loudness,
    source = e.source,
    actor = e.actor or plr,
  })
end)

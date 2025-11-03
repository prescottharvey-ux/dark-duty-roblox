--!strict
-- ServerScriptService/Combat/PlayerDamage.server.lua (bus-driven NPC -> Player hits)
local RS = game:GetService 'ReplicatedStorage'
local Bus = require(RS:WaitForChild('Events'):WaitForChild 'EventBus')

local DEBUG = true
local function log(...)
  if DEBUG then
    print('[PlayerDamage]', ...)
  end
end

-- Optional: remote to drive client-side damage numbers for players
local REFolder = RS:FindFirstChild 'Remotes' or Instance.new 'Folder'
REFolder.Name = 'Remotes'
REFolder.Parent = RS

local REEvents = REFolder:FindFirstChild 'RemoteEvent' or Instance.new 'Folder'
REEvents.Name = 'RemoteEvent'
REEvents.Parent = REFolder

local DamageNumberRE = REEvents:FindFirstChild 'DamageNumber' or Instance.new 'RemoteEvent'
DamageNumberRE.Name = 'DamageNumber'
DamageNumberRE.Parent = REEvents

-- Central damage gate
local Combat = require(RS:WaitForChild('Modules'):WaitForChild('Combat'):WaitForChild 'Combat')

local function asModel(inst: Instance?): Model?
  if not inst then
    return nil
  end
  if inst:IsA 'Model' then
    return inst
  end
  return inst:FindFirstAncestorOfClass 'Model'
end

-- Expected payload: { attacker: Model|Instance, player: Player, damage: number }
Bus.subscribe('combat.player_hit', function(e)
  if type(e) ~= 'table' then
    return
  end

  local plr = e.player
  if not plr or not plr.Character then
    return
  end
  local hum = plr.Character:FindFirstChildOfClass 'Humanoid'
  if not hum or hum.Health <= 0 then
    return
  end

  local dmg = tonumber(e.damage) or 10
  if dmg <= 0 then
    return
  end

  -- Resolve attacker model for telemetry (use victim's model as last resort)
  local attackerModel = asModel(e.attacker) or asModel(hum.Parent)

  -- Route through the central gate (respects IsBlocking, stamina bonus cost via Bus, etc.)
  local res = Combat.ApplyNPCHit(attackerModel :: Model, hum :: Humanoid, dmg)

  if res and res.blocked then
    log(('Blocked hit on %s for %d'):format(plr.Name, dmg))
    return
  end

  local applied = (res and tonumber(res.dmg) or 0)
  if applied > 0 then
    local before = hum.Health + applied -- gate already applied damage
    log(
      ('Hit %s for %d (HP %.0f -> %.0f)'):format(
        plr.Name,
        applied,
        before,
        math.max(0, before - applied)
      )
    )

    -- Spawn a red negative number on the victim client (keep your UX)
    local hrp = plr.Character:FindFirstChild 'HumanoidRootPart'
    if hrp then
      DamageNumberRE:FireClient(plr, hrp.Position + Vector3.new(0, 3, 0), -applied)
    end
  end
end)

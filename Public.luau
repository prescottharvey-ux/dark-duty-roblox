--!strict
-- Stamina/Public.lua
-- Port returns an object with: current(p), setCurrent(p, v), getMax(p), getRegenRate(p)
-- Internally tracks per-player stamina + simple regen. Reads Inventory weight if available.

local Players = game:GetService 'Players'
local RunService = game:GetService 'RunService'

-- Try to read Inventory weight (optional)
local okInv, InventoryPort = pcall(function()
  return require(
    game:GetService('ServerScriptService'):WaitForChild('Inventory'):WaitForChild 'Public'
  ).new()
end)

export type StaminaPort = {
  current: (Player) -> number,
  setCurrent: (Player, number) -> (),
  getMax: (Player) -> number,
  getRegenRate: (Player) -> number,
}

local M = {}

function M.new(): StaminaPort
  local cur: { [number]: number } = {}
  local max: { [number]: number } = {}

  local function ensure(pid: number)
    if max[pid] == nil then
      max[pid] = 100
    end
    if cur[pid] == nil then
      cur[pid] = max[pid]
    end
  end

  local self = {} :: any

  function self.getMax(p: Player): number
    ensure(p.UserId)
    return max[p.UserId]
  end

  function self.getRegenRate(p: Player): number
    -- heavier inventory = slower regen (fallback if no Inventory)
    local w = 0
    if okInv and InventoryPort and typeof(InventoryPort.getWeight) == 'function' then
      w = InventoryPort.getWeight(p)
    end
    -- base 5/s down to min 0.5/s as weight grows
    return math.max(0.5, 5.0 - 0.05 * w)
  end

  function self.current(p: Player): number
    ensure(p.UserId)
    return cur[p.UserId]
  end

  function self.setCurrent(p: Player, v: number)
    ensure(p.UserId)
    local pid = p.UserId
    cur[pid] = math.clamp(v, 0, max[pid])
  end

  -- keep players initialized
  local function onAdded(p: Player)
    ensure(p.UserId)
  end
  local function onRemoving(p: Player)
    cur[p.UserId] = nil
    max[p.UserId] = nil
  end
  Players.PlayerAdded:Connect(onAdded)
  Players.PlayerRemoving:Connect(onRemoving)
  for _, p in ipairs(Players:GetPlayers()) do
    onAdded(p)
  end

  -- simple regen loop
  RunService.Heartbeat:Connect(function(dt)
    for _, p in ipairs(Players:GetPlayers()) do
      local pid = p.UserId
      if cur[pid] ~= nil then
        local regen = self.getRegenRate(p) * dt
        cur[pid] = math.min(cur[pid] + regen, max[pid])
      end
    end
  end)

  return self
end

return M

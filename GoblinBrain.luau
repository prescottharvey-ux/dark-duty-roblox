--!strict
-- GoblinBrain.lua — movement + noise reaction
local PathfindingService = game:GetService 'PathfindingService'
local Players = game:GetService 'Players'
local RS = game:GetService 'ReplicatedStorage'
local Run = game:GetService 'RunService'

local Events = RS:FindFirstChild 'Events' or RS:FindFirstChild 'Modules' or RS
local Bus = require(Events:WaitForChild 'EventBus')

local DEBUG = Run:IsStudio()

export type Brain = {
  start: (self: any) -> (),
  stop: (self: any) -> (),
  setGoal: (self: any, goal: Vector3?) -> (),
  getGoal: (self: any) -> Vector3?,
}

local Brain = {}
Brain.__index = Brain

local PATH_THROTTLE_S = 0.20
local GOAL_REACH_EPS = 6.0
local WANDER_MIN_S = 2.0
local WANDER_MAX_S = 4.0
local WANDER_MIN_D = 10
local WANDER_MAX_D = 20

local function getRoot(model: Model): BasePart?
  return model.PrimaryPart
    or model:FindFirstChild 'HumanoidRootPart'
    or model:FindFirstChildWhichIsA 'BasePart'
end

local function dist(a: Vector3, b: Vector3): number
  return (a - b).Magnitude
end

function Brain.new(model: Model)
  local self = setmetatable({}, Brain)
  self.model = model
  self.hum = model:FindFirstChildOfClass 'Humanoid' :: Humanoid
  self.running = false
  self.goal = nil :: Vector3?
  self.wanderUntil = 0
  self.investigateUntil = 0
  self._noiseSub = nil :: any
  self._lastPathT = 0
  return self
end

function Brain:setGoal(goal: Vector3?)
  self.goal = goal
end

function Brain:getGoal(): Vector3?
  return self.goal
end

local function computePath(from: Vector3, to: Vector3)
  local path = PathfindingService:CreatePath()
  path:ComputeAsync(from, to)
  local way = path.Status == Enum.PathStatus.Success and path:GetWaypoints() or {}
  return way
end

function Brain:_moveToward(pos: Vector3)
  if not (self.hum and self.hum.Health > 0) then
    return
  end
  local root = getRoot(self.model)
  if not root then
    return
  end
  local now = os.clock()
  if now - (self._lastPathT or 0) < PATH_THROTTLE_S then
    return
  end
  self._lastPathT = now

  local way = computePath(root.Position, pos)
  if #way == 0 then
    -- fallback: try direct move
    self.hum:MoveTo(pos)
    return
  end

  -- move to next sensible waypoint (usually the last, but handle short paths)
  local target = way[math.max(1, #way - 0)].Position
  self.hum:MoveTo(target)
end

local function pickWanderFrom(r: BasePart): Vector3
  local dir = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5)
  if dir.Magnitude < 0.1 then
    dir = Vector3.new(1, 0, 0)
  end
  return r.Position + dir.Unit * math.random(WANDER_MIN_D, WANDER_MAX_D)
end

function Brain:start()
  if self.running then
    return
  end
  self.running = true

  -- Noise → investigate
  local unsub
  local function subscribe(fn)
    if typeof(Bus.subscribe) == 'function' then
      return Bus.subscribe('ai.noise.heard', fn)
    end
    if typeof(Bus.On) == 'function' then
      return Bus.On('ai.noise.heard', fn)
    end
    if typeof(Bus.Subscribe) == 'function' then
      return Bus.Subscribe('ai.noise.heard', fn)
    end
    error 'EventBus missing subscribe method'
  end
  unsub = subscribe(function(e: any)
    local r = getRoot(self.model)
    if not r then
      return
    end
    local pos = e and e.pos
    if typeof(pos) ~= 'Vector3' then
      return
    end
    local R = typeof(e.radius) == 'number' and e.radius or 100
    local L = typeof(e.loudness) == 'number' and e.loudness or 1
    local d = dist(r.Position, pos)
    if d <= R then
      self.goal = pos
      self.investigateUntil = os.clock() + math.clamp(3 + 2 * L, 3, 7)
      if DEBUG then
        print(
          ('[GoblinBrain:%s] heard %s d=%.1f <= R=%.1f (L=%.2f) -> investigate %.1fs'):format(
            self.model.Name,
            e.source or 'noise',
            d,
            R,
            L,
            self.investigateUntil - os.clock()
          )
        )
      end
    elseif DEBUG and d <= R + 10 then
      print(
        ('[GoblinBrain:%s] near miss d=%.1f > R=%.1f for %s'):format(
          self.model.Name,
          d,
          R,
          e.source or 'noise'
        )
      )
    end
  end)
  self._noiseSub = unsub

  -- Drive loop
  task.spawn(function()
    while self.running do
      if not (self.hum and self.hum.Parent and self.hum.Health > 0) then
        break
      end
      local r = getRoot(self.model)
      if not r then
        break
      end

      local now = os.clock()
      if self.investigateUntil > now and self.goal then
        if dist(r.Position, self.goal) > GOAL_REACH_EPS then
          self:_moveToward(self.goal)
        end
      else
        if self.wanderUntil <= now then
          self.goal = pickWanderFrom(r)
          self.wanderUntil = now + math.random(WANDER_MIN_S, WANDER_MAX_S)
        elseif self.goal then
          self:_moveToward(self.goal)
        end
      end

      -- proximity aggro nudge (movement only; actual attack decided elsewhere)
      local nearestPos: Vector3? = nil
      local best = math.huge
      for _, p in ipairs(Players:GetPlayers()) do
        local hrp = p.Character and p.Character:FindFirstChild 'HumanoidRootPart' :: BasePart
        local th = p.Character and p.Character:FindFirstChildOfClass 'Humanoid'
        if hrp and th and th.Health > 0 then
          local d = (hrp.Position - r.Position).Magnitude
          if d < best then
            best, nearestPos = d, hrp.Position
          end
        end
      end
      if nearestPos and best < 14 then
        self.goal = nearestPos
      end

      task.wait(0.2)
    end
  end)
end

function Brain:stop()
  self.running = false
  local sub = self._noiseSub
  if sub then
    if typeof(sub) == 'function' then
      sub()
    elseif typeof(sub) == 'Instance' and (sub :: any).Disconnect then
      (sub :: any):Disconnect()
    end
  end
  self._noiseSub = nil
end

return Brain

--!strict
-- Backwards-compatible callable:
--   local Require = require(RS.Modules.Require)
--   local ItemDB  = require(Require("ItemDB")) -- returns ModuleScript (callable contract)
-- Helpers:
--   Require.Module("ItemDB")         -> returns required value (throws on fail)
--   Require.Try("ItemDB")            -> (modOrNil, errOrNil)
--   Require.Exists("UI/ChestUI")     -> boolean
--   Require.Resolve("UI/ChestUI")    -> ModuleScript
--   Require.From(root, "Foo/Bar")    -> ModuleScript under custom root
--   Require.Bus()                    -> EventBus or no-op shim
-- Paths:
--   "UI/ChestUI" or "UI.ChestUI"
--   "@Events/EventBus" (explicit RS root)
--   "@Config/StaminaConfig"

local RS = game:GetService 'ReplicatedStorage'

-- ===== utils =====
local function splitPath(path: string): { string }
  local parts = {}
  for part in string.gmatch(path, '[^/%.]+') do
    if part ~= '' then
      table.insert(parts, part)
    end
  end
  return parts
end

-- Find child named <base> or <base>.lua within timeout (seconds)
local function waitForEither(parent: Instance, base: string, timeout: number): Instance?
  local t0 = os.clock()
  while os.clock() - t0 < timeout do
    local hit = parent:FindFirstChild(base) or parent:FindFirstChild(base .. '.lua')
    if hit then
      return hit
    end
    task.wait()
  end
  return nil
end

-- Resolve an RS child root by name (e.g. "Modules", "Events", "Config")
local function getRSRoot(rootName: string): Instance?
  return RS:FindFirstChild(rootName)
end

-- ===== caches =====
local _instCache: { [string]: Instance } = {}
local _modCache: { [Instance]: any } = {}

-- ===== core resolver (preserves original behavior) =====
local function resolveFrom(root: Instance, parts: { string }, timeout: number): ModuleScript
  assert(#parts > 0, 'Require: empty module path')

  local cursor: Instance = root
  for i, part in ipairs(parts) do
    local nextInst = waitForEither(cursor, part, timeout)
    assert(
      nextInst,
      string.format(
        "Require: missing '%s' under %s (looked for '%s' or '%s.lua')",
        part,
        cursor:GetFullName(),
        part,
        part
      )
    )

    if i < #parts then
      assert(
        nextInst:IsA 'Folder' or nextInst:IsA 'Model',
        string.format(
          "Require: expected Folder/Model at %s while resolving '%s', got %s",
          nextInst:GetFullName(),
          table.concat(parts, '/'),
          nextInst.ClassName
        )
      )
    end
    cursor = nextInst
  end

  assert(
    cursor:IsA 'ModuleScript',
    string.format(
      "Require: expected ModuleScript at %s for '%s', got %s",
      cursor:GetFullName(),
      table.concat(parts, '/'),
      cursor.ClassName
    )
  )
  return cursor :: ModuleScript
end

local function pickRootAndParts(modPath: string): (Instance, { string }, string)
  local timeoutDefault = 5
  -- Explicit root: "@Events/EventBus" -> RS.Events["EventBus"]
  if string.sub(modPath, 1, 1) == '@' then
    local noAt = string.sub(modPath, 2)
    local parts = splitPath(noAt)
    assert(#parts >= 1, "Require: invalid '@Root/...' path")
    local rootName = table.remove(parts, 1)
    local root = getRSRoot(rootName)
    assert(root, ('Require: missing ReplicatedStorage/%s'):format(rootName))
    return root, parts, ('@%s/%s'):format(rootName, table.concat(parts, '/'))
  end

  -- Default: ReplicatedStorage/Modules
  local modules = RS:FindFirstChild 'Modules' or RS:WaitForChild('Modules', timeoutDefault)
  assert(modules, 'Missing ReplicatedStorage/Modules')
  local parts = splitPath(modPath)
  return modules, parts, modPath
end

-- ===== public table (callable) =====
-- NOTE: Removed the callable type-entry that caused the parse error.
-- We keep strict types on functions, but leave the table itself as `any`.

local RequireTbl = {} :: any

-- Keep original contract (callable): returns the ModuleScript instance
local function callable(_, modPath: string, timeoutSec: number?): ModuleScript
  local timeout = timeoutSec or 5
  local _, _, cacheKey = pickRootAndParts(modPath)

  local inst = _instCache[cacheKey]
  if inst and inst.Parent then
    return inst :: ModuleScript
  end

  local root, parts, _ = pickRootAndParts(modPath)
  local resolved = resolveFrom(root, parts, timeout)
  _instCache[cacheKey] = resolved
  return resolved :: ModuleScript
end

-- Explicit alias of the callable
function RequireTbl.Resolve(modPath: string, timeoutSec: number?): ModuleScript
  return callable(nil, modPath, timeoutSec)
end

-- Do the require(...) for you, with caching
function RequireTbl.Module(modPath: string, timeoutSec: number?): any
  local inst = callable(nil, modPath, timeoutSec)
  local cached = _modCache[inst]
  if cached ~= nil then
    return cached
  end
  local ok, val = pcall(require, inst)
  if not ok then
    error(('[Require.Module] require(%s) failed: %s'):format(inst:GetFullName(), tostring(val)))
  end
  _modCache[inst] = val
  return val
end

-- Safe require: never throws
function RequireTbl.Try(modPath: string, timeoutSec: number?): (any?, string?)
  local ok, res = pcall(function()
    return RequireTbl.Module(modPath, timeoutSec)
  end)
  if ok then
    return res, nil
  end
  return nil, tostring(res)
end

-- Boolean existence check (no hard waits)
function RequireTbl.Exists(modPath: string): boolean
  local root, parts, _ = pickRootAndParts(modPath)
  local cursor: Instance = root
  for i, part in ipairs(parts) do
    local hit = cursor:FindFirstChild(part) or cursor:FindFirstChild(part .. '.lua')
    if not hit then
      return false
    end
    if i < #parts and not (hit:IsA 'Folder' or hit:IsA 'Model') then
      return false
    end
    cursor = hit
  end
  return cursor:IsA 'ModuleScript'
end

-- Resolve from an arbitrary root (e.g., RS.Events, RS.Config)
function RequireTbl.From(root: Instance, relPath: string, timeoutSec: number?): ModuleScript
  local timeout = timeoutSec or 5
  local parts = splitPath(relPath)
  return resolveFrom(root, parts, timeout)
end

-- Convenience: EventBus or a no-op shim if missing
function RequireTbl.Bus(): any
  local ok, bus = RequireTbl.Try('@Events/EventBus', 1)
  if ok and bus then
    return bus
  end

  local Events = RS:FindFirstChild 'Events'
  local mod = Events and (Events:FindFirstChild 'EventBus' or Events:FindFirstChild 'EventBus.lua')
  if mod and mod:IsA 'ModuleScript' then
    local ok2, val = pcall(require, mod)
    if ok2 and type(val) == 'table' then
      return val
    end
  end

  warn '[Require.Bus] EventBus not found; returning no-op shim'
  return {
    publish = function() end,
    subscribe = function() end,
    On = function() end,
    Connect = function() end,
    Subscribe = function() end,
    Fire = function() end,
    Emit = function() end,
    Publish = function() end,
  }
end

local Require = setmetatable(RequireTbl, { __call = callable }) :: any
return Require

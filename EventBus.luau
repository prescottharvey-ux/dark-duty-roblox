--!strict
-- ReplicatedStorage/Events/EventBus
-- Canonical API:
--   Bus.publish(name, payload?)
--   Bus.subscribe(name, handler) -> () (unsubscribe)
-- Compatibility aliases:
--   Bus.On/Connect/Subscribe, Bus.Fire/Emit/Publish

type Handler<T> = (T?) -> ()

local Bus = {}
local listeners: { [string]: { Handler<any> } } = {}

-- Internal
local function _publish<T>(name: string, payload: T?)
  local list = listeners[name]
  if not list then
    return
  end
  for _, h in ipairs(list) do
    task.spawn(h, payload :: any)
  end
end

local function _subscribe<T>(name: string, handler: Handler<T>)
  listeners[name] = listeners[name] or {}
  table.insert(listeners[name], handler :: any)
  return function()
    local t = listeners[name]
    if not t then
      return
    end
    for i, h in ipairs(t) do
      if h == handler then
        table.remove(t, i)
        break
      end
    end
  end
end

-- Canonical (dot-callable)
function Bus.publish<T>(name: string, payload: T?)
  _publish(name, payload)
end
function Bus.subscribe<T>(name: string, handler: Handler<T>)
  return _subscribe(name, handler)
end

-- Compatibility aliases (dot-callable)
Bus.On = function<T>(name: string, handler: Handler<T>)
  return _subscribe(name, handler)
end
Bus.Connect = Bus.On
Bus.Subscribe = Bus.On

Bus.Fire = function<T>(name: string, payload: T?)
  _publish(name, payload)
end
Bus.Emit = Bus.Fire
Bus.Publish = Bus.Fire

-- Optional colon-call support
function Bus:On<T>(name: string, handler: Handler<T>)
  return _subscribe(name, handler)
end
function Bus:Connect<T>(name: string, handler: Handler<T>)
  return _subscribe(name, handler)
end
function Bus:Subscribe<T>(name: string, handler: Handler<T>)
  return _subscribe(name, handler)
end
function Bus:Fire<T>(name: string, payload: T?)
  _publish(name, payload)
end
function Bus:Emit<T>(name: string, payload: T?)
  _publish(name, payload)
end
function Bus:Publish<T>(name: string, payload: T?)
  _publish(name, payload)
end

return Bus

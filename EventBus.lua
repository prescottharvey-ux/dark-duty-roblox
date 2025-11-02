-- Lightweight in-process pub/sub using Sleitnick Signal
local ReplicatedStorage = game:GetService 'ReplicatedStorage'
local Signal = require(ReplicatedStorage.Packages.Signal)

local Bus = {}
local topics = {}

local function topic(name: string)
  topics[name] = topics[name] or Signal.new()
  return topics[name]
end

function Bus.on(name: string, fn)
  return topic(name):Connect(fn)
end

function Bus.emit(name: string, ...)
  topic(name):Fire(...)
end

return Bus

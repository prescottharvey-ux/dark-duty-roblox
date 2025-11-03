--!strict
local Http = game:GetService 'HttpService'
local function enc(t)
  return t and Http:JSONEncode(t) or '{}'
end
local M = {}
function M.info(sys, msg, data)
  print(`[I][{sys}] {msg} :: {enc(data)}`)
end
function M.warn(sys, msg, data)
  warn(`[W][{sys}] {msg} :: {enc(data)}`)
end
function M.err(sys, msg, data)
  warn(`[E][{sys}] {msg} :: {enc(data)}`)
end
return M

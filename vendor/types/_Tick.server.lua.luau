--!strict
local M = {}
function M.regen(cur: number, rate: number, dt: number)
  return math.clamp(cur + rate * dt, 0, 100)
end
return M

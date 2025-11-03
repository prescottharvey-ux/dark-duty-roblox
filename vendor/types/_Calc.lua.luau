--!strict
local M = {}
function M.computeWeightFromItems(items: { [string]: number }): number
  local w = 0
  for _, qty in pairs(items) do
    w += qty
  end
  return w
end
return M

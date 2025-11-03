--!strict
local Brain = require(script.Parent:WaitForChild 'GoblinBrain')

local function attach(m: Model)
  if not m:GetAttribute 'IsGoblin' then
    return
  end
  local b = Brain.new(m)
  b:start()
  m.AncestryChanged:Connect(function(_, parent)
    if not parent then
      b:stop()
    end
  end)
end

-- attach existing
for _, m in ipairs(workspace:GetDescendants()) do
  if m:IsA 'Model' and m:GetAttribute 'IsGoblin' then
    attach(m)
  end
end

-- attach future spawns
workspace.DescendantAdded:Connect(function(d)
  if d:IsA 'Model' and d:GetAttribute 'IsGoblin' then
    attach(d)
  end
end)

--!strict
local RunService = game:GetService 'RunService'
local EN = workspace:WaitForChild 'Enemies'

local function attach(m: Model)
  local part = m.PrimaryPart or m:FindFirstChildWhichIsA 'BasePart'
  if not part then
    return
  end
  local gui = Instance.new 'BillboardGui'
  gui.Name = 'HPBillboard'
  gui.AlwaysOnTop = true
  gui.Size = UDim2.fromOffset(120, 30)
  gui.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
  gui.Adornee = part
  gui.Parent = part

  local label = Instance.new 'TextLabel'
  label.Size = UDim2.fromScale(1, 1)
  label.BackgroundTransparency = 1
  label.TextScaled = true
  label.Font = Enum.Font.GothamBold
  label.TextColor3 = Color3.new(1, 1, 1)
  label.TextStrokeTransparency = 0.5
  label.Parent = gui

  -- update each frame
  RunService.Heartbeat:Connect(function()
    local hp = m:GetAttribute 'HP'
    if hp == nil then
      return
    end
    label.Text = ('HP: %d'):format(hp)
  end)
end

for _, m in ipairs(EN:GetChildren()) do
  if m:IsA 'Model' and m:GetAttribute 'HP' ~= nil then
    attach(m)
  end
end
EN.ChildAdded:Connect(function(c)
  if c:IsA 'Model' then
    task.wait()
    if c:GetAttribute 'HP' ~= nil then
      attach(c)
    end
  end
end)

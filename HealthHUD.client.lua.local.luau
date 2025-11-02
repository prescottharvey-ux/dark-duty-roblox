--!strict
local Players = game:GetService 'Players'
local plr = Players.LocalPlayer

local gui = Instance.new 'ScreenGui'
gui.Name = 'HealthHUD'
gui.ResetOnSpawn = false
gui.Parent = plr:WaitForChild 'PlayerGui'

local bar = Instance.new 'Frame'
bar.AnchorPoint = Vector2.new(0, 1)
bar.Position = UDim2.new(0, 20, 1, -20)
bar.Size = UDim2.new(0, 240, 0, 16)
bar.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
bar.BorderSizePixel = 0
bar.Parent = gui

local fill = Instance.new 'Frame'
fill.Size = UDim2.fromScale(1, 1)
fill.BackgroundColor3 = Color3.fromRGB(220, 70, 70)
fill.BorderSizePixel = 0
fill.Parent = bar

local label = Instance.new 'TextLabel'
label.BackgroundTransparency = 1
label.Size = UDim2.fromScale(1, 1)
label.TextColor3 = Color3.new(1, 1, 1)
label.Font = Enum.Font.GothamBold
label.TextScaled = true
label.Text = 'HP'
label.Parent = bar

local function bindHumanoid(h: Humanoid)
  local function update()
    local frac = math.clamp(h.Health / math.max(1, h.MaxHealth), 0, 1)
    fill.Size = UDim2.new(frac, 0, 1, 0)
    label.Text = ('HP %d/%d'):format(math.floor(h.Health + 0.5), math.floor(h.MaxHealth + 0.5))
  end
  update()
  h.HealthChanged:Connect(update)
end

local function onCharacter(c: Model)
  local hum = c:WaitForChild 'Humanoid' :: Humanoid
  bindHumanoid(hum)
end

if plr.Character then
  onCharacter(plr.Character)
end
plr.CharacterAdded:Connect(onCharacter)

--!strict
local RS = game:GetService 'ReplicatedStorage'
local RunService = game:GetService 'RunService'
local Bus = require(RS.Events.EventBus)
local Extraction = require(game.ServerScriptService.Extraction.Public).new()

local E1, E2 = 2 * 60, 4 * 60
Extraction.startRound()

local EXITS = workspace:FindFirstChild 'Exits' or Instance.new('Folder', workspace)
EXITS.Name = 'Exits'

local function ensurePromptAndBoard(part: BasePart)
  local p = part:FindFirstChildOfClass 'ProximityPrompt'
  if not p then
    p = Instance.new 'ProximityPrompt'
    p.ActionText = 'Extract'
    p.Enabled = false
    p.Parent = part
  end
  local gui = part:FindFirstChild 'ExitBillboard'
  if not gui then
    gui = Instance.new 'BillboardGui'
    gui.Name = 'ExitBillboard'
    gui.AlwaysOnTop = true
    gui.Size = UDim2.fromOffset(160, 40)
    gui.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
    gui.Adornee = part
    gui.Parent = part
    local label = Instance.new 'TextLabel'
    label.Name = 'Label'
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.TextColor3 = Color3.new(1, 1, 1)
    label.TextStrokeTransparency = 0.5
    label.Parent = gui
  end
  return p, gui.Label :: TextLabel
end

local function firstBasePart(m: Model): BasePart?
  for _, d in ipairs(m:GetDescendants()) do
    if d:IsA 'BasePart' then
      return d
    end
  end
  return nil
end

local opened = false
Bus.subscribe('extraction.exit.opened', function(_)
  opened = true
end)

-- update text every frame
local elapsed = 0
RunService.Heartbeat:Connect(function(dt)
  elapsed += dt
  for _, m in ipairs(EXITS:GetChildren()) do
    if not m:IsA 'Model' then
      continue
    end
    local part = firstBasePart(m)
    if not part then
      continue
    end
    local prompt, label = ensurePromptAndBoard(part)
    if opened then
      label.Text = 'EXIT OPEN'
      prompt.Enabled = true
    else
      local t1 = math.max(0, E1 - elapsed)
      local t2 = math.max(0, E2 - elapsed)
      local nextOpen = (t1 > 0) and t1 or ((t2 > 0) and t2 or 0)
      label.Text = string.format('Exit opens in %.1fs', nextOpen)
      if nextOpen <= 0 then
        prompt.Enabled = true
      end
    end
  end
end)

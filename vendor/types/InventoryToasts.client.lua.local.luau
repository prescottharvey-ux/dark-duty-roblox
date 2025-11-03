--!strict
local Players = game:GetService 'Players'
local RS = game:GetService 'ReplicatedStorage'
local plr = Players.LocalPlayer

local RE = RS:WaitForChild('Remotes'):WaitForChild 'RemoteEvent'
local InvRE = RE:WaitForChild 'InventoryNotice' :: RemoteEvent

local gui = Instance.new 'ScreenGui'
gui.Name = 'InventoryToasts'
gui.ResetOnSpawn = false
gui.Parent = plr:WaitForChild 'PlayerGui'

local toast = Instance.new 'TextLabel'
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Position = UDim2.fromScale(0.5, 0.16)
toast.Size = UDim2.new(0, 560, 0, 36)
toast.BackgroundTransparency = 0.2
toast.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
toast.TextColor3 = Color3.fromRGB(240, 240, 240)
toast.TextStrokeTransparency = 0.5
toast.Font = Enum.Font.GothamSemibold
toast.TextScaled = true
toast.Visible = false
toast.Parent = gui

local function show(msg: string, secs: number?)
  toast.Text = msg
  toast.Visible = true
  task.delay(secs or 2.5, function()
    toast.Visible = false
  end)
end

InvRE.OnClientEvent:Connect(function(tag: string, data: any)
  if tag == 'extracted' then
    local msg = 'Extracted → sent to stash: ' .. (data.summary or '(nothing)')
    show(msg, 3)
  end
end)

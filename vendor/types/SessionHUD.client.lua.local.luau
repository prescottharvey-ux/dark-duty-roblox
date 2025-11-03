--!strict
-- Single source of truth: RS.Remotes.RemoteEvent.Session
local Players = game:GetService 'Players'
local StarterGui = game:GetService 'StarterGui'
local RS = game:GetService 'ReplicatedStorage'

local Bucket = RS:WaitForChild('Remotes'):WaitForChild 'RemoteEvent'
local SessionRE = Bucket:WaitForChild 'Session' :: RemoteEvent
local plr = Players.LocalPlayer

-- Reuse if it already exists (avoid double HUDs when play-testing)
local pg = plr:WaitForChild 'PlayerGui'
local gui = pg:FindFirstChild 'SessionHUD' :: ScreenGui
if not gui then
  gui = Instance.new 'ScreenGui'
  gui.Name = 'SessionHUD'
  gui.ResetOnSpawn = false
  gui.Parent = pg
end

local timerLabel = gui:FindFirstChild 'TimerLabel' :: TextLabel
if not timerLabel then
  timerLabel = Instance.new 'TextLabel'
  timerLabel.Name = 'TimerLabel'
  timerLabel.AnchorPoint = Vector2.new(0.5, 0)
  timerLabel.Position = UDim2.fromScale(0.5, 0.02)
  timerLabel.Size = UDim2.fromOffset(160, 36)
  timerLabel.BackgroundTransparency = 0.4
  timerLabel.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
  timerLabel.TextColor3 = Color3.new(1, 1, 1)
  timerLabel.Font = Enum.Font.GothamBold
  timerLabel.TextScaled = true
  timerLabel.Text = '06:00'
  timerLabel.Parent = gui
end

local function mmss(sec: number): string
  sec = math.max(0, math.floor(sec))
  local m = math.floor(sec / 60)
  local s = sec % 60
  return string.format('%02d:%02d', m, s)
end

local function toast(title: string, text: string, dur: number)
  pcall(function()
    StarterGui:SetCore('SendNotification', { Title = title, Text = text, Duration = dur or 2 })
  end)
end

-- Drain + display
SessionRE.OnClientEvent:Connect(function(tag: string, data: any)
  if tag == 'timer' then
    -- Server sends whole seconds at 1 Hz → no jitter
    local secs = (typeof(data) == 'number') and data or tonumber(data) or 0
    timerLabel.Text = mmss(secs)
  elseif tag == 'exit_open' then
    local name = tostring(data or 'Exit')
    toast('Exit Open', name .. ' is now open', 2)
  elseif tag == 'ended' then
    local reason = tostring(data or 'time_up'):gsub('_', ' ')
    toast('Round Ended', reason, 3)
  elseif tag == 'extracted' then
    -- Optional: show extraction toasts
    local who = (type(data) == 'table' and (data.name or ('User ' .. tostring(data.userId))))
      or 'Player'
    local exit = (type(data) == 'table' and data.exit) or 'Exit'
    toast('Extracted', string.format('%s via %s', who, exit), 2.5)
  end
end)

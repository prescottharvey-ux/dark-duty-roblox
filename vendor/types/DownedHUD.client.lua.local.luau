--!strict
local Players = game:GetService 'Players'
local RS = game:GetService 'ReplicatedStorage'
local plr = Players.LocalPlayer

local RE = RS:WaitForChild('Remotes'):WaitForChild 'RemoteEvent'
local DownedNotice = RE:WaitForChild 'DownedNotice' :: RemoteEvent

local gui = Instance.new 'ScreenGui'
gui.Name = 'DownedHUD'
gui.ResetOnSpawn = false
gui.Enabled = true
gui.Parent = plr:WaitForChild 'PlayerGui'

local frame = Instance.new 'Frame'
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.Position = UDim2.fromScale(0.5, 0.85)
frame.Size = UDim2.new(0, 360, 0, 46)
frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
frame.BorderSizePixel = 0
frame.Visible = false
frame.Parent = gui

local fill = Instance.new 'Frame'
fill.Size = UDim2.new(1, 0, 1, 0)
fill.BackgroundColor3 = Color3.fromRGB(220, 80, 80)
fill.BorderSizePixel = 0
fill.Parent = frame

local label = Instance.new 'TextLabel'
label.BackgroundTransparency = 1
label.Size = UDim2.fromScale(1, 1)
label.TextColor3 = Color3.new(1, 1, 1)
label.Font = Enum.Font.GothamBold
label.TextScaled = true
label.Text = 'DOWNED'
label.Parent = frame

local pausedBlink = false
local trackingUserId: number? = nil
local totalSeconds = 15

local function update(secondsLeft: number, paused: boolean)
  if not trackingUserId then
    return
  end
  local frac = math.clamp(secondsLeft / totalSeconds, 0, 1)
  fill.Size = UDim2.new(frac, 0, 1, 0)
  local base = ('DOWNED – %.0fs'):format(math.ceil(secondsLeft))
  if paused then
    pausedBlink = not pausedBlink
    label.Text = base .. (pausedBlink and ' (REVIVING…)' or ' (REVIVING)')
  else
    label.Text = base
  end
end

DownedNotice.OnClientEvent:Connect(function(tag: string, data)
  if tag == 'start' then
    if data.userId == plr.UserId then
      trackingUserId = data.userId
      totalSeconds = data.seconds or 15
      frame.Visible = true
      update(totalSeconds, false)
    end
  elseif tag == 'tick' then
    if trackingUserId and data.userId == trackingUserId then
      update(data.seconds or 0, data.paused == true)
      if (data.seconds or 0) <= 0 then
        -- safety: hide at 0
        frame.Visible = false
        trackingUserId = nil
      end
    end
  elseif tag == 'paused' then
    if trackingUserId and data.userId == trackingUserId then
      update(math.huge, data.paused == true) -- will be corrected on next tick
    end
  elseif tag == 'end' then
    if trackingUserId and data.userId == trackingUserId then
      frame.Visible = false
      trackingUserId = nil
    end
  end
end)

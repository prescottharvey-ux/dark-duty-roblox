--!strict
-- StarterPlayerScripts/DamageNumbers.client.lua
local Players = game:GetService 'Players'
local RS = game:GetService 'ReplicatedStorage'
local RunService = game:GetService 'RunService'
local Workspace = game:GetService 'Workspace'

local plr = Players.LocalPlayer

local RE = RS:WaitForChild('Remotes'):WaitForChild 'RemoteEvent'
local DamageNumberRE = RE:WaitForChild 'DamageNumber' :: RemoteEvent

-- Colors (preserve original positive/negative styling; crit is optional)
local POS_COLOR = Color3.fromRGB(80, 255, 120)
local NEG_COLOR = Color3.fromRGB(255, 80, 80)
local CRIT_COLOR = Color3.fromRGB(255, 230, 120)

-- helper to spawn a transient BillboardGui number
local function spawnNumber(worldPos: Vector3, value: number, isCrit: boolean?)
  local bill = Instance.new 'BillboardGui'
  bill.Size = UDim2.new(0, 100, 0, 40)
  bill.StudsOffset = Vector3.new(0, 0, 0)
  bill.AlwaysOnTop = true
  bill.MaxDistance = 100
  bill.Adornee = nil

  local txt = Instance.new 'TextLabel'
  txt.BackgroundTransparency = 1
  txt.Size = UDim2.fromScale(1, 1)
  txt.TextScaled = true
  txt.Font = Enum.Font.GothamBold
  txt.Text = (value > 0 and '+' or '') .. tostring(value)
  txt.TextColor3 = isCrit and CRIT_COLOR or ((value < 0) and NEG_COLOR or POS_COLOR)
  txt.Parent = bill

  -- use an invisible attachment at the position so it follows nicely
  local a = Instance.new 'Attachment'
  local p = Instance.new 'Part'
  p.Anchored = true
  p.CanCollide = false
  p.Transparency = 1
  p.Size = Vector3.new(0.2, 0.2, 0.2)
  p.Position = worldPos
  a.Parent = p
  bill.Parent = p
  bill.Adornee = a
  p.Parent = Workspace

  -- tween upward and fade (lifespan ~0.9s, fade over ~0.8s)
  local t0 = tick()
  local conn: RBXScriptConnection? = nil
  conn = RunService.Heartbeat:Connect(function()
    if not p.Parent then
      if conn then
        conn:Disconnect()
      end
      return
    end
    local dt = tick() - t0
    p.Position = worldPos + Vector3.new(0, dt * 2, 0)
    txt.TextTransparency = math.clamp(dt / 0.8, 0, 1)
    if dt > 0.9 then
      if conn then
        conn:Disconnect()
      end
      p:Destroy()
    end
  end)
end

-- Listen for server-emitted damage numbers (used for player hits now)
-- Supports optional 3rd arg: isCrit:boolean
DamageNumberRE.OnClientEvent:Connect(function(pos: Vector3, amount: number, isCrit: boolean?)
  if typeof(pos) ~= 'Vector3' or typeof(amount) ~= 'number' then
    return
  end
  spawnNumber(pos, amount, isCrit == true)
end)

local Players = game:GetService 'Players'
local UserInputService = game:GetService 'UserInputService'
local RS = game:GetService 'ReplicatedStorage'
local RE = RS:WaitForChild('Remotes'):WaitForChild('RemoteEvent'):WaitForChild 'DebugSwordHit'

local player = Players.LocalPlayer

local function getHit()
  local mouse = player:GetMouse()
  return mouse.Target
end

UserInputService.InputBegan:Connect(function(input, gp)
  if gp then
    return
  end
  if input.UserInputType == Enum.UserInputType.MouseButton1 then
    RE:FireServer {
      weaponId = 'DebugSword', -- or whatever you want to test
      target = getHit(),
    }
  end
end)

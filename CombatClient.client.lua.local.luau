--!strict
-- StarterPlayerScripts/CombatClient.client.lua
local RS = game:GetService 'ReplicatedStorage'
local UIS = game:GetService 'UserInputService'

local REFolder = RS:WaitForChild('Remotes'):WaitForChild 'RemoteEvent'
local RE_DaggerAttack = REFolder:WaitForChild 'DaggerAttack' :: RemoteEvent
local RE_StartBlock = REFolder:WaitForChild 'StartBlock' :: RemoteEvent
local RE_StopBlock = REFolder:WaitForChild 'StopBlock' :: RemoteEvent

-- LMB = stab
UIS.InputBegan:Connect(function(io, gpe)
  if gpe then
    return
  end
  if io.UserInputType == Enum.UserInputType.MouseButton1 then
    RE_DaggerAttack:FireServer()
  end
  if io.UserInputType == Enum.UserInputType.MouseButton2 then
    RE_StartBlock:FireServer()
  end
end)

UIS.InputEnded:Connect(function(io, gpe)
  if gpe then
    return
  end
  if io.UserInputType == Enum.UserInputType.MouseButton2 then
    RE_StopBlock:FireServer()
  end
end)

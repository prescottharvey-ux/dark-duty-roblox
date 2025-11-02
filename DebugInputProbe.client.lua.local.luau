-- DebugInputProbe.client.lua (remove after testing)
local UIS = game:GetService 'UserInputService'
UIS.InputBegan:Connect(function(i, gp)
  if i.UserInputType == Enum.UserInputType.Keyboard then
    if
      i.KeyCode == Enum.KeyCode.W
      or i.KeyCode == Enum.KeyCode.A
      or i.KeyCode == Enum.KeyCode.S
      or i.KeyCode == Enum.KeyCode.D
    then
      print('[Probe] WASD InputBegan', i.KeyCode.Name, 'gameProcessed=', gp)
    end
  end
end)

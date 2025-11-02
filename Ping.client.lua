-- Fires a ping to the server and prints the reply
local ReplicatedStorage = game:GetService 'ReplicatedStorage'
local Ping = ReplicatedStorage:WaitForChild 'Ping'

Ping.OnClientEvent:Connect(function(msg)
  print('[Client] got:', msg)
end)

task.delay(1, function()
  Ping:FireServer 'Hello from client'
end)

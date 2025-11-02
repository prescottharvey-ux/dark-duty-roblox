-- Creates a RemoteEvent "Ping" and wires basic echo logic
local ReplicatedStorage = game:GetService 'ReplicatedStorage'

local function ensureRemoteEvent(name: string)
  local ev = ReplicatedStorage:FindFirstChild(name)
  if not ev then
    ev = Instance.new 'RemoteEvent'
    ev.Name = name
    ev.Parent = ReplicatedStorage
  end
  return ev
end

local Ping = ensureRemoteEvent 'Ping'

Ping.OnServerEvent:Connect(function(player, payload)
  print(('[Server] got ping from %s: %s'):format(player.Name, tostring(payload)))
  Ping:FireClient(player, 'Pong!')
end)

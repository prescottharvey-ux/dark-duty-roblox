--!strict
local Players = game:GetService 'Players'
local RS = game:GetService 'ReplicatedStorage'
local plr = Players.LocalPlayer

local DurFolder = RS:WaitForChild('Remotes'):WaitForChild 'Durability'
local Changed = DurFolder:WaitForChild 'Changed' :: RemoteEvent
-- TODO: wire into your inventory/hotbar UI lookup and draw condition bars / color states.

Changed.OnClientEvent:Connect(function(payload)
  -- payload = { uid, id, cur, max, zero, reason }
  -- Example: print + TODO: call your UI update
  print(
    ('[Dur] %s (%s) %d/%d (%s)'):format(
      payload.id,
      payload.uid,
      payload.cur,
      payload.max,
      payload.reason
    )
  )
end)

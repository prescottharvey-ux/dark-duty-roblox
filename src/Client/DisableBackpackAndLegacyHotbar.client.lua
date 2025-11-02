-- StarterPlayerScripts/DisableBackpackAndLegacyHotbar.client.lua
local Players = game:GetService 'Players'
local StarterGui = game:GetService 'StarterGui'
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)

local pg = Players.LocalPlayer:WaitForChild 'PlayerGui'
local function hideLegacy()
  for _, gui in ipairs(pg:GetChildren()) do
    if gui:IsA 'ScreenGui' then
      local cand = gui:FindFirstChild 'Hotbar'
        or gui:FindFirstChild 'Quickbar'
        or gui:FindFirstChild 'QuickSlots'
        or gui:FindFirstChild 'ActionBar'
      if cand and cand:IsA 'GuiObject' then
        warn('[Hotbar] Hiding legacy quickbar:', gui.Name .. '.' .. cand.Name)
        cand.Visible = false
      end
    end
  end
end

pg.DescendantAdded:Connect(function(d)
  if
    d:IsA 'GuiObject'
    and (d.Name:match 'Hotbar' or d.Name:match 'Quick' or d.Name:match 'Action')
  then
    task.defer(hideLegacy)
  end
end)

task.defer(hideLegacy)

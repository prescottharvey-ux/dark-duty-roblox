-- PlayerScripts/Debug/CASWatch.client.lua
local CAS = game:GetService 'ContextActionService'
local UIS = game:GetService 'UserInputService'
local Players = game:GetService 'Players'
local me = Players.LocalPlayer
local playerGui = Players.LocalPlayer:WaitForChild 'PlayerGui'

local function dumpCAS()
  if CAS.GetAllBoundActionInfo then
    for _, info in pairs(CAS:GetAllBoundActionInfo()) do
      local names = {}
      for _, t in ipairs(info.inputTypes or {}) do
        table.insert(names, tostring(t))
      end
      warn(
        ('[CAS] action=%s priority=%s inputs={%s}'):format(
          tostring(info.actionName),
          tostring(info.priority),
          table.concat(names, ', ')
        )
      )
    end
  else
    warn '[CAS] GetAllBoundActionInfo not available in this Studio version.'
  end
end

local function warnModalGuis()
  local pg = me:FindFirstChildOfClass 'PlayerGui'
  if not pg then
    return
  end
  for _, g in ipairs(pg:GetChildren()) do
    if g:IsA 'ScreenGui' and g.Enabled and g.Modal then
      warn('[GUI] Modal ScreenGui eating input: ', g:GetFullName())
    end
  end
end

local function hasModal(screenGui: ScreenGui): boolean
  local ok, value = pcall(function()
    return screenGui.Modal
  end)
  return ok and value == true
end

for _, gui in ipairs(playerGui:GetChildren()) do
  if gui:IsA 'ScreenGui' then
    if gui.Name ~= 'Freecam' and hasModal(gui) then
      -- your logging here
    end
  end
end

UIS.InputBegan:Connect(function(io, gp)
  local kc = io.KeyCode
  if
    (kc == Enum.KeyCode.W or kc == Enum.KeyCode.A or kc == Enum.KeyCode.S or kc == Enum.KeyCode.D)
    and gp
  then
    warn '[CAS] WASD gameProcessed=true → dumping bound actions + modal GUIs'
    dumpCAS()
    warnModalGuis()
  end
end)

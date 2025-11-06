--!strict
-- PlayerScripts/UIInputBlocker.client.lua
-- Blocks movement/ability inputs while StashUI or PaperDollUI are open.
-- Also frees the mouse and switches camera to Classic, then restores.

local Players = game:GetService 'Players'
local UIS = game:GetService 'UserInputService'
local CAS = game:GetService 'ContextActionService'

local plr = Players.LocalPlayer
local pg = plr:WaitForChild 'PlayerGui'

-- Default Roblox controls (if present)
local Controls
do
  local ok, PlayerModule = pcall(function()
    return require(plr:WaitForChild('PlayerScripts'):WaitForChild 'PlayerModule')
  end)
  if ok and PlayerModule and PlayerModule.GetControls then
    Controls = PlayerModule:GetControls()
  end
end

local ACTION = 'UI_BLOCK_INPUT'

local prevMB = UIS.MouseBehavior
local prevMI = UIS.MouseIconEnabled
local prevCamMode = plr.CameraMode

local function sink(_name, _state, _io)
  return Enum.ContextActionResult.Sink
end

local function setBlocked(on: boolean)
  if on then
    if Controls and Controls.Disable then
      Controls:Disable()
    end
    prevMB, prevMI = UIS.MouseBehavior, UIS.MouseIconEnabled
    UIS.MouseBehavior = Enum.MouseBehavior.Default
    UIS.MouseIconEnabled = true
    prevCamMode = plr.CameraMode
    plr.CameraMode = Enum.CameraMode.Classic

    CAS:BindActionAtPriority(
      ACTION,
      sink,
      false,
      Enum.ContextActionPriority.High.Value,
      -- mouse
      Enum.UserInputType.MouseButton1,
      Enum.UserInputType.MouseButton2,
      Enum.UserInputType.MouseMovement,
      -- kb move / jump / sprint
      Enum.KeyCode.W,
      Enum.KeyCode.A,
      Enum.KeyCode.S,
      Enum.KeyCode.D,
      Enum.KeyCode.Up,
      Enum.KeyCode.Down,
      Enum.KeyCode.Left,
      Enum.KeyCode.Right,
      Enum.KeyCode.Space,
      Enum.KeyCode.LeftShift,
      -- ability keys
      Enum.KeyCode.E,
      Enum.KeyCode.R,
      Enum.KeyCode.F,
      Enum.KeyCode.One,
      Enum.KeyCode.Two,
      Enum.KeyCode.Three,
      Enum.KeyCode.Four,
      Enum.KeyCode.Five,
      -- gamepad
      Enum.KeyCode.Thumbstick1,
      Enum.KeyCode.Thumbstick2,
      Enum.KeyCode.ButtonA,
      Enum.KeyCode.ButtonB,
      Enum.KeyCode.DPadUp,
      Enum.KeyCode.DPadDown,
      Enum.KeyCode.DPadLeft,
      Enum.KeyCode.DPadRight
    )
  else
    CAS:UnbindAction(ACTION)
    if Controls and Controls.Enable then
      Controls:Enable()
    end
    UIS.MouseBehavior = prevMB
    UIS.MouseIconEnabled = prevMI
    plr.CameraMode = prevCamMode
  end
end

local function modalOpen(): boolean
  local stash = pg:FindFirstChild 'StashUI'
  local doll = pg:FindFirstChild 'PaperDollUI'
  return (stash and stash:IsA 'ScreenGui' and stash.Enabled)
    or (doll and doll:IsA 'ScreenGui' and doll.Enabled)
    or false
end

local function recompute()
  setBlocked(modalOpen())
end

local function watchGui(gui: ScreenGui)
  if gui.Name ~= 'StashUI' and gui.Name ~= 'PaperDollUI' then
    return
  end

  gui:GetPropertyChangedSignal('Enabled'):Connect(recompute)
  if gui.Destroying then
    gui.Destroying:Connect(recompute)
  else
    gui.AncestryChanged:Connect(function()
      task.defer(recompute)
    end)
  end
  task.defer(recompute)
end

for _, child in ipairs(pg:GetChildren()) do
  if child:IsA 'ScreenGui' then
    watchGui(child)
  end
end

pg.ChildAdded:Connect(function(c)
  if c:IsA 'ScreenGui' then
    watchGui(c)
  end
end)

pg.ChildRemoved:Connect(function(c)
  if c:IsA 'ScreenGui' and (c.Name == 'StashUI' or c.Name == 'PaperDollUI') then
    task.defer(recompute)
  end
end)

task.defer(recompute)

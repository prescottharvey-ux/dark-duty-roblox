--!strict
-- LMB tap  = normal attack (all weapons)
-- LMB hold = charged attack for Dagger only
-- If charge animations are missing, uses code-driven "raise + bob".
-- Supports RightGrip as Motor6D (Transform) OR Weld (C0).

local RS = game:GetService 'ReplicatedStorage'
local Players = game:GetService 'Players'
local UIS = game:GetService 'UserInputService'
local RunService = game:GetService 'RunService'
local TweenService = game:GetService 'TweenService'

local plr = Players.LocalPlayer
local mouse = plr:GetMouse()

-- ===== Remotes (CombatSwing OR DebugSwordHit) =====
local Remotes = RS:WaitForChild 'Remotes'
local REF = Remotes:WaitForChild 'RemoteEvent'

local SwingRE: RemoteEvent = (
  REF:FindFirstChild 'CombatSwing' or REF:FindFirstChild 'DebugSwordHit'
) :: RemoteEvent
if not SwingRE then
  error '[Melee.client] Missing swing RemoteEvent under Remotes/RemoteEvent'
end

-- NEW: optional charge-notify remote (safe if missing)
local ChargeRE: RemoteEvent? = REF:FindFirstChild 'CombatCharge' :: RemoteEvent?

local function fireCharge(kind: 'start' | 'end', wid: string)
  if ChargeRE then
    ChargeRE:FireServer(kind, { weaponId = wid })
  end
end

-- ===== WeaponStats (for charge duration if exposed) =====
local WeaponStatsOk, WeaponStats = pcall(function()
  return require(RS:WaitForChild('Modules'):WaitForChild 'WeaponStats')
end)

local CHARGE_REQ = 5.0
if WeaponStatsOk and WeaponStats and typeof(WeaponStats.getChargeSpec) == 'function' then
  local spec = WeaponStats.getChargeSpec 'Dagger'
  if spec and typeof(spec.requiredHold) == 'number' then
    CHARGE_REQ = spec.requiredHold
  end
end

-- ===== Animation lookups (optional assets) =====
local ANIM_NAMES = {
  raise = { 'DaggerRaise', 'Dagger_Raise', 'Raise', 'ChargeStart' },
  hold = { 'DaggerHold', 'Dagger_Hold', 'Hold', 'ChargeLoop' },
}

-- ===== Client cooldown (server also gates) =====
local CLIENT_COOLDOWN = 0.12
local lastFired = 0

-- ===== Charging state =====
local charging = false
local chargeStart = 0.0
local chargeConn: RBXScriptConnection? = nil

-- ===== Animation state =====
local currentRaiseTrack: AnimationTrack? = nil
local currentHoldTrack: AnimationTrack? = nil

-- ===== Procedural pose state =====
local procConn: RBXScriptConnection? = nil
local procTween: Tween? = nil
local usingProcedural = false

-- ===== Minimal progress UI =====
local gui: ScreenGui? = nil
local bar: Frame? = nil

local function ensureGui()
  if gui then
    return
  end
  gui = Instance.new 'ScreenGui'
  gui.Name = 'ChargeUI'
  gui.ResetOnSpawn = false
  gui.IgnoreGuiInset = true
  gui.Parent = plr:WaitForChild 'PlayerGui'

  local holder = Instance.new 'Frame'
  holder.Name = 'Holder'
  holder.AnchorPoint = Vector2.new(0.5, 1.0)
  holder.Position = UDim2.new(0.5, 0, 1, -40)
  holder.Size = UDim2.new(0, 300, 0, 10)
  holder.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
  holder.BorderSizePixel = 0
  holder.Parent = gui

  local stroke = Instance.new 'UIStroke'
  stroke.Thickness = 1
  stroke.Color = Color3.fromRGB(80, 80, 80)
  stroke.Parent = holder

  bar = Instance.new 'Frame'
  bar.Name = 'Bar'
  bar.Size = UDim2.new(0, 0, 1, 0)
  bar.BackgroundColor3 = Color3.fromRGB(240, 240, 240)
  bar.BorderSizePixel = 0
  bar.Parent = holder

  local c1 = Instance.new 'UICorner'
  c1.CornerRadius = UDim.new(0, 6)
  c1.Parent = holder
  local c2 = Instance.new 'UICorner'
  c2.CornerRadius = UDim.new(0, 6)
  c2.Parent = bar

  holder.Visible = false
end

local function showProgress(on: boolean)
  ensureGui()
  local holder = gui and gui:FindFirstChild 'Holder' :: Frame
  if holder then
    holder.Visible = on
  end
end

local function setProgress01(x: number)
  ensureGui()
  if not bar then
    return
  end
  bar.Size = UDim2.new(math.clamp(x, 0, 1), 0, 1, 0)
end

-- ===== Helpers =====
local function currentWeaponId(): string
  local char = plr.Character
  local tool = char and char:FindFirstChildOfClass 'Tool'
  return (tool and tool.Name) or 'DebugSword'
end

local function isDagger(id: string): boolean
  local s = string.lower(id)
  return s:find('dagger', 1, true) ~= nil or id == 'Dagger'
end

local function getHumanoid(): Humanoid?
  local char = plr.Character
  return char and char:FindFirstChildOfClass 'Humanoid' or nil
end

local function getAnimator(): Animator?
  local hum = getHumanoid()
  if not hum then
    return nil
  end
  local anim = hum:FindFirstChildOfClass 'Animator' :: Animator?
  if not anim then
    anim = Instance.new 'Animator'
    anim.Parent = hum
  end
  return anim
end

local function findAnimation(nameList: { string }): Animation?
  -- Tool.Animations/*
  local char = plr.Character
  local tool = char and char:FindFirstChildOfClass 'Tool'
  local toolAnims = tool and tool:FindFirstChild 'Animations'
  if toolAnims then
    for _, n in ipairs(nameList) do
      local a = toolAnims:FindFirstChild(n)
      if a and a:IsA 'Animation' and a.AnimationId ~= '' then
        return a
      end
    end
  end
  -- RS/Animations/Dagger/*
  local anims = RS:FindFirstChild 'Animations'
  if anims then
    local dag = anims:FindFirstChild 'Dagger'
    if dag then
      for _, n in ipairs(nameList) do
        local a = dag:FindFirstChild(n)
        if a and a:IsA 'Animation' and a.AnimationId ~= '' then
          return a
        end
      end
    end
    -- RS/Animations/*
    for _, n in ipairs(nameList) do
      local a = anims:FindFirstChild(n)
      if a and a:IsA 'Animation' and a.AnimationId ~= '' then
        return a
      end
    end
  end
  return nil
end

local function stopAnimTracks(fade: number?)
  local f = (fade and math.max(0, fade)) or 0.15
  if currentHoldTrack then
    pcall(function()
      currentHoldTrack:Stop(f)
      currentHoldTrack:Destroy()
    end)
    currentHoldTrack = nil
  end
  if currentRaiseTrack then
    pcall(function()
      currentRaiseTrack:Stop(f)
      currentRaiseTrack:Destroy()
    end)
    currentRaiseTrack = nil
  end
end

-- ===== RightGrip access (Motor6D or Weld) =====
type GripInfo = { joint: Instance?, kind: 'motor' | 'weld' | 'none', base: CFrame }
local _cachedBase: CFrame? = nil

local function findRightGrip(): GripInfo
  local char = plr.Character
  if not char then
    return { joint = nil, kind = 'none', base = CFrame.new() }
  end

  local hand = char:FindFirstChild 'RightHand' or char:FindFirstChild 'Right Arm'
  if not hand then
    return { joint = nil, kind = 'none', base = CFrame.new() }
  end

  local rg = hand:FindFirstChild 'RightGrip'
  if not rg then
    for _, inst in ipairs((char :: Instance):GetDescendants()) do
      if inst.Name == 'RightGrip' and (inst:IsA 'Motor6D' or inst:IsA 'Weld') then
        rg = inst
        break
      end
    end
  end
  if not rg then
    return { joint = nil, kind = 'none', base = CFrame.new() }
  end

  if rg:IsA 'Motor6D' then
    if not _cachedBase then
      _cachedBase = CFrame.new()
    end
    return { joint = rg, kind = 'motor', base = _cachedBase }
  elseif rg:IsA 'Weld' then
    if not _cachedBase then
      _cachedBase = (rg :: Weld).C0
    end
    return { joint = rg, kind = 'weld', base = _cachedBase }
  end
  return { joint = nil, kind = 'none', base = CFrame.new() }
end

local function applyGripOffset(offset: CFrame)
  local info = findRightGrip()
  if info.kind == 'motor' then
    (info.joint :: Motor6D).Transform = offset
  elseif info.kind == 'weld' then
    (info.joint :: Weld).C0 = info.base * offset
  end
end

local function resetGripOffset()
  local info = findRightGrip()
  if info.kind == 'motor' then
    (info.joint :: Motor6D).Transform = CFrame.new()
  elseif info.kind == 'weld' then
    (info.joint :: Weld).C0 = info.base
  end
end

-- ===== Procedural RightGrip pose =====
local RAISE_CF = CFrame.new(0, -0.45, -0.55)
  * CFrame.Angles(math.rad(-55), math.rad(15), math.rad(5))

local procConn: RBXScriptConnection? = nil
local procTween: Tween? = nil
local usingProcedural = false

local function startProceduralRaise()
  usingProcedural = true
  if procTween then
    procTween:Cancel()
    procTween = nil
  end

  local cfv = Instance.new 'CFrameValue'
  cfv.Value = CFrame.new()
  cfv:GetPropertyChangedSignal('Value'):Connect(function()
    applyGripOffset(cfv.Value)
  end)
  procTween = TweenService:Create(
    cfv,
    TweenInfo.new(0.12, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
    { Value = RAISE_CF }
  )
  procTween:Play()

  if procConn then
    procConn:Disconnect()
    procConn = nil
  end
  local t0 = os.clock()
  procConn = RunService.RenderStepped:Connect(function()
    local hum = getHumanoid()
    if not hum then
      return
    end
    local speed = hum.MoveDirection.Magnitude * hum.WalkSpeed
    local freq = 8 + math.clamp(speed * 0.15, 0, 6)
    local amp = 0.05 + math.clamp(speed * 0.002, 0, 0.10)

    local t = os.clock() - t0
    local bobY = math.sin(t * freq) * amp
    local bobX = math.sin(t * freq * 0.5) * (amp * 0.35)
    local rot = CFrame.Angles(math.rad(bobY * 20), math.rad(bobX * 15), 0)

    applyGripOffset(RAISE_CF * CFrame.new(0, bobY, 0) * rot)
  end)
end

local function stopProceduralRaise(fade: number?)
  if procConn then
    procConn:Disconnect()
    procConn = nil
  end
  if procTween then
    procTween:Cancel()
    procTween = nil
  end
  usingProcedural = false

  local dur = (fade and math.max(0, fade)) or 0.08
  local cfv = Instance.new 'CFrameValue'
  cfv.Value = RAISE_CF
  cfv:GetPropertyChangedSignal('Value'):Connect(function()
    applyGripOffset(cfv.Value)
  end)
  local tw = TweenService:Create(
    cfv,
    TweenInfo.new(dur, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
    { Value = CFrame.new() }
  )
  tw:Play()
  task.delay(dur + 0.02, function()
    resetGripOffset()
  end)
end

-- ===== Charge animation (prefers assets, else procedural) =====
local function playChargeStart()
  local raiseAnim = findAnimation(ANIM_NAMES.raise)
  local holdAnim = findAnimation(ANIM_NAMES.hold)
  if raiseAnim then
    local animator = getAnimator()
    if not animator then
      return
    end
    currentRaiseTrack = animator:LoadAnimation(raiseAnim)
    currentRaiseTrack.Priority = Enum.AnimationPriority.Action
    currentRaiseTrack.Looped = false
    if holdAnim then
      currentHoldTrack = animator:LoadAnimation(holdAnim)
      currentHoldTrack.Priority = Enum.AnimationPriority.Action
      currentHoldTrack.Looped = true
      currentRaiseTrack.Stopped:Connect(function()
        if charging and currentHoldTrack then
          pcall(function()
            currentHoldTrack:Play(0.08, 1.0, 1.0)
          end)
        end
      end)
    end
    pcall(function()
      currentRaiseTrack:Play(0.06, 1.0, 1.0)
    end)
  else
    startProceduralRaise()
  end
end

local function stopChargePose()
  if currentHoldTrack then
    pcall(function()
      currentHoldTrack:Stop(0.10)
      currentHoldTrack:Destroy()
    end)
    currentHoldTrack = nil
  end
  if currentRaiseTrack then
    pcall(function()
      currentRaiseTrack:Stop(0.10)
      currentRaiseTrack:Destroy()
    end)
    currentRaiseTrack = nil
  end
  if usingProcedural then
    stopProceduralRaise(0.10)
  end
end

-- ===== Fire to server =====
local function sendSwing(payload: { [string]: any })
  local now = time()
  if (now - lastFired) < CLIENT_COOLDOWN then
    return
  end
  lastFired = now
  SwingRE:FireServer(payload)
end

-- ===== Input =====
UIS.InputBegan:Connect(function(input, gp)
  if gp then
    return
  end
  if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
    return
  end

  local wid = currentWeaponId()
  if isDagger(wid) then
    charging = true
    chargeStart = time()
    showProgress(true)
    setProgress01(0)
    playChargeStart()

    -- NEW: notify server charge started
    fireCharge('start', wid)

    if chargeConn then
      chargeConn:Disconnect()
      chargeConn = nil
    end
    chargeConn = RunService.RenderStepped:Connect(function()
      local t = time() - chargeStart
      setProgress01(t / CHARGE_REQ)
    end)
  else
    sendSwing { weaponId = wid, mode = 'light', target = mouse.Target }
  end
end)

UIS.InputEnded:Connect(function(input, gp)
  if gp then
    return
  end
  if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
    return
  end
  if not charging then
    return
  end

  charging = false
  if chargeConn then
    chargeConn:Disconnect()
    chargeConn = nil
  end
  showProgress(false)
  stopChargePose()

  local wid = currentWeaponId()
  local held = time() - chargeStart
  local charged = (held >= CHARGE_REQ)

  -- NEW: notify server charge ended
  fireCharge('end', wid)

  sendSwing {
    weaponId = wid,
    mode = charged and 'charged' or 'light',
    held = held,
    target = mouse.Target,
  }
end)

-- ===== Cleanup on respawn / cancellation =====
local function cancelIfCharging()
  if charging then
    charging = false
    if chargeConn then
      chargeConn:Disconnect()
      chargeConn = nil
    end
    showProgress(false)
    stopChargePose()

    -- NEW: notify server charge ended on cancel
    local wid = currentWeaponId()
    fireCharge('end', wid)
  end
end

plr.CharacterRemoving:Connect(function()
  cancelIfCharging()
  _cachedBase = nil -- recalc base on next equip
end)

plr.CharacterAdded:Connect(function()
  task.delay(0.1, function()
    cancelIfCharging()
    resetGripOffset()
    _cachedBase = nil
  end)
end)

--!strict
-- Wires exit prompts, calls Inventory.extract/onExtract; adopts existing prompts to avoid duplicates.
local Players = game:GetService 'Players'
local RS = game:GetService 'ReplicatedStorage'
local SSS = game:GetService 'ServerScriptService'
local PPS = game:GetService 'ProximityPromptService'
local Inventory = require(SSS:WaitForChild('Inventory'):WaitForChild 'Public')

-- ---------- Remotes (safe create) ----------
local function ensureFolder(parent: Instance, name: string): Folder
  local f = parent:FindFirstChild(name)
  if not f then
    f = Instance.new 'Folder'
    f.Name = name
    f.Parent = parent
  end
  return f :: Folder
end

local Remotes = ensureFolder(RS, 'Remotes')
local REFolder = ensureFolder(Remotes, 'RemoteEvent')
local SessionRE: RemoteEvent = REFolder:FindFirstChild 'Session' :: RemoteEvent
if not SessionRE then
  SessionRE = Instance.new 'RemoteEvent'
  SessionRE.Name = 'Session'
  SessionRE.Parent = REFolder
end

-- ---------- Diagnostics (once) ----------
if not _G.__extractDiag then
  _G.__extractDiag = true
  PPS.PromptShown:Connect(function(prompt, player)
    print(
      ('[Extract][Diag] PromptShown %s for %s (Enabled=%s, Hold=%.2f, MaxDist=%.1f)'):format(
        prompt:GetFullName(),
        player.Name,
        tostring(prompt.Enabled),
        prompt.HoldDuration,
        prompt.MaxActivationDistance
      )
    )
  end)
  PPS.PromptButtonHoldBegan:Connect(function(prompt, player)
    print(('[Extract][Diag] HoldBegan %s by %s'):format(prompt:GetFullName(), player.Name))
  end)
  PPS.PromptButtonHoldEnded:Connect(function(prompt, player)
    print(('[Extract][Diag] HoldEnded %s by %s'):format(prompt:GetFullName(), player.Name))
  end)
  PPS.PromptTriggered:Connect(function(prompt, player)
    print(('[Extract][Diag] PromptTriggered %s by %s'):format(prompt:GetFullName(), player.Name))
  end)
end

-- ---------- Helpers ----------
local function isOpenAttrTrue(exitModel: Instance): boolean
  local v = exitModel:GetAttribute 'Open'
  return (v == nil) or (v == true) -- default OPEN if missing
end

local lastExtractAt: { [number]: number } = {}
local function doExtract(p: Player, exitModel: Instance)
  local t = os.clock()
  local prev = lastExtractAt[p.UserId]
  if prev and (t - prev) < 0.75 then
    return
  end
  lastExtractAt[p.UserId] = t

  print(('[Extract] Triggered by %s on %s'):format(p.Name, exitModel.Name))
  if typeof(Inventory.extract) == 'function' then
    Inventory.extract(p)
  else
    Inventory.onExtract(p)
  end

  SessionRE:FireAllClients('extracted', {
    userId = p.UserId,
    name = p.DisplayName,
    exit = exitModel.Name,
  })

  if p.Character then
    p:LoadCharacter()
  end
end

local function adoptOrCreatePrompt(host: BasePart, exitModel: Instance): ProximityPrompt
  -- Prefer an existing "ExtractPrompt"; else pick a prompt that already looks like an extract prompt; else create one.
  local prompts = {}
  for _, ch in ipairs(host:GetChildren()) do
    if ch:IsA 'ProximityPrompt' then
      table.insert(prompts, ch)
    end
  end

  local chosen: ProximityPrompt? = host:FindFirstChild 'ExtractPrompt' :: ProximityPrompt
  if not chosen then
    for _, pr in ipairs(prompts) do
      if (pr.ActionText == 'Extract') or (pr.KeyboardKeyCode == Enum.KeyCode.E) then
        chosen = pr
        break
      end
    end
  end
  if not chosen then
    chosen = Instance.new 'ProximityPrompt'
    chosen.Parent = host
  end

  -- Configure & rename the chosen one
  chosen.Name = 'ExtractPrompt'
  chosen.ActionText = 'Extract'
  chosen.ObjectText = exitModel.Name
  chosen.KeyboardKeyCode = Enum.KeyCode.E
  chosen.HoldDuration = 0.5
  chosen.RequiresLineOfSight = false
  chosen.MaxActivationDistance = 18
  chosen.Style = Enum.ProximityPromptStyle.Default

  -- Disable any other prompts on the same part to avoid confusion
  for _, pr in ipairs(prompts) do
    if pr ~= chosen then
      pr.Enabled = false
      pr:SetAttribute('DisabledByExtractionService', true)
    end
  end

  return chosen
end

local function wire(exitModel: Model)
  local root: BasePart? = exitModel:FindFirstChild 'HumanoidRootPart'
    or exitModel:FindFirstChildWhichIsA('BasePart', true)
  if not root then
    warn('[Extract] Wire failed (no BasePart):', exitModel:GetFullName())
    return
  end

  local prompt = adoptOrCreatePrompt(root, exitModel)
  prompt.Enabled = isOpenAttrTrue(exitModel)
  print(
    ('[Extract] Hooked %s on %s (Enabled=%s)'):format(
      prompt:GetFullName(),
      root:GetFullName(),
      tostring(prompt.Enabled)
    )
  )

  if not prompt:GetAttribute 'Hooked' then
    prompt:SetAttribute('Hooked', true)
    prompt.Triggered:Connect(function(p: Player)
      if isOpenAttrTrue(exitModel) then
        doExtract(p, exitModel)
      end
    end)
  end

  -- Click fallback (handy in Studio or if E is intercepted)
  local click = root:FindFirstChildOfClass 'ClickDetector' or Instance.new 'ClickDetector'
  click.MaxActivationDistance = 24
  click.Parent = root
  if not click:GetAttribute 'Hooked' then
    click:SetAttribute('Hooked', true)
    click.MouseClick:Connect(function(p: Player)
      if isOpenAttrTrue(exitModel) then
        doExtract(p, exitModel)
      end
    end)
  end

  -- Attribute sync (enable/disable prompt live)
  exitModel:GetAttributeChangedSignal('Open'):Connect(function()
    local en = isOpenAttrTrue(exitModel)
    prompt.Enabled = en
    print(('[Extract] %s Open→%s'):format(exitModel.Name, tostring(en)))
  end)
end

local function hookAll()
  local folder = workspace:FindFirstChild 'Exits'
  if not folder then
    warn '[Extract] No workspace.Exits folder found'
    return
  end
  local n = 0
  for _, m in ipairs(folder:GetChildren()) do
    if m:IsA 'Model' then
      wire(m)
      n += 1
    end
  end
  print('[Extract] Hooked exits:', n)
end

hookAll()

workspace.DescendantAdded:Connect(function(d)
  local exits = workspace:FindFirstChild 'Exits'
  if exits and d:IsDescendantOf(exits) and d:IsA 'Model' then
    wire(d)
  end
end)

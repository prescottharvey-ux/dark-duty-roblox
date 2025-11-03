local RS = game:GetService 'ReplicatedStorage'
local SSS = game:GetService 'ServerScriptService'
if not RS:FindFirstChild 'TestEZTests' then
  return
end
if not (SSS:FindFirstChild 'Server' and SSS.Server:FindFirstChild 'TestEZ') then
  return
end

-- existing test bootstrap below...

require(script.Parent.TestEZ).TestBootstrap:run {
  game.ServerScriptService.Lib,
}

-- Server/Setup/EnsureRemotes.server.lua
local RS = game:GetService("ReplicatedStorage")

local function ensureFolder(parent: Instance, name: string)
local f = parent:FindFirstChild(name)
if not f then
f = Instance.new("Folder")
f.Name = name
f.Parent = parent
end
return f
end

local function ensureRemoteEvent(parent: Instance, name: string)
local r = parent:FindFirstChild(name)
if not r then
r = Instance.new("RemoteEvent")
r.Name = name
r.Parent = parent
end
return r
end

local Remotes = ensureFolder(RS, "Remotes")
local RE = ensureFolder(Remotes, "RemoteEvent")

ensureRemoteEvent(RE, "Combat")
ensureRemoteEvent(RE, "StartBlock")
ensureRemoteEvent(RE, "DaggerAttack")

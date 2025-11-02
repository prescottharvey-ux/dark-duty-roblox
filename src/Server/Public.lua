-- ServerScriptService/Combat/Public
--!strict
local RS = game:GetService 'ReplicatedStorage'
local Mods = RS:WaitForChild 'Modules'
local Combat = require(Mods:WaitForChild 'Combat') -- your existing Combat API
return Combat

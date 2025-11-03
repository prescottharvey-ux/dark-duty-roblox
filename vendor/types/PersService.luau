--!strict
local Pers = {}
local STORE: { [number]: any } = {} -- in-memory for dev; replace with DataStore later

function Pers.LoadProfile(userId: number)
  return STORE[userId] or { gold = 0, stash = {}, durability = {} }
end

function Pers.SaveProfile(userId: number, data: table)
  STORE[userId] = data
  return true
end

return Pers

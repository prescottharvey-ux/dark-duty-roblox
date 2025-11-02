--!strict
-- ReplicatedStorage/Modules/Combat/AnimIds.lua
-- Fixed hands: weapons/spellbooks => RIGHT, shields/items => LEFT

-- Normalize any id to "rbxassetid://<id>"
local function asset(id: number | string): string
  if typeof(id) == 'number' then
    return 'rbxassetid://' .. tostring(id)
  end
  -- Accept already-wrapped and common URL formats
  if string.sub(id, 1, 13) == 'rbxassetid://' then
    return id
  end
  -- Handle "https://www.roblox.com/asset/?id=123" or "http://..."
  local q = string.match(id, '[%?&]id=(%d+)')
  if q then
    return 'rbxassetid://' .. q
  end
  return 'rbxassetid://' .. id
end

local function optAsset(id: number | string | nil): string?
  return id and asset(id) or nil
end

-- Core table (numeric ids preserved for back-compat).
local A = {
  Dagger = {
    -- RIGHT-hand stab (numeric id)
    Stab = 134992442327635,
    -- StabAsset filled below
  },

  Shield = {
    -- LEFT-hand block loop
    BlockLoop = 126671196764044,
    -- BlockLoopAsset filled below

    -- Optional raise/lower one-shots
    RaiseIn = 14332345678,
    -- RaiseInAsset filled below

    LowerOut = 14342345678,
    -- LowerOutAsset filled below

    -- Optional: short "impact" when a hit is blocked.
    -- If you add an id here, BlockHitAsset will auto-populate.
    -- BlockHit = 0000000000,
    -- BlockHitAsset filled below (if present)
  },
}

-- Precompute convenient asset-string variants (safe if an optional id is missing)
A.Dagger.StabAsset = asset(A.Dagger.Stab)

A.Shield.BlockLoopAsset = asset(A.Shield.BlockLoop)
A.Shield.RaiseInAsset = optAsset(A.Shield.RaiseIn)
A.Shield.LowerOutAsset = optAsset(A.Shield.LowerOut)
A.Shield.BlockHitAsset = optAsset((A.Shield :: any).BlockHit)

-- ---- Optional compatibility aliases (harmless if unused) ----
-- Generic “melee swing” some controllers look for:
A.Melee = {
  Right = { Swing = A.Dagger.Stab, SwingAsset = A.Dagger.StabAsset },
  Left = {},
}

-- Generic “block loop” (left hand):
A.Block = {
  LeftLoop = A.Shield.BlockLoop,
  LeftLoopAsset = A.Shield.BlockLoopAsset,
}

-- Short single-value aliases:
A.swing_dagger = A.Dagger.Stab
A.block_shield_loop = A.Shield.BlockLoop

-- Expose helper for callers that want to wrap other ids on the fly.
A.asset = asset

return A

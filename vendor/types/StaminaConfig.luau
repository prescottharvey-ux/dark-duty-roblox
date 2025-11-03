--!strict
-- ReplicatedStorage/Config/StaminaConfig.lua
-- Central tuning for stamina, speeds, noise, and weapon curves.
-- Includes a small helper: StaminaConfig.GetSwingCost(itemId, weight?)

local StaminaConfig = {
  -- ===== Core stamina =====
  Max = 100,
  TickRate = 10, -- Hz
  RegenDelay = 0.6, -- seconds after last spend before regen begins

  Costs = {
    SprintPerSec = 15,
    BlockPerSec = 3,
    SwingFlat = 12, -- fallback if weapon weight/override isn't found

    -- Optional hard per-weapon stamina overrides (by item id / Tool.Name)
    Weapon = {
      DebugSword = 12,
      Greatsword = 18,
      Dagger = 8,
    },

    -- Weight → swing stamina curve (used when there's no hard override)
    -- You can tweak these numbers to change how weight affects stamina cost.
    WeightToSwing = {
      Base = 6, -- baseline cost for 0 weight
      PerUnit = 2.0, -- +cost per weight unit
      Min = 5, -- clamp low
      Max = 30, -- clamp high
    },
  },

  -- Regen rates: walk is slowest, sneak is fastest
  Regen = {
    Walk = 1, -- very slow while walking
    Idle = 3, -- slow while standing still
    Sneak = 8, -- faster while sneaking
  },

  Thresholds = {
    MinToSprint = 10,
    MinToSwing = 8,
    MinToBlock = 5,
  },

  -- Intent names (keep in sync with client hotkeys/controller)
  Intents = {
    Sprinting = 'Sprinting',
    Sneaking = 'Sneaking',
    Blocking = 'Blocking',
  },

  -- Movement speeds
  UseServerSprintSpeed = true,
  Speeds = {
    Walk = 16,
    Sneak = 11, -- slower while sneaking
    Sprint = 22,
  },

  -- Noise multipliers (exported as a Player attribute "NoiseScalar")
  Noise = {
    Idle = 0.20,
    Walk = 1.00,
    Sneak = 0.40, -- quieter
    Sprint = 1.70, -- louder
  },

  -- ===== Optional weapon curves for feel (used by WeaponStats.lua) =====
  Weapons = {
    -- Weight → swing time (seconds)
    WeightToSwingTime = { Base = 0.34, PerUnit = 0.030, Min = 0.24, Max = 0.90 },

    -- Weight → damage
    WeightToDamage = { Base = 18, PerUnit = 3.0, Min = 12, Max = 50 },

    -- Optional hard per-weapon overrides (if you want exact values)
    -- Overrides = {
    --   Dagger     = { damage = 20, swingTime = 0.28, stamina = 6 },
    --   Greatsword = { damage = 38, swingTime = 0.70, stamina = 20 },
    -- }
    Overrides = {},
  },
}

-- ===== Helper function =====
-- Compute swing stamina cost for a given weapon id.
-- Order of precedence:
--   1) Costs.Weapon[itemId] (hard override)
--   2) Costs.WeightToSwing curve using provided 'weight' (if given)
--   3) SwingFlat fallback
--
-- Note: Our server-side StaminaService.SwingCost/WeaponStats.get() already
-- do this in a more robust way using ItemDB. This helper is convenient when
-- you're only holding the id (and maybe weight) on either client or server.
local function clamp(x: number, a: number, b: number): number
  if x < a then
    return a
  end
  if x > b then
    return b
  end
  return x
end

function StaminaConfig.GetSwingCost(itemId: string, weight: number?): number
  -- 1) Hard override wins
  local ov = (StaminaConfig.Costs.Weapon or {})[itemId]
  if typeof(ov) == 'number' then
    local w = StaminaConfig.Costs.WeightToSwing or { Min = 0, Max = 1e9 }
    return clamp(ov, w.Min or 0, w.Max or 1e9)
  end

  -- 2) Curve by weight (if provided)
  if typeof(weight) == 'number' then
    local w = StaminaConfig.Costs.WeightToSwing
    local base = (w and w.Base) or 6
    local per = (w and w.PerUnit) or 2.0
    local minC = (w and w.Min) or 5
    local maxC = (w and w.Max) or 30
    return clamp(base + per * weight, minC, maxC)
  end

  -- 3) Fallback flat cost
  return StaminaConfig.Costs.SwingFlat or 12
end

return StaminaConfig

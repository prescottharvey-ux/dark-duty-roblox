--!strict
-- Private state for Inventory (example)
local store: { [number]: { weight: number, items: { [string]: number } } } = {}
return { store = store }

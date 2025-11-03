--!strict
-- Proxy shim for Egg code expecting `InventoryService` as a ModuleScript.
-- Route it to your real Inventory API (Public).
return require(game.ServerScriptService:WaitForChild('Inventory'):WaitForChild 'Public')

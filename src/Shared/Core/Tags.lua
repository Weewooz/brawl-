--!strict
-- Shared CollectionService tags used as cross-system contracts.

local Tags = table.freeze({
	Combatant = "Combatant",
	MapSpawn = "MapSpawn",
	Fade = "WaterFade", -- Client tweens LocalTransparencyModifier before part destroy
})

return Tags

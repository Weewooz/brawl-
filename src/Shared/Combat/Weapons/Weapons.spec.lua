--!strict
return function(Weapons: typeof(require(script.Parent)))
	assert(Weapons.Get("Katana") and Weapons.Get("Yumi"), "Both starter weapons must be defined")
	assert(Weapons.Get("Unknown") == nil, "Unknown weapons must not resolve")
	for _, id in { "Katana", "Yumi" } do
		local definition = Weapons.Get(id)
		assert(definition, "Starter weapon definition is missing")
		for _, slot in Weapons.Slots do
			local skill = definition.Skills[slot]
			assert(
				skill and skill.Cooldown > 0 and skill.Range > 0,
				"Every equipped weapon must supply four real skills"
			)
		end
	end
	for _, status in { "Queued", "Playing", "Results", "Unknown" } do
		assert(not Weapons.CanEquip(status, false), "Queued and active builds must remain locked")
	end
	assert(
		Weapons.CanEquip("Lobby", false) and Weapons.CanEquip("Practice", false),
		"Lobby and training must allow selection"
	)
	assert(not Weapons.CanEquip("Lobby", true), "Dungeon builds must remain locked")
	return "Weapon definitions and activity selection rules passed"
end

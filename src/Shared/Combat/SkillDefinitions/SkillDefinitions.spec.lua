--!strict
return function(SkillDefinitions: typeof(require(script.Parent)))
	assert(SkillDefinitions.Get("Unknown") == nil, "Unknown skill IDs must not resolve")
	assert(SkillDefinitions.ForWeapon("Unknown") == nil, "Unknown weapons must not resolve")
	assert(SkillDefinitions.Resolve("Katana", "Unknown") == nil, "Unknown slots must not resolve")
	assert(SkillDefinitions.Slot(0) == nil and SkillDefinitions.Slot(5) == nil, "Only four network slots are valid")
	assert(SkillDefinitions.Slot(1.5) == nil, "Fractional network slots must not resolve")
	assert(
		SkillDefinitions.Slot(0 / 0) == nil and SkillDefinitions.Slot(math.huge) == nil,
		"Non-finite network slots must not resolve"
	)
	assert(SkillDefinitions.Index("Unknown") == nil, "Unknown slot names must not resolve")
	assert(table.isfrozen(SkillDefinitions.Slots), "Network slot order must remain immutable")

	local seen: { [string]: boolean } = {}
	for _, weapon in { "Katana", "Yumi" } do
		local skills = SkillDefinitions.ForWeapon(weapon)
		assert(skills and table.isfrozen(skills), "Weapon loadouts must exist and remain immutable")
		for index, slot in SkillDefinitions.Slots do
			assert(
				SkillDefinitions.Slot(index) == slot and SkillDefinitions.Index(slot) == index,
				"Slots must round trip"
			)
			local skill = SkillDefinitions.Resolve(weapon, slot)
			assert(skill and skill == skills[slot], "Weapon and slot lookup must agree with the loadout")
			assert(skill == SkillDefinitions.Get(skill.Id), "Skill IDs must resolve the same immutable definition")
			assert(not seen[skill.Id], "Each skill ID must identify one equipped ability")
			seen[skill.Id] = true
			assert(skill.Weapon == weapon and skill.Slot == slot, "Skill ownership must match its loadout")
			assert(skill.Cooldown > 0 and skill.Stamina >= 0 and skill.Range > 0, "Skill costs and reach must be valid")
			assert(skill.Duration > skill.Windup and skill.Windup >= 0, "Windup must fit within the skill lifetime")
			assert(table.isfrozen(skill) and table.isfrozen(skill.Presentation), "Skill presentation must be immutable")
			local previous = -math.huge
			for _, cue in skill.Presentation.Cues do
				assert(
					cue.At >= previous and cue.At >= 0 and cue.At < skill.Duration,
					"Cues must be ordered within a cast"
				)
				assert(cue.Sound ~= "" and table.isfrozen(cue), "Cues must name authored audio and remain immutable")
				previous = cue.At
			end
			local projectile = skill.Projectile
			if projectile then
				assert(weapon == "Yumi" and projectile.Damage > 0, "Only ranged skills may launch these projectiles")
				assert(
					projectile.MaxTargets >= 1 and #projectile.Angles >= 1,
					"Every shot must have targets and launch angles"
				)
				assert(
					table.isfrozen(projectile) and table.isfrozen(projectile.Angles),
					"Projectile settings must be immutable"
				)
			end
		end
	end

	local spin = SkillDefinitions.Resolve("Katana", "Spin")
	local volley = SkillDefinitions.Resolve("Yumi", "Spin")
	assert(
		spin and volley and spin.Id == "WindSpin" and volley.Id == "Volley",
		"A slot must resolve by equipped weapon"
	)
	assert(
		spin.Aim == "Instant" and volley.Aim == "Instant",
		"Spin and Volley must preserve successful click activation"
	)
	assert(#spin.Presentation.Cues == 2, "Wind Spin must retain both impact cues")
	local charge = SkillDefinitions.Resolve("Katana", "Charge")
	local quick = SkillDefinitions.Resolve("Yumi", "Charge")
	assert(
		charge and quick and charge.Aim == "Target" and quick.Aim == "Direction",
		"Charge must preserve weapon-specific aiming"
	)
	assert(charge.Presentation.Cues[1].At == 0, "Charge audio must start immediately")
	local piercing = SkillDefinitions.Get("PiercingShot")
	local pinning = SkillDefinitions.Get("PinningShot")
	assert(
		piercing and piercing.Projectile and piercing.Projectile.MaxTargets == 2,
		"Piercing Shot must retain two targets"
	)
	assert(volley.Projectile and #volley.Projectile.Angles == 3, "Volley must retain three arrows")
	assert(pinning and pinning.Projectile and pinning.Projectile.Slow, "Pinning Shot must retain its slow")
	assert(
		pinning.Projectile.Slow.Ratio == 0.65 and pinning.Projectile.Slow.Duration == 2,
		"Pinning Shot slow must remain unchanged"
	)
	return "Skill definitions, slot routing, authored cue timelines, and projectile contracts passed"
end

--!strict
local Types = require(script.Types)

export type Id = Types.Id
export type Slot = Types.Slot
export type Weapon = Types.Weapon
export type Cue = Types.Cue
export type Presentation = Types.Presentation
export type Projectile = Types.Projectile
export type Slow = Types.Slow
export type Definition = Types.Definition

local SkillDefinitions = {}
SkillDefinitions.Slots = table.freeze({ "RisingCrash", "Spin", "Charge", "GroundShock" } :: { Slot })

local Definitions: { [string]: Definition } = {
	RisingCrash = require(script.RisingCrash),
	WindSpin = require(script.WindSpin),
	Charge = require(script.Charge),
	GroundShock = require(script.GroundShock),
	PiercingShot = require(script.PiercingShot),
	Volley = require(script.Volley),
	QuickShot = require(script.QuickShot),
	PinningShot = require(script.PinningShot),
}
local ByWeapon: { [string]: { [string]: Definition } } = {}
local Indices: { [string]: number } = {}

for index, slot in SkillDefinitions.Slots do
	Indices[slot] = index
end
table.freeze(Indices)

for id, definition in Definitions do
	assert(definition.Id == id, "[Combat] Skill definition ID must match its module: " .. id)
	assert(Indices[definition.Slot], "[Combat] Invalid skill slot: " .. id)
	local skills = ByWeapon[definition.Weapon]
	if not skills then
		skills = {}
		ByWeapon[definition.Weapon] = skills
	end
	assert(
		skills[definition.Slot] == nil,
		"[Combat] Duplicate skill slot: " .. definition.Weapon .. "." .. definition.Slot
	)
	skills[definition.Slot] = definition
	for _, cue in definition.Presentation.Cues do
		table.freeze(cue)
	end
	table.freeze(definition.Presentation.Cues)
	table.freeze(definition.Presentation.Effects)
	table.freeze(definition.Presentation)
	local projectile = definition.Projectile
	if projectile then
		table.freeze(projectile.Angles)
		if projectile.Slow then
			table.freeze(projectile.Slow)
		end
		table.freeze(projectile)
	end
	table.freeze(definition)
end
for _, skills in ByWeapon do
	table.freeze(skills)
end
table.freeze(ByWeapon)
table.freeze(Definitions)

function SkillDefinitions.Get(id: string): Definition?
	return Definitions[id]
end

function SkillDefinitions.Resolve(weapon: string, slot: string): Definition?
	local skills = ByWeapon[weapon]
	return if skills then skills[slot] else nil
end

function SkillDefinitions.Slot(index: number): Slot?
	if index ~= index or index % 1 ~= 0 or index < 1 or index > #SkillDefinitions.Slots then
		return nil
	end
	return SkillDefinitions.Slots[index]
end

function SkillDefinitions.Index(slot: string): number?
	return Indices[slot]
end

function SkillDefinitions.ForWeapon(weapon: string): { [string]: Definition }?
	return ByWeapon[weapon]
end

return table.freeze(SkillDefinitions)

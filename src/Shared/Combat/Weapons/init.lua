--!strict
local Config = require(script.Parent.Config)
local SkillDefinitions = require(script.Parent.SkillDefinitions)

export type Id = "Katana" | "Yumi"
export type Skill = SkillDefinitions.Definition
export type Definition = {
	Name: string,
	Range: number,
	IsRanged: boolean,
	Attack: { Cooldown: number, Stamina: number },
	Skills: { [string]: Skill },
	ChargeTime: number?,
	MinDamage: number?,
	MaxDamage: number?,
	Speed: number?,
}

local Weapons = {}
Weapons.Slots = SkillDefinitions.Slots

local DEFINITIONS: { [string]: Definition } = {
	Katana = {
		Name = "Katana",
		Range = Config.Charge.Range,
		IsRanged = false,
		Attack = { Cooldown = Config.Attack.Cooldown, Stamina = 0 },
		Skills = SkillDefinitions.ForWeapon("Katana") :: { [string]: Skill },
	},
	Yumi = {
		Name = "Yumi",
		Range = 60,
		IsRanged = true,
		ChargeTime = 1,
		MinDamage = 10,
		MaxDamage = 28,
		Speed = 100,
		Attack = { Cooldown = 0.8, Stamina = 8 },
		Skills = SkillDefinitions.ForWeapon("Yumi") :: { [string]: Skill },
	},
}

for _, definition in DEFINITIONS do
	table.freeze(definition.Attack)
	table.freeze(definition)
end
table.freeze(DEFINITIONS)

function Weapons.Get(id: string): Definition?
	return DEFINITIONS[id]
end

function Weapons.Weapon(character: Model?): Id
	return if character and character:GetAttribute("Weapon") == "Yumi" then "Yumi" else "Katana"
end

function Weapons.CanEquip(status: string?, inDungeon: boolean): boolean
	return not inDungeon and (status == nil or status == "Lobby" or status == "Practice")
end

return table.freeze(Weapons)

--!strict
local Config = require(script.Parent.Config)

export type Id = "Katana" | "Yumi"
export type Skill = {
	Name: string,
	Cooldown: number,
	Stamina: number,
	Range: number,
}
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
Weapons.Slots = table.freeze({ "RisingCrash", "Spin", "Charge", "GroundShock" })

local DEFINITIONS: { [string]: Definition } = {
	Katana = {
		Name = "Katana",
		Range = Config.Charge.Range,
		IsRanged = false,
		Attack = { Cooldown = Config.Attack.Cooldown, Stamina = 0 },
		Skills = {
			RisingCrash = {
				Name = "Rising Crash",
				Cooldown = Config.RisingCrash.Cooldown,
				Stamina = Config.RisingCrash.Stamina,
				Range = Config.RisingCrash.Range,
			},
			Spin = {
				Name = "Wind Spin",
				Cooldown = Config.Spin.Cooldown,
				Stamina = Config.Spin.Stamina,
				Range = Config.Spin.Radius,
			},
			Charge = {
				Name = "Charge",
				Cooldown = Config.Charge.Cooldown,
				Stamina = Config.Charge.Stamina,
				Range = Config.Charge.Range,
			},
			GroundShock = {
				Name = "Ground Shock",
				Cooldown = Config.GroundShock.Cooldown,
				Stamina = Config.GroundShock.Stamina,
				Range = Config.GroundShock.Range,
			},
		},
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
		Skills = {
			RisingCrash = { Name = "Piercing Shot", Cooldown = 7, Stamina = 20, Range = 60 },
			Spin = { Name = "Volley", Cooldown = 8, Stamina = 25, Range = 45 },
			Charge = { Name = "Quick Shot", Cooldown = 4, Stamina = 12, Range = 45 },
			GroundShock = { Name = "Pinning Shot", Cooldown = 10, Stamina = 20, Range = 50 },
		},
	},
}

for _, definition in DEFINITIONS do
	table.freeze(definition.Attack)
	for _, skill in definition.Skills do
		table.freeze(skill)
	end
	table.freeze(definition.Skills)
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

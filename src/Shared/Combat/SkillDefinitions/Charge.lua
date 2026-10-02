--!strict
local Config = require(script.Parent.Parent.Config).Charge
local Types = require(script.Parent.Types)

local Charge: Types.Definition = {
	Id = "Charge",
	Name = "Charge",
	Weapon = "Katana",
	Slot = "Charge",
	Cooldown = Config.Cooldown,
	Stamina = Config.Stamina,
	Range = Config.Range,
	Duration = Config.Duration,
	Windup = 0,
	Aim = "Target",
	Presentation = {
		Animation = "Charge",
		Cues = { { At = 0, Sound = "Charge", Volume = 0.35, RemoteVolume = 0.24, Shake = 0.18, ShakeDuration = 0.14 } },
		Preview = "Charge",
		Height = 5,
		Effects = {},
	},
}

return Charge

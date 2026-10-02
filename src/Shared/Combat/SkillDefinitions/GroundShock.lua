--!strict
local Config = require(script.Parent.Parent.Config).GroundShock
local Types = require(script.Parent.Types)

local GroundShock: Types.Definition = {
	Id = "GroundShock",
	Name = "Ground Shock",
	Weapon = "Katana",
	Slot = "GroundShock",
	Cooldown = Config.Cooldown,
	Stamina = Config.Stamina,
	Range = Config.Range,
	Duration = Config.Duration,
	Windup = Config.Windup,
	Aim = "Direction",
	Presentation = {
		Animation = "GroundShock",
		Trail = true,
		Cues = {
			{
				At = Config.Windup,
				Sound = "GroundShock",
				Volume = 0.34,
				RemoteVolume = 0.28,
				Shake = 0.24,
				ShakeDuration = 0.16,
			},
		},
		Preview = "Cone",
		HalfAngle = Config.HalfAngle,
		Height = Config.Height,
		Effects = {},
	},
}

return GroundShock

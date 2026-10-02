--!strict
local Config = require(script.Parent.Parent.Config).RisingCrash
local Types = require(script.Parent.Types)

local RisingCrash: Types.Definition = {
	Id = "RisingCrash",
	Name = "Rising Crash",
	Weapon = "Katana",
	Slot = "RisingCrash",
	Cooldown = Config.Cooldown,
	Stamina = Config.Stamina,
	Range = Config.Range,
	Duration = Config.Duration,
	Windup = Config.Windup,
	Aim = "Direction",
	Presentation = {
		Animation = "RisingCrash",
		Trail = true,
		Cues = {
			{
				At = Config.Windup,
				Sound = "RisingCrash",
				Volume = 0.34,
				RemoteVolume = 0.24,
				Shake = 0.15,
				ShakeDuration = 0.16,
			},
		},
		Preview = "Cone",
		HalfAngle = Config.HalfAngle,
		Height = Config.Height,
		Effects = {},
	},
}

return RisingCrash

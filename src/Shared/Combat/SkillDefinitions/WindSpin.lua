--!strict
local Config = require(script.Parent.Parent.Config).Spin
local Types = require(script.Parent.Types)

local WindSpin: Types.Definition = {
	Id = "WindSpin",
	Name = "Wind Spin",
	Weapon = "Katana",
	Slot = "Spin",
	Cooldown = Config.Cooldown,
	Stamina = Config.Stamina,
	Range = Config.Radius,
	Duration = Config.Duration,
	Windup = Config.FirstHit,
	Aim = "Instant",
	Presentation = {
		Animation = "Spin",
		Looped = true,
		Trail = true,
		Cues = {
			{
				At = Config.FirstHit,
				Sound = "WindSpin",
				Volume = 0.32,
				RemoteVolume = 0.24,
				Shake = 0.13,
				ShakeDuration = 0.12,
			},
			{
				At = Config.FirstHit + Config.Interval,
				Sound = "WindSpin",
				Volume = 0.32,
				RemoteVolume = 0.24,
				Shake = 0.13,
				ShakeDuration = 0.12,
			},
		},
		Preview = "Ring",
		Height = Config.Height,
		Effects = {},
	},
}

return WindSpin

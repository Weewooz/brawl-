--!strict
local Types = require(script.Parent.Types)

local PinningShot: Types.Definition = {
	Id = "PinningShot",
	Name = "Pinning Shot",
	Weapon = "Yumi",
	Slot = "GroundShock",
	Cooldown = 10,
	Stamina = 20,
	Range = 50,
	Duration = 0.35,
	Windup = 0.15,
	Aim = "Direction",
	Presentation = { Cues = {}, Preview = "Projectile", Effects = {} },
	Projectile = {
		Damage = 12,
		MaxTargets = 1,
		Angles = { 0 },
		Slow = { Ratio = 0.65, Duration = 2, Key = "YumiPinning" },
	},
}

return PinningShot

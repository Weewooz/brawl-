--!strict
local Types = require(script.Parent.Types)

local PiercingShot: Types.Definition = {
	Id = "PiercingShot",
	Name = "Piercing Shot",
	Weapon = "Yumi",
	Slot = "RisingCrash",
	Cooldown = 7,
	Stamina = 20,
	Range = 60,
	Duration = 0.35,
	Windup = 0.15,
	Aim = "Direction",
	Presentation = { Cues = {}, Preview = "Projectile", Effects = {} },
	Projectile = { Damage = 24, MaxTargets = 2, Angles = { 0 } },
}

return PiercingShot

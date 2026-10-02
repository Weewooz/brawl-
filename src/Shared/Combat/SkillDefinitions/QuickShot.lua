--!strict
local Types = require(script.Parent.Types)

local QuickShot: Types.Definition = {
	Id = "QuickShot",
	Name = "Quick Shot",
	Weapon = "Yumi",
	Slot = "Charge",
	Cooldown = 4,
	Stamina = 12,
	Range = 45,
	Duration = 0.35,
	Windup = 0.15,
	Aim = "Direction",
	Presentation = { Cues = {}, Preview = "Projectile", Effects = {} },
	Projectile = { Damage = 10, MaxTargets = 1, Angles = { 0 } },
}

return QuickShot

--!strict
local Types = require(script.Parent.Types)

local Volley: Types.Definition = {
	Id = "Volley",
	Name = "Volley",
	Weapon = "Yumi",
	Slot = "Spin",
	Cooldown = 8,
	Stamina = 25,
	Range = 45,
	Duration = 0.35,
	Windup = 0.15,
	Aim = "Instant",
	Presentation = { Cues = {}, Preview = "Projectile", Effects = {} },
	Projectile = { Damage = 8, MaxTargets = 1, Angles = { -8, 0, 8 } },
}

return Volley

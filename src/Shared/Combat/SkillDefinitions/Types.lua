--!strict

export type Id =
	"RisingCrash"
	| "WindSpin"
	| "Charge"
	| "GroundShock"
	| "PiercingShot"
	| "Volley"
	| "QuickShot"
	| "PinningShot"
export type Slot = "RisingCrash" | "Spin" | "Charge" | "GroundShock"
export type Weapon = "Katana" | "Yumi"
export type Cue = {
	At: number,
	Sound: string,
	Volume: number?,
	RemoteVolume: number?,
	Shake: number?,
	ShakeDuration: number?,
}
export type Presentation = {
	Animation: string?,
	Looped: boolean?,
	Trail: boolean?,
	Cues: { Cue },
	Preview: "Cone" | "Ring" | "Charge" | "Projectile",
	HalfAngle: number?,
	Height: number?,
	Effects: { Cast: string?, Impact: string? },
}
export type Slow = { Ratio: number, Duration: number, Key: string }
export type Projectile = {
	Damage: number,
	MaxTargets: number,
	Angles: { number },
	Slow: Slow?,
}
export type Definition = {
	Id: Id,
	Name: string,
	Weapon: Weapon,
	Slot: Slot,
	Cooldown: number,
	Stamina: number,
	Range: number,
	Duration: number,
	Windup: number,
	Aim: "Instant" | "Direction" | "Target",
	Presentation: Presentation,
	Projectile: Projectile?,
}

return {}

--!strict
local SkillDefinitions = require(game:GetService("ReplicatedStorage").Shared.Combat.SkillDefinitions)

export type Request = {
	Direction: Vector3,
	Target: Instance?,
	Player: Player?,
}
export type Hit = (attacker: Model, target: Model, damage: number, label: string, stagger: boolean?) -> boolean
export type Handler = (Model, SkillDefinitions.Definition, Request, Hit) -> boolean

return {}

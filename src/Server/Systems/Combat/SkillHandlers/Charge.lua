--!strict
local Skills = require(script.Parent.Parent.Skills)
local Types = require(script.Parent.Types)
local SkillDefinitions = require(game:GetService("ReplicatedStorage").Shared.Combat.SkillDefinitions)

local function Charge(
	character: Model,
	definition: SkillDefinitions.Definition,
	request: Types.Request,
	hit: Types.Hit
): boolean
	local target = request.Target
	if not target then
		return false
	end
	local function apply(attacker: Model, victim: Model, damage: number): boolean
		return hit(attacker, victim, damage, definition.Name, false)
	end
	if request.Player then
		return Skills.TryCharge(request.Player, target, apply)
	end
	return Skills.CastCharge(character, target, apply)
end

return Charge

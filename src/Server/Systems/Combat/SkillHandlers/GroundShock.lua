--!strict
local Skills = require(script.Parent.Parent.Skills)
local Types = require(script.Parent.Types)
local SkillDefinitions = require(game:GetService("ReplicatedStorage").Shared.Combat.SkillDefinitions)

local function GroundShock(
	character: Model,
	definition: SkillDefinitions.Definition,
	request: Types.Request,
	hit: Types.Hit
): boolean
	local function apply(attacker: Model, target: Model, damage: number): boolean
		return hit(attacker, target, damage, definition.Name, false)
	end
	if request.Player then
		return Skills.TryGroundShock(request.Player, request.Direction, apply)
	end
	return Skills.CastGroundShock(character, request.Direction, apply)
end

return GroundShock

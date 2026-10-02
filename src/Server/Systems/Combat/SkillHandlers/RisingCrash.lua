--!strict
local Skills = require(script.Parent.Parent.Skills)
local Types = require(script.Parent.Types)
local SkillDefinitions = require(game:GetService("ReplicatedStorage").Shared.Combat.SkillDefinitions)

local function RisingCrash(
	character: Model,
	definition: SkillDefinitions.Definition,
	request: Types.Request,
	hit: Types.Hit
): boolean
	local function apply(attacker: Model, target: Model, damage: number): boolean
		return hit(attacker, target, damage, definition.Name, if request.Player then nil else true)
	end
	if request.Player then
		return Skills.TryRisingCrash(request.Player, request.Direction, apply)
	end
	return Skills.CastRisingCrash(character, request.Direction, apply)
end

return RisingCrash

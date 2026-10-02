--!strict
local Skills = require(script.Parent.Parent.Skills)
local Types = require(script.Parent.Types)
local SkillDefinitions = require(game:GetService("ReplicatedStorage").Shared.Combat.SkillDefinitions)

local function WindSpin(
	character: Model,
	definition: SkillDefinitions.Definition,
	request: Types.Request,
	hit: Types.Hit
): boolean
	local function apply(attacker: Model, target: Model, damage: number): boolean
		return hit(attacker, target, damage, definition.Name, false)
	end
	if request.Player then
		return Skills.TrySpin(request.Player, apply)
	end
	return Skills.CastSpin(character, apply)
end

return WindSpin

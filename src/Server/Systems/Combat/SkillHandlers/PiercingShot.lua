--!strict
local Yumi = require(script.Parent.Parent.Yumi)
local Types = require(script.Parent.Types)
local SkillDefinitions = require(game:GetService("ReplicatedStorage").Shared.Combat.SkillDefinitions)

local function PiercingShot(
	character: Model,
	definition: SkillDefinitions.Definition,
	request: Types.Request,
	hit: Types.Hit
): boolean
	local index = SkillDefinitions.Index(definition.Slot)
	if not index then
		return false
	end
	return Yumi:Cast(character, index, request.Direction, function(attacker, target, damage, label)
		return hit(attacker, target, damage, label, false)
	end)
end

return PiercingShot

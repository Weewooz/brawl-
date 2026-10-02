--!strict
local SkillDefinitions = require(game:GetService("ReplicatedStorage").Shared.Combat.SkillDefinitions)
local Types = require(script.Parent.Types)

return function(SkillHandlers: typeof(require(script.Parent)))
	local character = Instance.new("Model")
	local player: Player = { Character = nil } :: any
	local request: Types.Request = { Direction = Vector3.xAxis }
	local function hit(): boolean
		error("Rejected skill requests must not apply hits")
	end
	for _, weapon in { "Katana", "Yumi" } do
		local definitions = SkillDefinitions.ForWeapon(weapon)
		assert(definitions, "Starter skill definitions must exist")
		for _, definition in definitions do
			character:SetAttribute("Weapon", if weapon == "Katana" then "Yumi" else "Katana")
			assert(not SkillHandlers.Cast(character, definition, request, hit), "Skills must match the equipped weapon")
			character:SetAttribute("Weapon", weapon)
			local forged = table.clone(definition)
			forged.Stamina = 0
			assert(not SkillHandlers.Cast(character, forged, request, hit), "Unregistered definitions must be rejected")
			request.Player = player
			assert(
				not SkillHandlers.Cast(character, definition, request, hit),
				"Player requests must own the character"
			)
			request.Player = nil
		end
	end
	character:Destroy()
	return "Skill handler definition, weapon, and character ownership checks passed"
end

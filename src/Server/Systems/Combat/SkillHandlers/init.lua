--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Weapons = require(ReplicatedStorage.Shared.Combat.Weapons)
local SkillDefinitions = require(ReplicatedStorage.Shared.Combat.SkillDefinitions)
local Types = require(script.Types)

export type Request = Types.Request
export type Hit = Types.Hit

local Handlers: { [string]: Types.Handler } = table.freeze({
	RisingCrash = require(script.RisingCrash),
	WindSpin = require(script.WindSpin),
	Charge = require(script.Charge),
	GroundShock = require(script.GroundShock),
	PiercingShot = require(script.PiercingShot),
	Volley = require(script.Volley),
	QuickShot = require(script.QuickShot),
	PinningShot = require(script.PinningShot),
})

local SkillHandlers = {}

function SkillHandlers.Cast(
	character: Model,
	definition: SkillDefinitions.Definition,
	request: Request,
	hit: Hit
): boolean
	local handler = Handlers[definition.Id]
	if
		not handler
		or SkillDefinitions.Get(definition.Id) ~= definition
		or Weapons.Weapon(character) ~= definition.Weapon
	then
		return false
	end
	if request.Player and request.Player.Character ~= character then
		return false
	end
	return handler(character, definition, request, hit)
end

return table.freeze(SkillHandlers)

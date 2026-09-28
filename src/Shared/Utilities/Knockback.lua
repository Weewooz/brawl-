--!strict
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tags = require(ReplicatedStorage.Shared.Core.Tags)

local COMBATANT_TAG = Tags.Combatant
local UPWARD_BIAS = 0.3

local Knockback = {}

local function GetRoot(character: Model): BasePart?
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end

	return character.PrimaryPart or character:FindFirstChildWhichIsA("BasePart")
end

local function GetEligibleRoot(character: Model): BasePart?
	if not CollectionService:HasTag(character, COMBATANT_TAG) then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = GetRoot(character)
	if not humanoid or humanoid.Health <= 0 or not rootPart or rootPart.Anchored then
		return nil
	end

	return rootPart
end

local function CanApply(character: Model): boolean
	return GetEligibleRoot(character) ~= nil
end

Knockback.CanApply = CanApply

function Knockback.GetRadial(
	character: Model,
	origin: Vector3,
	radius: number,
	minimumVelocityChange: number,
	maximumVelocityChange: number
): (Vector3?, number)
	local rootPart = GetEligibleRoot(character)
	if not rootPart or radius <= 0 then
		return nil, 0
	end

	local offset = rootPart.Position - origin
	local distance = offset.Magnitude
	if distance > radius then
		return nil, 0
	end

	local alpha = 1 - math.clamp(distance / radius, 0, 1)
	local velocityChange = minimumVelocityChange + (maximumVelocityChange - minimumVelocityChange) * alpha
	local direction = if distance > 0.001 then offset.Unit else Vector3.yAxis
	return direction, velocityChange
end

function Knockback.Apply(character: Model, direction: Vector3, velocityChange: number): boolean
	local rootPart = GetEligibleRoot(character)
	if not rootPart or velocityChange <= 0 then
		return false
	end

	local biasedDirection = direction + Vector3.yAxis * UPWARD_BIAS
	if biasedDirection.Magnitude < 0.001 then
		biasedDirection = Vector3.yAxis
	end

	rootPart:ApplyImpulse(biasedDirection.Unit * velocityChange * rootPart.AssemblyMass)
	return true
end

function Knockback.ApplyRadial(
	character: Model,
	origin: Vector3,
	radius: number,
	minimumVelocityChange: number,
	maximumVelocityChange: number
): number
	local direction, velocityChange =
		Knockback.GetRadial(character, origin, radius, minimumVelocityChange, maximumVelocityChange)
	if not direction then
		return 0
	end

	return if Knockback.Apply(character, direction, velocityChange) then velocityChange else 0
end

return Knockback

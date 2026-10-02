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
	if velocityChange <= 0 then
		return false
	end

	return Knockback.ApplyVelocity(character, Knockback.VelocityChange(direction, velocityChange))
end

function Knockback.VelocityChange(direction: Vector3, velocityChange: number): Vector3
	local biasedDirection = direction + Vector3.yAxis * UPWARD_BIAS
	if biasedDirection.Magnitude < 0.001 then
		biasedDirection = Vector3.yAxis
	end

	return biasedDirection.Unit * velocityChange
end

function Knockback.CancelDash(character: Model)
	local rootPart = GetRoot(character)
	if not rootPart then
		return
	end
	local velocity = rootPart:FindFirstChild("DashVelocity")
	if velocity then
		velocity:Destroy()
	end
	local attachment = rootPart:FindFirstChild("DashAttachment")
	if attachment then
		attachment:Destroy()
	end
end

function Knockback.ApplyVelocity(character: Model, velocityChange: Vector3): boolean
	local rootPart = GetEligibleRoot(character)
	if not rootPart or velocityChange.Magnitude <= 0 then
		return false
	end

	Knockback.CancelDash(character)
	rootPart.AssemblyLinearVelocity = velocityChange
	return true
end

function Knockback.ApplySustained(character: Model, velocityChange: Vector3, duration: number): boolean
	local rootPart = GetEligibleRoot(character)
	local horizontal = Vector3.new(velocityChange.X, 0, velocityChange.Z)
	if not rootPart or horizontal.Magnitude <= 0 or duration <= 0 then
		return false
	end

	Knockback.CancelDash(character)
	local previousVelocity = rootPart:FindFirstChild("StaggerVelocity")
	if previousVelocity then
		previousVelocity:Destroy()
	end
	local previousAttachment = rootPart:FindFirstChild("StaggerAttachment")
	if previousAttachment then
		previousAttachment:Destroy()
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "StaggerAttachment"
	attachment.Parent = rootPart
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "StaggerVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.ForceLimitsEnabled = true
	velocity.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	local force = rootPart.AssemblyMass * 600
	velocity.MaxAxesForce = Vector3.new(force, 0, force)
	velocity.VectorVelocity = horizontal
	velocity.Parent = rootPart
	rootPart.AssemblyLinearVelocity = horizontal + Vector3.yAxis * rootPart.AssemblyLinearVelocity.Y
	task.delay(duration, function()
		velocity:Destroy()
		attachment:Destroy()
	end)
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

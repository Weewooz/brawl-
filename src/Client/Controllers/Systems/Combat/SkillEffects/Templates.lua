--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type Effect = { Instances: { Instance }, Until: number }

local Templates = {}
local Missing: { [string]: boolean } = {}

local function Anchor(instance: Instance): CFrame?
	if instance:IsA("PVInstance") then
		return instance:GetPivot()
	elseif instance:IsA("Attachment") then
		return instance.WorldCFrame
	end
	for _, child in instance:GetChildren() do
		local anchor = Anchor(child)
		if anchor then
			return anchor
		end
	end
	return nil
end

local function Place(instance: Instance, delta: CFrame, root: BasePart, detached: { Instance })
	if instance:IsA("PVInstance") then
		instance:PivotTo(delta * instance:GetPivot())
	elseif instance:IsA("Attachment") then
		local placement = delta * instance.WorldCFrame
		instance.Parent = root
		instance.WorldCFrame = placement
		if not table.find(detached, instance) then
			table.insert(detached, instance)
		end
	else
		for _, child in instance:GetChildren() do
			Place(child, delta, root, detached)
		end
	end
end

function Templates.Spawn(
	name: string,
	root: BasePart,
	position: Vector3,
	direction: Vector3?,
	now: number,
	duration: number
): Effect?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local effects = assets and assets:FindFirstChild("Effects")
	local template = effects
	for segment in string.gmatch(name, "[^/]+") do
		template = template and template:FindFirstChild(segment)
	end
	if not template or template == effects then
		if not Missing[name] then
			Missing[name] = true
			warn("[Combat.SkillEffects] Author the effect template at ReplicatedStorage.Assets.Effects/" .. name)
		end
		return nil
	end
	Missing[name] = nil
	local effect = template:Clone()
	local anchor = Anchor(effect)
	if not anchor then
		effect:Destroy()
		warn("[Combat.SkillEffects] Effect template needs an authored Model, BasePart, or Attachment: " .. name)
		return nil
	end
	local placement = if direction and direction.Magnitude > 0.001
		then CFrame.lookAt(position, position + direction)
		else CFrame.new(position)
	local instances: { Instance } = { effect }
	Place(effect, placement * anchor:Inverse(), root, instances)
	if not effect:IsA("Attachment") then
		effect.Parent = workspace
	end
	local lifetime = duration
	local authoredLifetime = template:GetAttribute("Lifetime")
	if typeof(authoredLifetime) == "number" and authoredLifetime >= 0 and authoredLifetime < math.huge then
		lifetime = authoredLifetime
	end
	for _, instance in instances do
		local descendants = instance:GetDescendants()
		table.insert(descendants, instance)
		for _, descendant in descendants do
			if descendant:IsA("ParticleEmitter") then
				local count = descendant:GetAttribute("EmitCount")
				descendant:Emit(
					if typeof(count) == "number" and count >= 0 and count < math.huge then math.floor(count) else 1
				)
				lifetime = math.max(lifetime, descendant.Lifetime.Max + 0.05)
			end
		end
	end
	return { Instances = instances, Until = now + lifetime }
end

function Templates.Destroy(effect: Effect)
	for _, instance in effect.Instances do
		instance:Destroy()
	end
end

return Templates

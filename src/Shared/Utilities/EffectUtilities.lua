--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EffectsFolder = ReplicatedStorage.Assets:WaitForChild("Effects")

local EffectUtilities = {}

local SoundEffectCache = {}
local FailedSoundEffectSearches = {}

--==========================-- Private Functions --==========================--

local function FindParticleAttachment(name: string): Attachment?
	if type(name) ~= "string" then
		return nil
	end

	local effect: Attachment? = SoundEffectCache[name]
	if not effect and not FailedSoundEffectSearches[name] then
		local potentialEffect: Instance? = EffectsFolder:FindFirstChild(name, true)
		if potentialEffect and not potentialEffect:IsA("Attachment") then
			potentialEffect = potentialEffect:FindFirstChildWhichIsA("Attachment")
		end

		if potentialEffect and potentialEffect:IsA("Attachment") then
			effect = potentialEffect
			SoundEffectCache[name] = effect
		else
			effect = nil
			FailedSoundEffectSearches[name] = true
		end
	end

	return effect
end

local function EmitParticleEffect(instance: Instance): number
	local longestLifespan = 0

	for _, v in instance:GetDescendants() do
		if v:IsA("ParticleEmitter") then
			local emitCountAttribute = v:GetAttribute("EmitCount")
			local emitCount = type(emitCountAttribute) == "number" and emitCountAttribute or 1

			if v.Lifetime.Max > longestLifespan then
				longestLifespan = v.Lifetime.Max
			end

			v:Emit(emitCount)
		end
	end

	return longestLifespan
end

local function GetEffectPlacementCFrame(position: Vector3, normal: Vector3?): CFrame
	if normal and normal.Magnitude > 0 then
		return CFrame.lookAt(position, position - normal)
	end

	return CFrame.new(position)
end

local function GetAnchorWorldCFrame(instance: Instance): CFrame?
	if instance:IsA("Attachment") then
		return instance.WorldCFrame
	end

	if instance:IsA("PVInstance") then
		return instance:GetPivot()
	end

	local attachment = instance:FindFirstChildWhichIsA("Attachment", true)
	if attachment then
		return attachment.WorldCFrame
	end

	local pvInstance = instance:FindFirstChildWhichIsA("PVInstance", true)
	if pvInstance then
		return pvInstance:GetPivot()
	end

	return nil
end

local function ApplyEffectWorldCFrame(instance: Instance, targetCFrame: CFrame)
	if instance:IsA("Attachment") then
		instance.WorldCFrame = targetCFrame
		return
	end

	if instance:IsA("PVInstance") then
		instance:PivotTo(targetCFrame)
		return
	end

	local anchorWorldCFrame = GetAnchorWorldCFrame(instance)
	if not anchorWorldCFrame then
		return
	end

	local deltaCFrame = targetCFrame * anchorWorldCFrame:Inverse()

	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("Attachment") then
			descendant.WorldCFrame = deltaCFrame * descendant.WorldCFrame
		elseif descendant:IsA("PVInstance") then
			descendant:PivotTo(deltaCFrame * descendant:GetPivot())
		end
	end
end

local function PlayEffectAtPosition(effectTemplate: Instance?, position: Vector3, normal: Vector3?)
	if not effectTemplate then
		return
	end

	local effect = effectTemplate:Clone()
	ApplyEffectWorldCFrame(effect, GetEffectPlacementCFrame(position, normal))
	effect.Parent = workspace

	local debrisTime = EmitParticleEffect(effect)
	task.delay(debrisTime + 0.05, function()
		if effect.Parent then
			effect:Destroy()
		end
	end)
end

local function PlayParticleAttachmentAtPosition(attachmentTemplate: Attachment?, position: Vector3, normal: Vector3?)
	if not attachmentTemplate then
		return
	end
	PlayEffectAtPosition(attachmentTemplate, position, normal)
end

--==========================-- Public Functions --==========================--

function EffectUtilities:FindParticleAttachment(name: string): Attachment?
	return FindParticleAttachment(name)
end

function EffectUtilities:PlayEffectAtPosition(effectTemplate: Instance?, position: Vector3, normal: Vector3?)
	PlayEffectAtPosition(effectTemplate, position, normal)
end

function EffectUtilities:PlayParticleAttachmentAtPosition(
	attachmentTemplate: Attachment?,
	position: Vector3,
	normal: Vector3?
)
	PlayParticleAttachmentAtPosition(attachmentTemplate, position, normal)
end

return EffectUtilities

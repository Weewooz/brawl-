--!strict
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Tags = require(ReplicatedStorage.Shared.Core.Tags)

export type Sample = {
	Time: number,
	CFrame: CFrame,
	Blocking: boolean,
}

local History = {}
local Samples: { [Model]: { Sample } } = {}
local Elapsed = 0
local STEP = 0.025
local WINDOW = 0.65
local VIEW_LAG = 0.2

function History.Step(dt: number)
	Elapsed += dt
	if Elapsed < STEP then
		return
	end
	Elapsed -= STEP
	local now = Workspace:GetServerTimeNow()
	for _, instance in CollectionService:GetTagged(Tags.Combatant) do
		if not instance:IsA("Model") then
			continue
		end
		local root = instance:FindFirstChild("HumanoidRootPart")
		local humanoid = instance:FindFirstChildOfClass("Humanoid")
		if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
			continue
		end
		local samples = Samples[instance]
		if not samples then
			samples = {}
			Samples[instance] = samples
			instance.Destroying:Connect(function()
				Samples[instance] = nil
			end)
		end
		table.insert(samples, {
			Time = now,
			CFrame = root.CFrame,
			Blocking = instance:GetAttribute("Blocking") == true,
		})
		while samples[1] and now - samples[1].Time > WINDOW do
			table.remove(samples, 1)
		end
	end
end

function History.Get(model: Model, at: number): Sample?
	local samples = Samples[model]
	if not samples then
		return nil
	end
	local best: Sample? = nil
	local distance = math.huge
	for _, sample in samples do
		local gap = math.abs(sample.Time - at)
		if gap < distance then
			best = sample
			distance = gap
		end
	end
	return if distance <= 0.06 then best else nil
end

function History.FindTarget(model: Model, at: number, position: Vector3): Sample?
	local samples = Samples[model]
	if not samples then
		return nil
	end
	local best: Sample? = nil
	local distance = math.huge
	for _, sample in samples do
		if sample.Time >= at - VIEW_LAG and sample.Time <= at + 0.025 then
			local gap = (sample.CFrame.Position - position).Magnitude
			if gap < distance then
				best = sample
				distance = gap
			end
		end
	end
	return if distance <= 3.5 then best else nil
end

return History

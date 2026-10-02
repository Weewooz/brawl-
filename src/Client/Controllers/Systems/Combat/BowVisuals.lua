--!strict
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Weapons = require(ReplicatedStorage.Shared.Combat.Weapons)
local Authority = require(ReplicatedStorage.Shared.Capture.Authority)

type Flight = {
	Part: BasePart,
	Origin: Vector3,
	Direction: Vector3,
	Speed: number,
	Range: number,
	FiredAt: number,
	Travelled: number,
	Shooter: Model?,
	Ignored: { Instance },
	Hits: number,
	Limit: number,
	Active: boolean,
}
type Pose = { Left: Motor6D, Right: Motor6D }
export type API = {
	Init: (self: API) -> (),
	Fire: (self: API, Instance, Vector3, Vector3, number, number, number, number) -> (),
	Step: (self: API) -> (),
	Pose: (self: API) -> (),
}
local Visuals = {} :: API
local Flights: { Flight } = {}
local Poses: { [Model]: Pose } = {}
local CAPACITY = 32
local Next = 0
local Sight = RaycastParams.new()
Sight.FilterType = Enum.RaycastFilterType.Exclude
Sight.RespectCanCollide = false
local CAST_SIZE = Vector3.new(0.25, 0.25, 0.8)

local function ClearPose(pose: Pose)
	pose.Left.Transform = CFrame.identity
	pose.Right.Transform = CFrame.identity
end

function Visuals:Init()
	local arrow = ReplicatedStorage.Assets.Weapons:WaitForChild("Arrow") :: BasePart
	assert(
		arrow.Anchored and not arrow.CanCollide and not arrow.CanQuery and not arrow.CanTouch,
		"[Combat] Arrow visuals require an anchored, nonphysical template"
	)
	for _ = 1, CAPACITY do
		local part = arrow:Clone()
		part.Transparency = 1
		part.Parent = workspace:WaitForChild("Visual")
		table.insert(Flights, {
			Part = part,
			Origin = Vector3.zero,
			Direction = Vector3.zAxis,
			Speed = 0,
			Range = 0,
			FiredAt = 0,
			Travelled = 0,
			Shooter = nil,
			Ignored = {},
			Hits = 0,
			Limit = 1,
			Active = false,
		})
	end
end

function Visuals:Fire(
	shooter: Instance,
	origin: Vector3,
	direction: Vector3,
	speed: number,
	range: number,
	firedAt: number,
	pierceLimit: number
)
	if #Flights == 0 or direction.Magnitude < 0.001 or speed <= 0 or range <= 0 then
		return
	end
	Next = Next % #Flights + 1
	local flight = Flights[Next]
	flight.Origin = origin
	flight.Direction = direction.Unit
	flight.Speed = speed
	flight.Range = range
	flight.FiredAt = firedAt
	flight.Travelled = 0
	flight.Shooter = if shooter:IsA("Model") then shooter else nil
	flight.Ignored = { flight.Part, shooter }
	flight.Hits = 0
	flight.Limit = math.clamp(pierceLimit, 1, 2)
	flight.Active = true
	flight.Part.Transparency = 0
	flight.Part.CFrame = CFrame.lookAt(origin, origin + flight.Direction)
end

local function Target(part: BasePart): Model?
	local ancestor: Instance? = part
	while ancestor and ancestor ~= workspace do
		if ancestor:IsA("Model") and ancestor:FindFirstChildOfClass("Humanoid") then
			return ancestor
		end
		ancestor = ancestor.Parent
	end
	return nil
end

local function Opponent(shooter: Model?, target: Model, now: number): boolean
	local humanoid = target:FindFirstChildOfClass("Humanoid")
	if
		not shooter
		or not humanoid
		or humanoid.Health <= 0
		or not CollectionService:HasTag(target, "Combatant")
		or target:GetAttribute("DungeonDowned") == true
		or target:FindFirstChildOfClass("ForceField") ~= nil
		or (Players:GetPlayerFromCharacter(target) ~= nil and (target:GetAttribute("DashingUntil") or 0) > now)
		or not Authority.CanHit(Authority.Read(shooter), Authority.Read(target), now)
	then
		return false
	end
	local run = shooter:GetAttribute("DungeonRunId")
	local targetRun = target:GetAttribute("DungeonRunId")
	if run ~= nil or targetRun ~= nil then
		return run ~= nil
			and run == targetRun
			and (CollectionService:HasTag(shooter, "DungeonMob") or CollectionService:HasTag(target, "DungeonMob"))
	end
	return true
end

function Visuals:Step()
	local now = workspace:GetServerTimeNow()
	for _, flight in Flights do
		if not flight.Active then
			continue
		end
		local distance = math.clamp((now - flight.FiredAt) * flight.Speed, 0, flight.Range)
		local previous = flight.Origin + flight.Direction * flight.Travelled
		local position = flight.Origin + flight.Direction * distance
		local stopped = false
		if distance > flight.Travelled then
			for index = 1, 16 do
				Sight.FilterDescendantsInstances = flight.Ignored
				local hit = workspace:Blockcast(
					CFrame.lookAt(previous, previous + flight.Direction),
					CAST_SIZE,
					position - previous,
					Sight
				)
				if not hit then
					break
				end
				local target = Target(hit.Instance)
				if not target then
					stopped = true
					break
				end
				table.insert(flight.Ignored, target)
				if Opponent(flight.Shooter, target, now) then
					flight.Hits += 1
					if flight.Hits >= flight.Limit then
						stopped = true
						break
					end
				end
				if index == 16 then
					stopped = true
				end
			end
		end
		if stopped or distance >= flight.Range then
			flight.Active = false
			flight.Part.Transparency = 1
		else
			flight.Part.CFrame = CFrame.lookAt(position, position + flight.Direction)
			flight.Travelled = distance
		end
	end
end

-- Apply after Animator updates, before physics reads Motor6D transforms.
function Visuals:Pose()
	local seen: { [Model]: boolean } = {}
	for _, instance in CollectionService:GetTagged("Combatant") do
		if not instance:IsA("Model") or Weapons.Weapon(instance) ~= "Yumi" then
			continue
		end
		local started = instance:GetAttribute("BowDrawStartedAt")
		if typeof(started) ~= "number" or started <= 0 then
			continue
		end
		local leftArm = instance:FindFirstChild("LeftUpperArm")
		local rightArm = instance:FindFirstChild("RightUpperArm")
		local left = leftArm and leftArm:FindFirstChild("LeftShoulder")
		local right = rightArm and rightArm:FindFirstChild("RightShoulder")
		if not left or not left:IsA("Motor6D") or not right or not right:IsA("Motor6D") then
			continue
		end
		seen[instance] = true
		local pose = Poses[instance]
		if not pose then
			pose = { Left = left, Right = right }
			Poses[instance] = pose
		end
		pose.Left.Transform = CFrame.Angles(math.rad(85), 0, math.rad(-12))
		pose.Right.Transform = CFrame.Angles(math.rad(85), math.rad(-32), math.rad(38))
	end
	for character, pose in Poses do
		if not seen[character] then
			ClearPose(pose)
			Poses[character] = nil
		end
	end
end

return Visuals

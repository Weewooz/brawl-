--!strict
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Combat.Config)
local SkillDefinitions = require(ReplicatedStorage.Shared.Combat.SkillDefinitions)
local Tags = require(ReplicatedStorage.Shared.Core.Tags)
local Katana = require(script.Parent.Katana)
local Status = require(script.Parent.Status)
local CaptureAuthority = require(ReplicatedStorage.Shared.Capture.Authority)

type Hit = (Model, Model, number) -> boolean
type ChargeState = {
	Connection: RBXScriptConnection?,
	Root: BasePart,
	ServerOwned: boolean,
}
type DirectionalConfig = {
	Range: number,
	Height: number,
	HalfAngle: number,
	Windup: number,
	Duration: number,
	Cooldown: number,
	Stamina: number,
	Damage: number,
}
type DirectionalState = {
	Connection: RBXScriptConnection?,
	Attribute: string,
}

local Skills = {}
local Spins: { [Model]: RBXScriptConnection } = {}
local Charges: { [Model]: ChargeState } = {}
local ChargeRequests: { [Player]: number } = {}
local Directionals: { [Model]: DirectionalState } = {}

Players.PlayerRemoving:Connect(function(player)
	ChargeRequests[player] = nil
end)

local function Living(model: Model?): BasePart?
	if not model then
		return nil
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	return if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then root else nil
end

local function Opponent(attacker: Model, target: Model): boolean
	if target == attacker or not CollectionService:HasTag(target, Tags.Combatant) then
		return false
	end
	if
		not CaptureAuthority.CanHit(
			CaptureAuthority.Read(attacker),
			CaptureAuthority.Read(target),
			Workspace:GetServerTimeNow()
		)
	then
		return false
	end
	if attacker:GetAttribute("DungeonDowned") == true or target:GetAttribute("DungeonDowned") == true then
		return false
	end
	if CollectionService:HasTag(attacker, "DungeonMob") or CollectionService:HasTag(target, "DungeonMob") then
		local runId = attacker:GetAttribute("DungeonRunId")
		return runId ~= nil and runId == target:GetAttribute("DungeonRunId")
	end
	return true
end

local function ClearSight(origin: Vector3, target: Vector3): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = CollectionService:GetTagged(Tags.Combatant)
	return Workspace:Raycast(origin, target - origin, params) == nil
end

local function TargetFromPart(part: BasePart): Model?
	local ancestor: Instance? = part
	while ancestor do
		if ancestor:IsA("Model") and ancestor:FindFirstChildOfClass("Humanoid") then
			return ancestor
		end
		ancestor = ancestor.Parent
	end
	return nil
end

local function EndSpin(character: Model)
	local connection = Spins[character]
	if not connection then
		return
	end
	Spins[character] = nil
	connection:Disconnect()
	Status.SetSpin(character, 0)
	Katana.SetTrail(character, false)
end

function Skills.CastSpin(character: Model, hit: Hit): boolean
	local root = Living(character)
	if
		not character
		or not root
		or not CaptureAuthority.CanAttack(CaptureAuthority.Read(character), Workspace:GetServerTimeNow())
		or not character:FindFirstChild("Katana")
		or not Status.CanAct(character)
		or Status.Busy(character)
		or Status.Dashing(character)
	then
		return false
	end
	local now = Workspace:GetServerTimeNow()
	if
		character:GetAttribute("DungeonDowned") == true
		or (character:GetAttribute("SpinReadyAt") or 0) > now
		or (character:GetAttribute("AttackReadyAt") or 0) > now
		or Status.Rooted(character)
	then
		return false
	end
	if not Status.ConsumeStamina(character, Config.Spin.Stamina) then
		return false
	end
	Skills.Cancel(character)
	character:SetAttribute("SpinReadyAt", now + Config.Spin.Cooldown)
	Status.SetSpin(character, now + Config.Spin.Duration)
	local definition = SkillDefinitions.Get("WindSpin")
	Katana.SetTrail(character, definition ~= nil and definition.Presentation.Trail == true)
	local endsAt = now + Config.Spin.Duration
	local nextHit = now + Config.Spin.FirstHit
	local hits = 0
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	Spins[character] = RunService.Heartbeat:Connect(function()
		local current = Workspace:GetServerTimeNow()
		if
			current >= endsAt
			or not Living(character)
			or not CaptureAuthority.CanAttack(CaptureAuthority.Read(character), Workspace:GetServerTimeNow())
			or not character:FindFirstChild("Katana")
			or not Status.CanAct(character)
			or character:GetAttribute("DungeonDowned") == true
		then
			EndSpin(character)
			return
		end
		if hits >= Config.Spin.Hits or current < nextHit then
			return
		end
		hits += 1
		nextHit += Config.Spin.Interval
		local seen: { [Model]: boolean } = {}
		for _, part in Workspace:GetPartBoundsInRadius(root.Position, Config.Spin.Radius, params) do
			local target = TargetFromPart(part)
			if target and not seen[target] and Opponent(character, target) then
				seen[target] = true
				local targetRoot = Living(target)
				if
					targetRoot
					and math.abs(targetRoot.Position.Y - root.Position.Y) <= Config.Spin.Height
					and (targetRoot.Position - root.Position).Magnitude <= Config.Spin.Radius
					and ClearSight(root.Position, targetRoot.Position)
				then
					hit(character, target, Config.Spin.Damage)
				end
			end
		end
	end)
	return true
end

local function EndDirectional(character: Model)
	local state = Directionals[character]
	if not state then
		return
	end
	Directionals[character] = nil
	if state.Connection then
		state.Connection:Disconnect()
	end
	character:SetAttribute(state.Attribute, 0)
	Katana.SetTrail(character, false)
end

local function Direction(requested: Vector3, root: BasePart): Vector3?
	if typeof(requested) ~= "Vector3" then
		return nil
	end
	for _, component in { requested.X, requested.Y, requested.Z } do
		if component ~= component or math.abs(component) >= 1e6 then
			return nil
		end
	end
	local flat = Vector3.new(requested.X, 0, requested.Z)
	if flat.Magnitude < 0.01 then
		local facing = root.CFrame.LookVector
		flat = Vector3.new(facing.X, 0, facing.Z)
	end
	return if flat.Magnitude > 0.01 then flat.Unit else nil
end

local function ConeTargets(character: Model, root: BasePart, aim: Vector3, config: DirectionalConfig): { Model }
	local targets = {}
	local cosine = math.cos(math.rad(config.HalfAngle))
	for _, instance in CollectionService:GetTagged(Tags.Combatant) do
		if not instance:IsA("Model") or not instance:IsDescendantOf(Workspace) or not Opponent(character, instance) then
			continue
		end
		local targetRoot = Living(instance)
		if not targetRoot then
			continue
		end
		local offset = targetRoot.Position - root.Position
		local flat = Vector3.new(offset.X, 0, offset.Z)
		if
			flat.Magnitude <= config.Range
			and math.abs(offset.Y) <= config.Height
			and (flat.Magnitude <= 0.1 or flat.Unit:Dot(aim) >= cosine)
			and ClearSight(root.Position, targetRoot.Position)
		then
			table.insert(targets, instance)
		end
	end
	table.sort(targets, function(first, second)
		local firstRoot = Living(first)
		local secondRoot = Living(second)
		return firstRoot ~= nil
			and (
				secondRoot == nil
				or (firstRoot.Position - root.Position).Magnitude < (secondRoot.Position - root.Position).Magnitude
			)
	end)
	return targets
end

local function TryDirectional(
	character: Model,
	requested: Vector3,
	name: string,
	config: DirectionalConfig,
	onImpact: (Model, BasePart, Vector3) -> ()
): boolean
	local root = Living(character)
	if
		not character
		or not root
		or root.Anchored
		or not CaptureAuthority.CanAttack(CaptureAuthority.Read(character), Workspace:GetServerTimeNow())
		or not character:FindFirstChild("Katana")
		or not Status.CanAct(character)
		or Status.Busy(character)
		or Status.Dashing(character)
	then
		return false
	end
	local now = Workspace:GetServerTimeNow()
	local weapon = character:FindFirstChild("Katana")
	if
		character:GetAttribute("DungeonDowned") == true
		or not weapon
		or not weapon:FindFirstChild("Sword")
		or (character:GetAttribute(name .. "ReadyAt") or 0) > now
		or (character:GetAttribute("AttackReadyAt") or 0) > now
	then
		return false
	end
	local aim = Direction(requested, root)
	if not aim then
		return false
	end
	if Status.Active(character, "Confuse") then
		aim = -aim
	end
	if not Status.ConsumeStamina(character, config.Stamina) then
		return false
	end
	Skills.Cancel(character)
	Status.SetSprinting(character, false)
	character:SetAttribute(name .. "ReadyAt", now + config.Cooldown)
	character:SetAttribute(name .. "Until", now + config.Duration)
	character:SetAttribute(name .. "Direction", aim)
	root.CFrame = CFrame.lookAt(root.Position, root.Position + aim)
	local definition = SkillDefinitions.Resolve("Katana", name)
	Katana.SetTrail(character, definition ~= nil and definition.Presentation.Trail == true)
	local state: DirectionalState = { Connection = nil, Attribute = name .. "Until" }
	Directionals[character] = state
	local impacted = false
	state.Connection = RunService.Heartbeat:Connect(function()
		local current = Workspace:GetServerTimeNow()
		local currentRoot = Living(character)
		if
			current >= now + config.Duration
			or not currentRoot
			or not CaptureAuthority.CanAttack(CaptureAuthority.Read(character), Workspace:GetServerTimeNow())
			or not character:FindFirstChild("Katana")
			or not Status.CanAct(character)
			or character:GetAttribute("DungeonDowned") == true
		then
			EndDirectional(character)
			return
		end
		if not impacted and current >= now + config.Windup then
			impacted = true
			onImpact(character, currentRoot, aim :: Vector3)
		end
	end)
	return true
end

function Skills.CastRisingCrash(character: Model, direction: Vector3, hit: Hit): boolean
	return TryDirectional(character, direction, "RisingCrash", Config.RisingCrash, function(character, root, aim)
		local target = ConeTargets(character, root, aim, Config.RisingCrash)[1]
		if
			target
			and hit(character, target, Config.RisingCrash.Damage)
			and Living(target)
			and target:GetAttribute("CaptureActive") ~= false
			and target:GetAttribute("DungeonDowned") ~= true
		then
			Status.ApplyExposed(target, Config.RisingCrash.ExposedDuration)
		end
	end)
end

function Skills.CastGroundShock(character: Model, direction: Vector3, hit: Hit): boolean
	return TryDirectional(character, direction, "GroundShock", Config.GroundShock, function(character, root, aim)
		for _, target in ConeTargets(character, root, aim, Config.GroundShock) do
			if
				hit(character, target, Config.GroundShock.Damage)
				and Living(target)
				and target:GetAttribute("CaptureActive") ~= false
				and target:GetAttribute("DungeonDowned") ~= true
			then
				Skills.Cancel(target)
				Status.ApplySlow(target, Config.GroundShock.SlowRatio, Config.GroundShock.SlowDuration, "GroundShock")
				Status.ApplyPush(target, aim, Config.GroundShock.PushDistance, Config.GroundShock.PushDuration)
			end
		end
	end)
end

local function EndCharge(character: Model)
	local state = Charges[character]
	if not state then
		return
	end
	Charges[character] = nil
	if state.Connection then
		state.Connection:Disconnect()
	end
	if
		state.ServerOwned
		and Players:GetPlayerFromCharacter(character)
		and state.Root.Parent
		and state.Root:CanSetNetworkOwnership()
	then
		state.Root:SetNetworkOwnershipAuto()
	end
	character:SetAttribute("ChargeUntil", 0)
end

local function ChargeDestination(character: Model, root: BasePart, targetRoot: BasePart): CFrame?
	local offset = targetRoot.Position - root.Position
	local horizontal = Vector3.new(offset.X, 0, offset.Z)
	local distance = horizontal.Magnitude
	if not (distance > 0.1 and distance <= Config.Charge.Range and math.abs(offset.Y) <= 5) then
		return nil
	end
	local aim = horizontal.Unit
	local position = targetRoot.Position - aim * math.min(distance, Config.Charge.ContactRange)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = CollectionService:GetTagged(Tags.Combatant)
	params.RespectCanCollide = true
	if Workspace:Raycast(root.Position, offset, params) then
		return nil
	end
	local ground = Workspace:Raycast(position + Vector3.yAxis * 5, -Vector3.yAxis * 12, params)
	if not ground or ground.Normal.Y < 0.65 then
		return nil
	end
	local groundY = ground.Position.Y
	local width = math.max(root.Size.X, 2)
	local depth = math.max(root.Size.Z, 2)
	for _, corner in
		{
			Vector3.new(-width * 0.5, 0, -depth * 0.5),
			Vector3.new(width * 0.5, 0, -depth * 0.5),
			Vector3.new(-width * 0.5, 0, depth * 0.5),
			Vector3.new(width * 0.5, 0, depth * 0.5),
		}
	do
		local support = Workspace:Raycast(position + corner + Vector3.yAxis * 5, -Vector3.yAxis * 12, params)
		if support then
			groundY = math.max(groundY, support.Position.Y)
		end
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
	local clearance = humanoid.HipHeight + root.Size.Y * 0.5
	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		local leg = character:FindFirstChild("Left Leg")
		clearance += if leg and leg:IsA("BasePart") then leg.Size.Y else 2
	end
	position = Vector3.new(position.X, groundY + clearance + 0.1, position.Z)
	if math.abs(position.Y - root.Position.Y) > 5 then
		return nil
	end
	local destination = CFrame.lookAt(position, position + aim)
	local height = clearance + root.Size.Y * 0.5 + 2
	local size = Vector3.new(width, height, depth)
	local bodyOffset = CFrame.new(0, height * 0.5 - clearance, 0)
	-- Sweep above the higher support surface to avoid treating a step down as a wall.
	local rise = Vector3.yAxis * math.max(0, position.Y - root.Position.Y)
	if rise.Magnitude > 0.01 and Workspace:Blockcast(root.CFrame * bodyOffset, size, rise, params) then
		return nil
	end
	local travel = Vector3.new(position.X - root.Position.X, 0, position.Z - root.Position.Z)
	if travel.Magnitude > 0.01 and Workspace:Blockcast(root.CFrame * bodyOffset + rise, size, travel, params) then
		return nil
	end
	-- Include other characters at the endpoint so teleporting cannot overlap a body.
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { character }
	overlap.RespectCanCollide = true
	if #Workspace:GetPartBoundsInBox(destination * bodyOffset, size, overlap) > 0 then
		return nil
	end
	return destination
end

function Skills.CastCharge(character: Model, requestedTarget: Instance, hit: Hit): boolean
	local now = Workspace:GetServerTimeNow()
	local root = Living(character)
	if
		not character
		or not root
		or root.Anchored
		or not CaptureAuthority.CanAttack(CaptureAuthority.Read(character), Workspace:GetServerTimeNow())
		or not character:FindFirstChild("Katana")
		or not Status.CanAct(character)
		or Status.Busy(character)
		or Status.Dashing(character)
		or typeof(requestedTarget) ~= "Instance"
		or not requestedTarget:IsA("Model")
		or not requestedTarget:IsDescendantOf(Workspace)
		or not Opponent(character, requestedTarget)
	then
		return false
	end
	if
		character:GetAttribute("DungeonDowned") == true
		or (character:GetAttribute("ChargeReadyAt") or 0) > now
		or (character:GetAttribute("AttackReadyAt") or 0) > now
		or Status.Rooted(character)
	then
		return false
	end
	local targetRoot = Living(requestedTarget)
	local destination = targetRoot and ChargeDestination(character, root, targetRoot)
	if not destination or not root:CanSetNetworkOwnership() then
		return false
	end
	if not Status.ConsumeStamina(character, Config.Charge.Stamina) then
		return false
	end
	Skills.Cancel(character)
	character:SetAttribute("ChargeReadyAt", now + Config.Charge.Cooldown)
	Status.SetSprinting(character, false)
	root:SetNetworkOwner(nil)
	local state: ChargeState = { Connection = nil, Root = root, ServerOwned = true }
	Charges[character] = state
	-- Move the root without assuming the model pivot is at the root's center.
	character:PivotTo(destination * root.CFrame:ToObjectSpace(character:GetPivot()))
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	character:SetAttribute("ChargeUntil", now + Config.Charge.Duration)
	if
		hit(character, requestedTarget, Config.Charge.Damage)
		and Living(requestedTarget)
		and requestedTarget:GetAttribute("CaptureActive") ~= false
		and requestedTarget:GetAttribute("DungeonDowned") ~= true
	then
		Status.ApplySlow(requestedTarget, Config.Charge.SlowRatio, Config.Charge.SlowDuration, "Charge")
	end
	state.Connection = RunService.Heartbeat:Connect(function()
		if
			Workspace:GetServerTimeNow() >= now + Config.Charge.Duration
			or not Living(character)
			or not CaptureAuthority.CanAttack(CaptureAuthority.Read(character), Workspace:GetServerTimeNow())
			or not character:FindFirstChild("Katana")
			or not Status.CanAct(character)
			or Status.Rooted(character)
		then
			EndCharge(character)
		end
	end)
	return true
end

function Skills.TrySpin(player: Player, hit: Hit): boolean
	return player.Character ~= nil and Skills.CastSpin(player.Character, hit)
end

function Skills.TryRisingCrash(player: Player, direction: Vector3, hit: Hit): boolean
	return player.Character ~= nil and Skills.CastRisingCrash(player.Character, direction, hit)
end

function Skills.TryGroundShock(player: Player, direction: Vector3, hit: Hit): boolean
	return player.Character ~= nil and Skills.CastGroundShock(player.Character, direction, hit)
end

function Skills.TryCharge(player: Player, target: Instance, hit: Hit): boolean
	local now = Workspace:GetServerTimeNow()
	if (ChargeRequests[player] or 0) > now then
		return false
	end
	ChargeRequests[player] = now + 0.15
	return player.Character ~= nil and Skills.CastCharge(player.Character, target, hit)
end

function Skills.Cancel(character: Model)
	EndSpin(character)
	EndCharge(character)
	EndDirectional(character)
end

return Skills

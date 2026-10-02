--!strict
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Authority = require(ReplicatedStorage.Shared.Capture.Authority)
local Rules = require(ReplicatedStorage.Shared.Capture.Rules)
local Config = require(ReplicatedStorage.Shared.Combat.Config)
local Tags = require(ReplicatedStorage.Shared.Core.Tags)
local Status = require(script.Parent.Parent.Combat.Status)
local Skills = require(script.Parent.Parent.Combat.Skills)
local Outcomes = require(script.Parent.Outcomes)

export type Occupancy = { [string]: { [number]: boolean } }
export type CombatApi = {
	RegisterCaptureBot: (CombatApi, Model) -> boolean,
	UnregisterCaptureBot: (CombatApi, Model) -> (),
	TryNPCAttack: (CombatApi, Model, Vector3) -> boolean,
	TryCaptureBotSkill: (CombatApi, Model, string, Vector3, Model?) -> boolean,
	SetCaptureBotLethalHandler: (CombatApi, ((Model) -> ())?) -> (),
}
type Actor = {
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Team: Rules.Team,
	Slot: number,
	Selected: boolean,
	RespawnAt: number,
	GuardUntil: number,
	GuardReadyAt: number,
	Route: { BasePart },
	Waypoint: number,
	Tracks: { [string]: AnimationTrack },
	ImpactAt: number,
}

local Bots = {}
local Actors: { Actor } = {}
local Combat: CombatApi?
local Arena: Model?
local Pool: Folder?
local Point: BasePart?
local Running = false
local ANCHOR_DISTANCE = 24
local TARGET_DISTANCE = 25
local GUARD_SECONDS = 0.4
local GUARD_COOLDOWN = 2.4

local function LoadTracks(actor: Actor)
	if next(actor.Tracks) then
		return
	end
	local animator = actor.Humanoid:FindFirstChildOfClass("Animator")
	assert(animator, "[Capture Bots] Author an Animator inside each Humanoid")
	local assets = ReplicatedStorage.Assets.CombatAnimations
	for _, name in { "Idle", "Walk", "Run", "Guard", "Impact", "Charge", "Spin", "RisingCrash", "GroundShock" } do
		local source = assets:FindFirstChild(name)
		assert(source and source:IsA("Animation"), "[Capture Bots] Missing animation " .. name)
		local track = animator:LoadAnimation(source)
		track.Priority = if name == "Idle"
			then Enum.AnimationPriority.Idle
			elseif name == "Walk" or name == "Run" then Enum.AnimationPriority.Movement
			else Enum.AnimationPriority.Action
		track.Looped = name == "Idle" or name == "Walk" or name == "Run" or name == "Guard"
		actor.Tracks[name] = track
	end
end

local function Animate(actor: Actor)
	local model = actor.Model
	local staggered = model:GetAttribute("StaggeredUntil") or 0
	if staggered > actor.ImpactAt and staggered > Workspace:GetServerTimeNow() then
		actor.ImpactAt = staggered
		actor.Tracks.Impact:Play(0.05)
	end
	local velocity = actor.Root.AssemblyLinearVelocity
	local moving = Vector2.new(velocity.X, velocity.Z).Magnitude > 1
	local selected = if moving then "Walk" else "Idle"
	for _, name in { "Idle", "Walk", "Run", "Guard" } do
		local wanted = if name == "Guard" then model:GetAttribute("Blocking") == true else name == selected
		local track = actor.Tracks[name]
		if wanted and not track.IsPlaying then
			track:Play(0.1)
		elseif not wanted and track.IsPlaying then
			track:Stop(0.1)
		end
	end
	if not Status.Busy(model) then
		for _, name in { "Charge", "Spin", "RisingCrash", "GroundShock" } do
			local track = actor.Tracks[name]
			if track.IsPlaying then
				track:Stop(0.1)
			end
		end
	end
end

local function Living(model: Model): BasePart?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	return if model:IsDescendantOf(Workspace)
			and humanoid
			and humanoid.Health > 0
			and root
			and root:IsA("BasePart")
		then root
		else nil
end

local function Route(team: Rules.Team, slot: number): { BasePart }
	local arena = Arena
	local routes = arena and arena:FindFirstChild("Routes")
	local teamRoutes = routes and routes:FindFirstChild(team)
	local lane = ({ "Center", "Left", "Right" })[(slot - 1) % 3 + 1]
	local folder = teamRoutes and teamRoutes:FindFirstChild(lane)
	local route: { BasePart } = {}
	if folder then
		for _, instance in folder:GetChildren() do
			if instance:IsA("BasePart") and tonumber(instance.Name) then
				table.insert(route, instance)
			end
		end
		table.sort(route, function(first, second)
			return (tonumber(first.Name) or 0) < (tonumber(second.Name) or 0)
		end)
	end
	return route
end

local function Stop(actor: Actor)
	actor.Model:SetAttribute("CaptureActive", false)
	if Combat then
		Combat:UnregisterCaptureBot(actor.Model)
	end
	Status.CancelDash(actor.Model)
	Skills.Cancel(actor.Model)
	Status.ClearEffects(actor.Model)
	Status.SetBlocking(actor.Model, false)
	Status.SetSprinting(actor.Model, false)
	actor.Humanoid:Move(Vector3.zero)
	actor.Root.AssemblyLinearVelocity = Vector3.zero
	actor.Root.AssemblyAngularVelocity = Vector3.zero
	actor.Root.Anchored = true
	actor.Model.Parent = Pool
	Outcomes.Clear(actor.Model)
	actor.Model:SetAttribute("CaptureBotState", "Pooled")
	for _, track in actor.Tracks do
		track:Stop(0)
	end
end

local function Spawn(actor: Actor, now: number)
	local arena, combat = Arena, Combat
	if not arena or not combat then
		return
	end
	local spawns = arena:FindFirstChild("Spawns")
	local teamSpawns = spawns and spawns:FindFirstChild(actor.Team)
	local destination = teamSpawns and teamSpawns:FindFirstChild(tostring(actor.Slot))
	assert(destination and destination:IsA("BasePart"), "[Capture Bots] Missing authored team spawn")
	actor.Root.Anchored = false
	actor.Model.Parent = arena
	actor.Model:PivotTo(destination.CFrame)
	actor.Humanoid.Health = actor.Humanoid.MaxHealth
	actor.Humanoid:ChangeState(Enum.HumanoidStateType.Running)
	actor.Model:SetAttribute("CaptureTeam", actor.Team)
	actor.Model:SetAttribute("CaptureSlot", actor.Slot)
	actor.Model:SetAttribute("CaptureActive", true)
	actor.Model:SetAttribute("CaptureProtectedUntil", now + Rules.ProtectionSeconds)
	actor.Model:SetAttribute("CaptureRespawnAt", 0)
	actor.Model:SetAttribute("CaptureBotState", "Regroup")
	actor.Route = Route(actor.Team, actor.Slot)
	actor.Waypoint = 1
	actor.RespawnAt = 0
	actor.GuardUntil = 0
	actor.GuardReadyAt = now + actor.Slot * 0.2
	assert(combat:RegisterCaptureBot(actor.Model), "[Capture Bots] Rig could not register: " .. actor.Model.Name)
	LoadTracks(actor)
	actor.ImpactAt = 0
	Status.OwnNPC(actor.Model)
end

function Bots.Defeat(character: Model)
	if not Running then
		return
	end
	for _, actor in Actors do
		if actor.Model ~= character or not actor.Selected or actor.RespawnAt > 0 then
			continue
		end
		local now = Workspace:GetServerTimeNow()
		Outcomes.Finish(character, now)
		Stop(actor)
		actor.Humanoid.Health = 1
		actor.RespawnAt = now + Rules.RespawnSeconds
		character:SetAttribute("CaptureRespawnAt", actor.RespawnAt)
		character:SetAttribute("CaptureBotState", "Respawning")
		return
	end
end

function Bots.Configure(combat: CombatApi)
	Combat = combat
	combat:SetCaptureBotLethalHandler(Bots.Defeat)
end

function Bots.Enabled(): boolean
	return RunService:IsStudio() and Arena ~= nil and Arena:GetAttribute("PracticeBotsEnabled") == true
end

function Bots.Init(arena: Model)
	Arena = arena
	Point = arena:FindFirstChild("Point") :: BasePart
	if not Bots.Enabled() then
		return
	end
	local pool = ServerStorage:FindFirstChild("CaptureBotPool")
	assert(
		pool and pool:IsA("Folder"),
		"[Capture Bots] Author ServerStorage.CaptureBotPool before enabling practice bots"
	)
	Pool = pool
	for _, team: Rules.Team in { "Azure", "Coral" } do
		for slot = 1, Rules.Capacity do
			local model = pool:FindFirstChild(team .. slot)
			assert(model and model:IsA("Model"), "[Capture Bots] Missing authored rig " .. team .. slot)
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			local root = model:FindFirstChild("HumanoidRootPart")
			assert(humanoid and root and root:IsA("BasePart"), "[Capture Bots] Rig requires Humanoid and root")
			humanoid.BreakJointsOnDeath = false
			if humanoid.DisplayName == "" then
				humanoid.DisplayName = team .. " AI " .. slot
			end
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
			model:SetAttribute("CaptureBot", true)
			model:SetAttribute("CaptureTeam", team)
			model:SetAttribute("CaptureActive", false)
			local actor: Actor = {
				Model = model,
				Humanoid = humanoid,
				Root = root,
				Team = team,
				Slot = slot,
				Selected = false,
				RespawnAt = 0,
				GuardUntil = 0,
				GuardReadyAt = 0,
				Route = {},
				Waypoint = 1,
				Tracks = {},
				ImpactAt = 0,
			}
			table.insert(Actors, actor)
			Stop(actor)
		end
	end
end

function Bots.Sync(occupied: Occupancy, now: number)
	if not Bots.Enabled() or not Running then
		return
	end
	local arena = Arena :: Model
	local count = arena:GetAttribute("BotsPerTeam")
	local extra = if typeof(count) == "number" and count == count then math.clamp(math.floor(count), 1, 4) else 2
	local humans: { [string]: number } = { Azure = 0, Coral = 0 }
	for team, slots in occupied do
		for _ in slots do
			humans[team] += 1
		end
	end
	local target = math.min(Rules.Capacity, math.max(humans.Azure, humans.Coral) + extra)
	local selected: { [string]: number } = { Azure = 0, Coral = 0 }
	for _, actor in Actors do
		local teamSlots = occupied[actor.Team]
		local desired = not teamSlots[actor.Slot] and selected[actor.Team] < target - humans[actor.Team]
		if desired then
			selected[actor.Team] += 1
		end
		if desired and not actor.Selected then
			actor.Selected = true
			Spawn(actor, now)
		elseif not desired and actor.Selected then
			actor.Selected = false
			actor.RespawnAt = 0
			Stop(actor)
		end
	end
end

function Bots.Begin(occupied: Occupancy, now: number)
	Bots.Stop()
	Running = Bots.Enabled()
	Bots.Sync(occupied, now)
end

function Bots.Stop()
	Running = false
	for _, actor in Actors do
		actor.Selected = false
		actor.RespawnAt = 0
		Stop(actor)
	end
end

local function Visible(actor: Actor, target: BasePart): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = CollectionService:GetTagged(Tags.Combatant)
	params.RespectCanCollide = true
	return Workspace:Raycast(actor.Root.Position, target.Position - actor.Root.Position, params) == nil
end

local function Enemy(actor: Actor, now: number): (Model?, BasePart?)
	local nearest, nearestRoot, distance = nil, nil, TARGET_DISTANCE
	for _, instance in CollectionService:GetTagged(Tags.Combatant) do
		if not instance:IsA("Model") or instance == actor.Model then
			continue
		end
		local root = Living(instance)
		if root and Authority.CanHit(Authority.Read(actor.Model), Authority.Read(instance), now) then
			local offset = root.Position - actor.Root.Position
			if offset.Magnitude < distance and Visible(actor, root) then
				nearest, nearestRoot, distance = instance, root, offset.Magnitude
			end
		end
	end
	return nearest, nearestRoot
end

local function NearbyEnemies(actor: Actor, now: number): number
	local count = 0
	for _, instance in CollectionService:GetTagged(Tags.Combatant) do
		if instance:IsA("Model") then
			local root = Living(instance)
			if
				root
				and (root.Position - actor.Root.Position).Magnitude <= Config.Spin.Radius
				and Authority.CanHit(Authority.Read(actor.Model), Authority.Read(instance), now)
			then
				count += 1
			end
		end
	end
	return count
end

local function Fight(actor: Actor, target: Model, targetRoot: BasePart, now: number): boolean
	local combat = Combat
	if not combat then
		return false
	end
	local offset = targetRoot.Position - actor.Root.Position
	local flat = Vector3.new(offset.X, 0, offset.Z)
	if flat.Magnitude <= 0.01 then
		return false
	end
	local aim = flat.Unit
	if now < actor.GuardUntil then
		actor.Root.CFrame = CFrame.lookAt(actor.Root.Position, actor.Root.Position + aim)
		actor.Humanoid:Move(Vector3.zero)
		return true
	end
	Status.SetBlocking(actor.Model, false)
	if not Status.CanAct(actor.Model) or Status.Busy(actor.Model) then
		return true
	end
	actor.Root.CFrame = CFrame.lookAt(actor.Root.Position, actor.Root.Position + aim)
	local attacking = (target:GetAttribute("RisingCrashUntil") or 0) > now
		or (target:GetAttribute("GroundShockUntil") or 0) > now
		or (target:GetAttribute("AttackReadyAt") or 0)
				- Config.Attack.Cooldown
				+ Config.Attack.Windup
				+ Config.Attack.Active
			> now
	if
		flat.Magnitude <= 6
		and attacking
		and now >= actor.GuardReadyAt
		and (actor.Model:GetAttribute("Stamina") or 0) >= 30
	then
		actor.GuardUntil = now + GUARD_SECONDS
		actor.GuardReadyAt = now + GUARD_COOLDOWN
		Status.SetBlocking(actor.Model, true)
		actor.Humanoid:Move(Vector3.zero)
		return true
	end
	local candidates = {}
	if flat.Magnitude > 8 and flat.Magnitude <= Config.Charge.Range then
		table.insert(candidates, "Charge")
	end
	if NearbyEnemies(actor, now) >= 2 then
		table.insert(candidates, "Spin")
	end
	if flat.Magnitude <= Config.RisingCrash.Range and (target:GetAttribute("ExposedUntil") or 0) <= now then
		table.insert(candidates, "RisingCrash")
	end
	if flat.Magnitude <= Config.GroundShock.Range then
		table.insert(candidates, "GroundShock")
	end
	for _, skill in candidates do
		if
			(actor.Model:GetAttribute(skill .. "ReadyAt") or 0) <= now
			and combat:TryCaptureBotSkill(actor.Model, skill, aim, target)
		then
			actor.Tracks[skill]:Play(0.05)
			actor.Humanoid:Move(Vector3.zero)
			return true
		end
	end
	if flat.Magnitude <= 3.5 then
		actor.Humanoid:Move(Vector3.zero)
		combat:TryNPCAttack(actor.Model, aim)
		return true
	end
	return false
end

function Bots.Step(now: number, owner: string)
	if not Running then
		return
	end
	local point = Point :: BasePart
	for _, actor in Actors do
		if not actor.Selected then
			continue
		end
		if actor.RespawnAt > 0 then
			if now >= actor.RespawnAt then
				Spawn(actor, now)
			end
			continue
		end
		Animate(actor)
		if not Authority.CanAttack(Authority.Read(actor.Model), now) then
			actor.Humanoid:Move(Vector3.zero)
			continue
		end
		if not Status.CanAct(actor.Model) and actor.Model:GetAttribute("Blocking") ~= true then
			actor.Humanoid:Move(Vector3.zero)
			continue
		end
		local target, targetRoot = Enemy(actor, now)
		local pointOffset = actor.Root.Position - point.Position
		local onApproach = Vector3.new(pointOffset.X, 0, pointOffset.Z).Magnitude > ANCHOR_DISTANCE
		if target and targetRoot and not onApproach then
			actor.Model:SetAttribute("CaptureBotState", "Fight")
			if Fight(actor, target, targetRoot, now) then
				continue
			end
			actor.Humanoid:MoveTo(targetRoot.Position)
			continue
		end
		Status.SetBlocking(actor.Model, false)
		if Status.Busy(actor.Model) then
			actor.Humanoid:Move(Vector3.zero)
			continue
		end
		local waypoint = actor.Route[actor.Waypoint]
		if waypoint and (waypoint.Position - actor.Root.Position).Magnitude <= 4 then
			actor.Waypoint += 1
			waypoint = actor.Route[actor.Waypoint]
		end
		actor.Model:SetAttribute(
			"CaptureBotState",
			if waypoint then "Regroup" else if owner == actor.Team then "Defend" else "Capture"
		)
		local angle = (actor.Slot - 1) * math.pi * 2 / Rules.Capacity
		local destination = if waypoint
			then waypoint.Position
			else point.Position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * 5
		if (destination - actor.Root.Position).Magnitude > 2 then
			actor.Humanoid:MoveTo(destination)
		else
			actor.Humanoid:Move(Vector3.zero)
		end
	end
end

function Bots.Counts(): (number, number)
	local azure, coral = 0, 0
	for _, actor in Actors do
		if actor.Selected then
			if actor.Team == "Azure" then
				azure += 1
			else
				coral += 1
			end
		end
	end
	return azure, coral
end

function Bots.Publish(state: Folder)
	for _, actor in Actors do
		local prefix = actor.Team .. "Bot" .. actor.Slot
		local values = {
			Name = if actor.Selected
				then (if actor.Humanoid.DisplayName ~= "" then actor.Humanoid.DisplayName else actor.Model.Name)
				else "",
			RespawnAt = if actor.Selected then actor.RespawnAt else 0,
			Health = if actor.Selected and actor.RespawnAt == 0 then actor.Humanoid.Health else 0,
			MaxHealth = actor.Humanoid.MaxHealth,
		}
		for key, value in values do
			if state:GetAttribute(prefix .. key) ~= value then
				state:SetAttribute(prefix .. key, value)
			end
		end
	end
end

function Bots.PointCounts(now: number): (number, number)
	local azure, coral = 0, 0
	local point = Point
	if not Running or not point then
		return azure, coral
	end
	for _, actor in Actors do
		if not actor.Selected or actor.RespawnAt > 0 or not Authority.CanAttack(Authority.Read(actor.Model), now) then
			continue
		end
		local offset = actor.Root.Position - point.Position
		if math.abs(offset.Y) <= Rules.Height and Vector2.new(offset.X, offset.Z).Magnitude <= Rules.Radius then
			if actor.Team == "Azure" then
				azure += 1
			else
				coral += 1
			end
		end
	end
	return azure, coral
end

return Bots

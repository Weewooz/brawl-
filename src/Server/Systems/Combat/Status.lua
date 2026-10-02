--!strict
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Combat.Config)
local Server = require(ReplicatedStorage.Shared.Network.Server)
local Tags = require(ReplicatedStorage.Shared.Core.Tags)
local Knockback = require(ReplicatedStorage.Shared.Utilities.Knockback)

export type Kind = "Stun" | "Stagger" | "ControlDisabled" | "Confuse"
export type StaggerLevel = "Weak" | "Strong"

type State = {
	Humanoid: Humanoid,
	Speed: number,
	JumpPower: number,
	JumpHeight: number,
	AutoRotate: boolean,
	Stamina: number,
	Grit: number,
	RegenAt: number,
	Destroying: RBXScriptConnection?,
	Added: RBXScriptConnection?,
	Capture: RBXScriptConnection?,
	Slows: { [string]: { Until: number, Ratio: number } },
}

type Push = {
	Root: BasePart,
	Direction: Vector3,
	Distance: number,
	Duration: number,
	StartedAt: number,
	Moved: number,
}

local Status = {}
local States: { [Model]: State } = {}
local Pushes: { [Model]: Push } = {}
local Elapsed = 0
local STEP = 0.1
local KNOCKBACK_DURATION = 0.16
local COMBATANT_GROUP = "Combatant"
local GHOST_GROUP = "CombatGhost"

for _, group in { COMBATANT_GROUP, GHOST_GROUP } do
	pcall(function()
		PhysicsService:RegisterCollisionGroup(group)
	end)
end
PhysicsService:CollisionGroupSetCollidable(COMBATANT_GROUP, COMBATANT_GROUP, true)
PhysicsService:CollisionGroupSetCollidable(GHOST_GROUP, COMBATANT_GROUP, false)
PhysicsService:CollisionGroupSetCollidable(GHOST_GROUP, GHOST_GROUP, false)

local ATTRIBUTES = {
	Stun = "StunnedUntil",
	Stagger = "StaggeredUntil",
	ControlDisabled = "ControlDisabledUntil",
	Confuse = "ConfusedUntil",
}

local function Active(model: Model, attribute: string): boolean
	local untilAt = model:GetAttribute(attribute)
	return typeof(untilAt) == "number" and untilAt > Workspace:GetServerTimeNow()
end

local function Refresh(model: Model)
	local state = States[model]
	if not state or state.Humanoid.Health <= 0 then
		return
	end

	local staggered = Active(model, ATTRIBUTES.Stagger)
	local rooted = Active(model, "RootedUntil")
	local spinning = Active(model, "SpinUntil")
	local player = Players:GetPlayerFromCharacter(model)
	local locked = model:GetAttribute("DungeonDowned") == true
		or Pushes[model] ~= nil
		or Active(model, ATTRIBUTES.Stun)
		or Active(model, ATTRIBUTES.ControlDisabled)
		or rooted
		or (staggered and (not player or model:GetAttribute("StaggerLevel") == "Strong"))
	local sprinting = model:GetAttribute("Sprinting") == true
	local blocking = model:GetAttribute("Blocking") == true
	local drawing = (model:GetAttribute("BowDrawStartedAt") or 0) > 0
	local speed = if locked
		then 0
		else if staggered
			then math.min(state.Speed, Config.Stagger.WeakWalkSpeed)
			else if spinning
				then math.min(state.Speed, Config.Spin.WalkSpeed)
				else if blocking
					then math.min(state.Speed, Config.BlockWalkSpeed)
					else if drawing
						then math.min(state.Speed, 10)
						else if sprinting then Config.SprintSpeed else state.Speed
	local slow = model:GetAttribute("SlowRatio")
	state.Humanoid.WalkSpeed = if Active(model, "SlowUntil") and typeof(slow) == "number"
		then speed * math.clamp(slow, 0, 1)
		else speed
	state.Humanoid.JumpPower = if locked then 0 else state.JumpPower
	state.Humanoid.JumpHeight = if locked then 0 else state.JumpHeight
end

local function SetCollisionGroup(model: Model, group: string)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = group
		end
	end
end

local function CollisionGroup(model: Model): string
	return if model:GetAttribute("CaptureActive") ~= nil or Active(model, "SpinUntil")
		then GHOST_GROUP
		else COMBATANT_GROUP
end

local function SetStamina(model: Model, state: State, amount: number)
	state.Stamina = math.clamp(amount, 0, Config.Stamina.Max)
	model:SetAttribute("Stamina", math.round(state.Stamina * 10) / 10)
end

function Status.Attach(model: Model): boolean
	if States[model] then
		return true
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end

	CollectionService:AddTag(model, Tags.Combatant)
	local state: State = {
		Humanoid = humanoid,
		Speed = humanoid.WalkSpeed,
		JumpPower = humanoid.JumpPower,
		JumpHeight = humanoid.JumpHeight,
		AutoRotate = humanoid.AutoRotate,
		Stamina = Config.Stamina.Max,
		Grit = 0,
		RegenAt = 0,
		Destroying = nil,
		Added = nil,
		Capture = nil,
		Slows = {},
	}
	SetCollisionGroup(model, CollisionGroup(model))
	state.Capture = model:GetAttributeChangedSignal("CaptureActive"):Connect(function()
		SetCollisionGroup(model, CollisionGroup(model))
	end)
	state.Added = model.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = CollisionGroup(model)
		end
	end)
	state.Destroying = model.Destroying:Connect(function()
		Pushes[model] = nil
		if state.Added then
			state.Added:Disconnect()
		end
		if state.Capture then
			state.Capture:Disconnect()
		end
		if state.Destroying then
			state.Destroying:Disconnect()
		end
		States[model] = nil
	end)
	States[model] = state
	model:SetAttribute("Sprinting", false)
	model:SetAttribute("Blocking", model:GetAttribute("Blocking") == true)
	model:SetAttribute("Stamina", Config.Stamina.Max)
	model:SetAttribute("Grit", 0)
	model:SetAttribute("StunnedUntil", 0)
	model:SetAttribute("StaggeredUntil", 0)
	model:SetAttribute("StaggerLevel", "Weak")
	model:SetAttribute("ControlDisabledUntil", 0)
	model:SetAttribute("ConfusedUntil", 0)
	model:SetAttribute("DashingUntil", 0)
	model:SetAttribute("RootedUntil", 0)
	model:SetAttribute("SpinUntil", 0)
	model:SetAttribute("ChargeUntil", 0)
	model:SetAttribute("RisingCrashUntil", 0)
	model:SetAttribute("GroundShockUntil", 0)
	model:SetAttribute("ExposedUntil", 0)
	model:SetAttribute("SlowUntil", 0)
	model:SetAttribute("SlowRatio", 1)
	model:SetAttribute("PerfectGuardUntil", 0)
	model:SetAttribute("PerfectGuardReadyAt", 0)
	model:SetAttribute("LastPerfectGuardAt", 0)
	model:SetAttribute("ActionRecoveryUntil", 0)
	Refresh(model)
	return true
end

function Status.Active(model: Model, kind: Kind): boolean
	return Active(model, ATTRIBUTES[kind])
end

function Status.OwnNPC(model: Model)
	if Players:GetPlayerFromCharacter(model) then
		return
	end
	local assemblies: { [BasePart]: boolean } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			local root = descendant.AssemblyRootPart or descendant
			if not assemblies[root] and not root.Anchored and root:CanSetNetworkOwnership() then
				assemblies[root] = true
				root:SetNetworkOwner(nil)
			end
		end
	end
end

function Status.CanAct(model: Model): boolean
	local state = States[model]
	return state ~= nil
		and model:GetAttribute("CaptureActive") ~= false
		and state.Humanoid.Health > 0
		and not Status.Active(model, "Stun")
		and not Status.Active(model, "Stagger")
		and not Status.Active(model, "ControlDisabled")
		and not Active(model, "ActionRecoveryUntil")
		and model:GetAttribute("Blocking") ~= true
end

function Status.Busy(model: Model): boolean
	return Active(model, "SpinUntil")
		or Active(model, "ChargeUntil")
		or Active(model, "RisingCrashUntil")
		or Active(model, "GroundShockUntil")
end

local function RefreshSlows(model: Model, state: State, now: number)
	local ratio, untilAt = 1, 0
	for source, effect in state.Slows do
		if effect.Until <= now then
			state.Slows[source] = nil
		else
			ratio = math.min(ratio, effect.Ratio)
			untilAt = math.max(untilAt, effect.Until)
		end
	end
	if model:GetAttribute("SlowUntil") ~= untilAt or model:GetAttribute("SlowRatio") ~= ratio then
		model:SetAttribute("SlowUntil", untilAt)
		model:SetAttribute("SlowRatio", ratio)
		Refresh(model)
	end
end

function Status.ApplySlow(model: Model, ratio: number, duration: number, source: string): boolean
	if ratio ~= ratio or ratio <= 0 or ratio > 1 or duration ~= duration or duration <= 0 or duration == math.huge then
		return false
	end
	if not Status.Attach(model) then
		return false
	end
	local state = States[model]
	local now = Workspace:GetServerTimeNow()
	state.Slows[source] = { Until = now + math.min(duration, 30), Ratio = ratio }
	RefreshSlows(model, state, now)
	return true
end

function Status.ApplyExposed(model: Model, duration: number): boolean
	if duration ~= duration or duration <= 0 or duration == math.huge or not Status.Attach(model) then
		return false
	end
	model:SetAttribute("ExposedUntil", Workspace:GetServerTimeNow() + math.min(duration, 30))
	return true
end

local function EndPush(model: Model)
	local push = Pushes[model]
	if not push then
		return
	end
	Pushes[model] = nil
	local root = push.Root
	if root.Parent then
		root.AssemblyLinearVelocity = Vector3.yAxis * root.AssemblyLinearVelocity.Y
		if Players:GetPlayerFromCharacter(model) and root:CanSetNetworkOwnership() then
			root:SetNetworkOwnershipAuto()
		end
	end
	Refresh(model)
end

function Status.ClearEffects(model: Model)
	EndPush(model)
	local state = States[model]
	if state then
		table.clear(state.Slows)
	end
	model:SetAttribute("SlowUntil", 0)
	model:SetAttribute("SlowRatio", 1)
	model:SetAttribute("ExposedUntil", 0)
	model:SetAttribute("PerfectGuardUntil", 0)
	model:SetAttribute("ActionRecoveryUntil", 0)
	Refresh(model)
end

function Status.Reset(model: Model): boolean
	local state = States[model]
	if not state then
		return false
	end
	Status.ClearEffects(model)
	Status.CancelDash(model)
	for _, attribute in ATTRIBUTES do
		model:SetAttribute(attribute, 0)
	end
	model:SetAttribute("RootedUntil", 0)
	model:SetAttribute("Blocking", false)
	model:SetAttribute("Sprinting", false)
	model:SetAttribute("PerfectGuardReadyAt", 0)
	model:SetAttribute("CaptureResolveUntil", 0)
	model:SetAttribute("LastPerfectGuardAt", 0)
	SetStamina(model, state, Config.Stamina.Max)
	state.RegenAt = 0
	Refresh(model)
	return true
end

function Status.ApplyPush(model: Model, direction: Vector3, distance: number, duration: number): boolean
	local state = States[model]
	local root = model:FindFirstChild("HumanoidRootPart")
	if not state or state.Humanoid.Health <= 0 or not root or not root:IsA("BasePart") or root.Anchored then
		return false
	end
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.01 or flat.Magnitude ~= flat.Magnitude or distance <= 0 or duration <= 0 then
		return false
	end
	if Pushes[model] or not root:CanSetNetworkOwnership() then
		return false
	end
	local aim = flat.Unit
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = CollectionService:GetTagged(Tags.Combatant)
	params.RespectCanCollide = true
	local castParams = RaycastParams.new()
	castParams.FilterType = Enum.RaycastFilterType.Exclude
	castParams.FilterDescendantsInstances = { model }
	castParams.RespectCanCollide = true
	local length = math.min(distance, Config.GroundShock.PushDistance)
	local obstruction = Workspace:Blockcast(root.CFrame, root.Size + Vector3.new(0.2, 2, 0.2), aim * length, castParams)
	if obstruction then
		length = math.max(0, obstruction.Distance - 0.2)
	end
	local floor = Workspace:Raycast(root.Position, -Vector3.yAxis * 8, params)
	if not floor then
		return false
	end
	for _, fraction in { 0.5, 1 } do
		local support = Workspace:Raycast(root.Position + aim * length * fraction, -Vector3.yAxis * 8, params)
		if not support or support.Normal.Y < 0.65 or math.abs(support.Position.Y - floor.Position.Y) > 1 then
			return false
		end
	end
	if length <= 0.05 then
		return false
	end
	Status.CancelDash(model)
	Status.ApplyStagger(model, "Weak", duration, aim, 0)
	local previous = root:FindFirstChild("StaggerVelocity")
	if previous and previous:IsA("LinearVelocity") then
		previous.Enabled = false
	end
	root:SetNetworkOwner(nil)
	root.AssemblyLinearVelocity = Vector3.yAxis * root.AssemblyLinearVelocity.Y
	root.AssemblyAngularVelocity = Vector3.zero
	Pushes[model] = {
		Root = root,
		Direction = aim,
		Distance = length,
		Duration = duration,
		StartedAt = Workspace:GetServerTimeNow(),
		Moved = 0,
	}
	Refresh(model)
	return true
end

local function StepPushes(now: number)
	for model, push in Pushes do
		local root = push.Root
		if
			not root.Parent
			or root.Anchored
			or not States[model]
			or States[model].Humanoid.Health <= 0
			or Status.Dashing(model)
			or model:GetAttribute("CaptureActive") == false
			or model:GetAttribute("DungeonDowned") == true
		then
			EndPush(model)
			continue
		end
		local moved = push.Distance * math.clamp((now - push.StartedAt) / push.Duration, 0, 1)
		local travel = push.Direction * (moved - push.Moved)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { model }
		params.RespectCanCollide = true
		if
			travel.Magnitude > 0.001
			and Workspace:Blockcast(root.CFrame, root.Size + Vector3.new(0.2, 2, 0.2), travel, params)
		then
			EndPush(model)
			continue
		end
		root.CFrame += travel
		root.AssemblyLinearVelocity = Vector3.yAxis * root.AssemblyLinearVelocity.Y
		root.AssemblyAngularVelocity = Vector3.zero
		push.Moved = moved
		if moved >= push.Distance then
			EndPush(model)
		end
	end
end

function Status.Rooted(model: Model): boolean
	return Active(model, "RootedUntil")
end

function Status.Dashing(model: Model): boolean
	return Active(model, "DashingUntil")
end

function Status.SetSpin(model: Model, untilAt: number)
	local state = States[model]
	if not state then
		return
	end
	model:SetAttribute("SpinUntil", untilAt)
	if untilAt > Workspace:GetServerTimeNow() then
		model:SetAttribute("Sprinting", false)
		model:SetAttribute("Blocking", false)
	end
	SetCollisionGroup(model, CollisionGroup(model))
	state.Humanoid.AutoRotate = if untilAt > Workspace:GetServerTimeNow() then false else state.AutoRotate
	Refresh(model)
end

function Status.ApplyRoot(model: Model, duration: number): boolean
	if duration <= 0 or duration ~= duration or not Status.Attach(model) then
		return false
	end
	local now = Workspace:GetServerTimeNow()
	local current = model:GetAttribute("RootedUntil")
	local untilAt = math.max(if typeof(current) == "number" then current else 0, now + duration)
	Status.CancelDash(model)
	model:SetAttribute("RootedUntil", untilAt)
	model:SetAttribute("Sprinting", false)
	Refresh(model)
	task.delay(untilAt - now, function()
		if States[model] then
			Refresh(model)
		end
	end)
	return true
end

function Status.SetGrit(model: Model, value: number): boolean
	local state = States[model]
	if not state or typeof(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
		return false
	end
	state.Grit = math.clamp(value, 0, Config.Stagger.GritMax)
	model:SetAttribute("Grit", state.Grit)
	return true
end

function Status.ImpactRatio(model: Model, damage: number): number
	local state = States[model]
	if not state or typeof(damage) ~= "number" or damage ~= damage or damage <= 0 or math.abs(damage) == math.huge then
		return 1
	end
	return damage / (damage + state.Grit * Config.Stagger.GritWeight)
end

function Status.CancelDash(model: Model): boolean
	local root = model:FindFirstChild("HumanoidRootPart")
	if not Active(model, "DashingUntil") and not (root and root:FindFirstChild("DashVelocity")) then
		return false
	end
	Knockback.CancelDash(model)
	model:SetAttribute("DashingUntil", 0)
	return true
end

function Status.ApplyStagger(
	model: Model,
	level: StaggerLevel,
	duration: number,
	direction: Vector3?,
	knockback: number?,
	impactDamage: number?
): boolean
	if level ~= "Weak" and level ~= "Strong" then
		return false
	end
	if duration ~= duration or duration <= 0 or duration == math.huge or not Status.Attach(model) then
		return false
	end
	local ratio = Status.ImpactRatio(model, impactDamage or Config.Attack.Damage)
	if level == "Strong" and ratio <= Config.Stagger.StrongDowngradeRatio then
		level = "Weak"
	end
	local now = Workspace:GetServerTimeNow()
	local current = model:GetAttribute("StaggeredUntil")
	-- Weak hits cannot continually reset recovery during a team pile-on.
	if level == "Weak" and model:GetAttribute("CaptureActive") == true then
		if (model:GetAttribute("CaptureResolveUntil") or 0) > now then
			return false
		end
		model:SetAttribute("CaptureResolveUntil", now + math.min(duration * ratio, 30) + 0.45)
	end
	local active = typeof(current) == "number" and current > now
	local currentLevel = model:GetAttribute("StaggerLevel")
	local appliedLevel = if active and currentLevel == "Strong" then "Strong" else level
	local untilAt = math.max(if active then current else 0, now + math.min(duration * ratio, 30))
	Status.CancelDash(model)
	model:SetAttribute("StaggerLevel", appliedLevel)
	model:SetAttribute("StaggeredUntil", untilAt)
	model:SetAttribute("Sprinting", false)
	local root = model:FindFirstChild("HumanoidRootPart")
	local player = Players:GetPlayerFromCharacter(model)
	if player then
		model:SetAttribute("Blocking", false)
	else
		Status.OwnNPC(model)
		local state = States[model]
		if state then
			state.Humanoid:Move(Vector3.zero)
		end
	end
	if root and root:IsA("BasePart") then
		local impulseDirection = direction or -root.CFrame.LookVector
		local horizontal = Vector3.new(impulseDirection.X, 0, impulseDirection.Z)
		if horizontal.Magnitude > 0.01 then
			local velocityChange = (
				knockback or (if level == "Strong" then Config.Stagger.StrongKnockback else Config.Attack.Knockback)
			) * ratio
			if player then
				Server.Combat.Knockback.Fire(player, Knockback.VelocityChange(horizontal.Unit, velocityChange))
			else
				Knockback.ApplySustained(
					model,
					horizontal.Unit * velocityChange,
					math.min(untilAt - now, KNOCKBACK_DURATION)
				)
			end
		end
	end
	Refresh(model)
	task.delay(untilAt - now, function()
		if States[model] then
			Refresh(model)
		end
	end)
	return true
end

function Status.Apply(model: Model, kind: Kind, duration: number): boolean
	if kind == "Stagger" then
		return Status.ApplyStagger(model, "Weak", duration)
	end
	if duration ~= duration or duration <= 0 or duration == math.huge or not Status.Attach(model) then
		return false
	end
	local attribute = ATTRIBUTES[kind]
	local now = Workspace:GetServerTimeNow()
	local current = model:GetAttribute(attribute)
	local untilAt = math.max(if typeof(current) == "number" then current else 0, now + math.min(duration, 30))
	model:SetAttribute(attribute, untilAt)
	if kind ~= "Confuse" then
		model:SetAttribute("Sprinting", false)
		if Players:GetPlayerFromCharacter(model) then
			model:SetAttribute("Blocking", false)
		end
	end
	Refresh(model)
	task.delay(untilAt - now, function()
		if States[model] then
			Refresh(model)
		end
	end)
	return true
end

function Status.SetSprinting(model: Model, enabled: boolean): boolean
	if not States[model] then
		return false
	end
	if enabled and (not Status.CanAct(model) or Status.Busy(model) or States[model].Stamina <= 0) then
		return false
	end
	model:SetAttribute("Sprinting", enabled)
	Refresh(model)
	return true
end

function Status.SetBlocking(model: Model, enabled: boolean): boolean
	local state = States[model]
	if not state then
		return false
	end
	if model:GetAttribute("Blocking") == enabled then
		return true
	end
	if enabled and (not Status.CanAct(model) or Status.Busy(model) or state.Stamina <= 0) then
		return false
	end
	model:SetAttribute("Blocking", enabled)
	if enabled then
		model:SetAttribute("Sprinting", false)
		local now = Workspace:GetServerTimeNow()
		local readyAt = model:GetAttribute("PerfectGuardReadyAt") or 0
		if now >= readyAt then
			model:SetAttribute("PerfectGuardUntil", now + Config.PerfectGuard.Window)
			model:SetAttribute("PerfectGuardReadyAt", now + Config.PerfectGuard.Rearm)
		end
	else
		model:SetAttribute("PerfectGuardUntil", 0)
	end
	Refresh(model)
	return true
end

function Status.ConsumeStamina(model: Model, amount: number): boolean
	local state = States[model]
	if not state or amount <= 0 or state.Stamina < amount then
		return false
	end
	SetStamina(model, state, state.Stamina - amount)
	state.RegenAt = Workspace:GetServerTimeNow() + Config.Stamina.RegenDelay
	return true
end

function Status.TryPerfectGuard(model: Model): boolean
	local now = Workspace:GetServerTimeNow()
	if model:GetAttribute("Blocking") ~= true or not Active(model, "PerfectGuardUntil") then
		return false
	end
	if not Status.ConsumeStamina(model, Config.Stamina.BlockHit * Config.PerfectGuard.StaminaRatio) then
		return false
	end
	model:SetAttribute("PerfectGuardUntil", 0)
	model:SetAttribute("LastPerfectGuardAt", now)
	return true
end

function Status.BlockHit(model: Model, direction: Vector3?, damage: number?): boolean
	if Status.ConsumeStamina(model, Config.Stamina.BlockHit) then
		local state = States[model]
		if state and state.Stamina <= 0 then
			model:SetAttribute("Blocking", false)
			Status.ApplyStagger(model, "Strong", Config.Stamina.GuardBreakStagger, direction, nil, damage)
		end
		return true
	end
	local state = States[model]
	if state then
		SetStamina(model, state, 0)
		model:SetAttribute("Blocking", false)
		Status.ApplyStagger(model, "Strong", Config.Stamina.GuardBreakStagger, direction, nil, damage)
	end
	return false
end

function Status.Step(dt: number)
	local now = Workspace:GetServerTimeNow()
	StepPushes(now)
	Elapsed += dt
	if Elapsed < STEP then
		return
	end
	local step = Elapsed
	Elapsed = 0
	for model, state in States do
		if state.Humanoid.Health <= 0 then
			table.clear(state.Slows)
			model:SetAttribute("SlowUntil", 0)
			model:SetAttribute("SlowRatio", 1)
			model:SetAttribute("ExposedUntil", 0)
			continue
		end
		RefreshSlows(model, state, now)
		local exposedUntil = model:GetAttribute("ExposedUntil")
		if typeof(exposedUntil) == "number" and exposedUntil > 0 and exposedUntil <= now then
			model:SetAttribute("ExposedUntil", 0)
		end
		if not Players:GetPlayerFromCharacter(model) and model:GetAttribute("CaptureBot") ~= true then
			continue
		end
		local blocking = model:GetAttribute("Blocking") == true
		local sprinting = model:GetAttribute("Sprinting") == true and state.Humanoid.MoveDirection.Magnitude > 0.1
		local drain = if blocking
			then Config.Stamina.BlockPerSecond
			else if sprinting then Config.Stamina.SprintPerSecond else 0
		if drain > 0 then
			SetStamina(model, state, state.Stamina - drain * step)
			state.RegenAt = now + Config.Stamina.RegenDelay
			if state.Stamina <= 0 then
				model:SetAttribute("Blocking", false)
				model:SetAttribute("Sprinting", false)
				Refresh(model)
				if blocking then
					Status.ApplyStagger(model, "Strong", Config.Stamina.GuardBreakStagger)
				end
			end
		elseif now >= state.RegenAt and state.Stamina < Config.Stamina.Max then
			SetStamina(model, state, state.Stamina + Config.Stamina.RegenPerSecond * step)
		end
	end
end

return Status

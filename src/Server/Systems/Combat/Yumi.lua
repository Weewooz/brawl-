--!strict
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Server = require(ReplicatedStorage.Shared.Network.Server)
local Weapons = require(ReplicatedStorage.Shared.Combat.Weapons)
local SkillDefinitions = require(ReplicatedStorage.Shared.Combat.SkillDefinitions)
local Rules = require(ReplicatedStorage.Shared.Combat.YumiRules)
local CaptureAuthority = require(ReplicatedStorage.Shared.Capture.Authority)
local Tags = require(ReplicatedStorage.Shared.Core.Tags)
local Projectiles = require(ReplicatedStorage.Shared.Utilities.Projectiles)
local Status = require(script.Parent.Status)

export type Hit = (attacker: Model, target: Model, damage: number, label: string) -> boolean
export type API = {
	Prepare: (self: API) -> boolean,
	Equip: (self: API, Model) -> boolean,
	Begin: (self: API, Model, number) -> boolean,
	Release: (self: API, Model, number, Vector3, Hit) -> boolean,
	Cancel: (self: API, Model, number?) -> (),
	Cast: (self: API, Model, number, Vector3, Hit) -> boolean,
	Step: (self: API, number) -> (),
}

type Pending = {
	At: number,
	Direction: Vector3,
	Definition: SkillDefinitions.Definition,
	Hit: Hit,
}
type State = {
	Charge: Rules.Charge,
	Epoch: number,
	Pending: Pending?,
	Connections: { RBXScriptConnection },
	Flights: { [Projectiles.Projectile]: boolean },
}
type Context = {
	Epoch: number,
	Round: number?,
	WorldRound: number?,
	Run: number?,
}

local Yumi = {} :: API
local States: { [Model]: State } = {}
local Config = Weapons.Get("Yumi")
assert(Config, "[Combat] Yumi weapon configuration is missing")
local RECOVERY = 0.2
local INTERRUPTS = {
	"Weapon",
	"Blocking",
	"StunnedUntil",
	"StaggeredUntil",
	"ControlDisabledUntil",
	"RootedUntil",
	"DashingUntil",
	"CaptureActive",
	"CaptureTeam",
	"CaptureRound",
	"CaptureProtectedUntil",
	"DungeonDowned",
	"DungeonRunId",
}

local function Living(character: Model): BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	return if character:IsDescendantOf(Workspace)
			and humanoid
			and humanoid.Health > 0
			and root
			and root:IsA("BasePart")
		then root
		else nil
end

local function Active(character: Model): boolean
	if
		not Living(character)
		or Weapons.Weapon(character) ~= "Yumi"
		or not character:FindFirstChild("Yumi")
		or character:GetAttribute("DungeonDowned") == true
		or character:GetAttribute("Blocking") == true
		or Status.Rooted(character)
		or Status.Dashing(character)
		or Status.Busy(character)
		or Status.Active(character, "Stun")
		or Status.Active(character, "Stagger")
		or Status.Active(character, "ControlDisabled")
		or not CaptureAuthority.CanAttack(CaptureAuthority.Read(character), Workspace:GetServerTimeNow())
	then
		return false
	end
	if character:GetAttribute("CaptureActive") == true then
		local capture = ReplicatedStorage:FindFirstChild("CaptureState")
		local phase = capture and capture:GetAttribute("Phase")
		local player = Players:GetPlayerFromCharacter(character)
		return capture ~= nil
			and (phase == "Active" or phase == "Overtime")
			and (not player or player:GetAttribute("CaptureRound") == capture:GetAttribute("Round"))
	end
	return true
end

local function CanStart(character: Model): boolean
	return Active(character) and Status.CanAct(character)
end

local function Ready(character: Model, attribute: string): boolean
	local deadline = character:GetAttribute(attribute)
	return deadline == nil
		or (typeof(deadline) == "number" and Rules.Finite(deadline) and deadline <= Workspace:GetServerTimeNow())
end

local function Direction(character: Model, requested: Vector3): Vector3?
	if typeof(requested) ~= "Vector3" then
		return nil
	end
	local x, z = Rules.Normalize(requested.X, requested.Y, requested.Z, Status.Active(character, "Confuse"))
	return if x ~= nil and z ~= nil then Vector3.new(x, 0, z) else nil
end

local function Templates(): (Model?, BasePart?)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Weapons")
	local bow = folder and folder:FindFirstChild("Yumi")
	local arrow = folder and folder:FindFirstChild("Arrow")
	local template: Model? = nil
	if bow and bow:IsA("Model") then
		local handle = bow.PrimaryPart or bow:FindFirstChild("Handle")
		if handle and handle:IsA("BasePart") then
			bow.PrimaryPart = handle
			template = bow
		end
	end
	return template, if arrow and arrow:IsA("BasePart") then arrow else nil
end

local function Target(part: Instance): Model?
	local ancestor: Instance? = part
	while ancestor and ancestor ~= Workspace do
		if ancestor:IsA("Model") and ancestor:FindFirstChildOfClass("Humanoid") then
			return ancestor
		end
		ancestor = ancestor.Parent
	end
	return nil
end

local function Opponent(character: Model, target: Model): boolean
	if
		target == character
		or not CollectionService:HasTag(target, Tags.Combatant)
		or not Living(target)
		or target:GetAttribute("DungeonDowned") == true
		or target:FindFirstChildOfClass("ForceField") ~= nil
		or (Players:GetPlayerFromCharacter(target) ~= nil and Status.Dashing(target))
		or not CaptureAuthority.CanHit(
			CaptureAuthority.Read(character),
			CaptureAuthority.Read(target),
			Workspace:GetServerTimeNow()
		)
	then
		return false
	end
	local run = character:GetAttribute("DungeonRunId")
	local targetRun = target:GetAttribute("DungeonRunId")
	if run ~= nil or targetRun ~= nil then
		return run ~= nil
			and run == targetRun
			and (CollectionService:HasTag(character, "DungeonMob") or CollectionService:HasTag(target, "DungeonMob"))
	end
	return true
end

local function Snapshot(character: Model, state: State): Context
	local capture = ReplicatedStorage:FindFirstChild("CaptureState")
	local player = Players:GetPlayerFromCharacter(character)
	return {
		Epoch = state.Epoch,
		Round = if player then player:GetAttribute("CaptureRound") else nil,
		WorldRound = if character:GetAttribute("CaptureActive") == true and capture
			then capture:GetAttribute("Round")
			else nil,
		Run = character:GetAttribute("DungeonRunId"),
	}
end

local function Current(character: Model, state: State, context: Context): boolean
	local player = Players:GetPlayerFromCharacter(character)
	if
		States[character] ~= state
		or state.Epoch ~= context.Epoch
		or not Active(character)
		or (if player then player:GetAttribute("CaptureRound") else nil) ~= context.Round
		or character:GetAttribute("DungeonRunId") ~= context.Run
	then
		return false
	end
	if context.WorldRound ~= nil then
		local capture = ReplicatedStorage:FindFirstChild("CaptureState")
		return capture ~= nil and capture:GetAttribute("Round") == context.WorldRound
	end
	return true
end

local function Filter(character: Model): { Instance }
	local filter: { Instance } = { character, Projectiles.GetVisualFolder() }
	for _, instance in CollectionService:GetTagged(Tags.Combatant) do
		if instance:IsA("Model") and not Opponent(character, instance) then
			table.insert(filter, instance)
		end
	end
	return filter
end

local function Launch(
	character: Model,
	state: State,
	direction: Vector3,
	range: number,
	damage: number,
	label: string,
	maximum: number,
	hit: Hit,
	slow: SkillDefinitions.Slow?
): boolean
	local root = Living(character)
	local _, arrow = Templates()
	if not root or not arrow then
		return false
	end
	local speed = Config.Speed or 100
	local definition: Projectiles.Definition = {
		Speed = speed,
		Acceleration = Vector3.zero,
		Fly = { Time = range / speed + 0.1, Distance = range },
		Cast = { Size = Vector3.new(0.25, 0.25, 0.8), Shape = "Block" },
		Model = arrow,
	}
	local bow = character:FindFirstChild("Yumi")
	local muzzle = bow and bow:FindFirstChild("Muzzle", true)
	local origin = if muzzle and muzzle:IsA("Attachment")
		then muzzle.WorldPosition
		else root.Position + Vector3.yAxis * 0.5 + direction * 1.5
	local filter = Filter(character)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local cover: { Instance } = { character, Projectiles.GetVisualFolder() }
	for _, instance in CollectionService:GetTagged(Tags.Combatant) do
		table.insert(cover, instance)
	end
	params.FilterDescendantsInstances = cover
	local start = root.Position + Vector3.yAxis * 0.5
	if (origin - start).Magnitude > 6 or Workspace:Raycast(start, origin - start, params) then
		return false
	end
	local launch = Projectiles.GetLaunchInfo(definition, origin, direction, filter)
	if not launch or launch.Obstruction then
		return false
	end
	local context = Snapshot(character, state)
	local reserved: { [Model]: boolean } = {}
	local applied: { [Model]: boolean } = {}
	local count = 0
	local now = Workspace:GetServerTimeNow()
	local projectile = Projectiles.Launch({
		Definition = definition,
		Origin = launch.Origin,
		Direction = direction,
		Filter = filter,
		Visual = false,
		FiredAt = now,
		CanPierce = function(flight, result)
			if not Current(character, state, context) then
				return false
			end
			local target = Target(result.Instance)
			if not target then
				return false
			end
			local eligible = Opponent(character, target)
			if eligible and not reserved[target] then
				reserved[target] = true
				count += 1
			end
			local raycast = flight.RaycastParams
			if raycast then
				local ignored = raycast.FilterDescendantsInstances
				table.insert(ignored, target)
				raycast.FilterDescendantsInstances = ignored
			end
			return not eligible or count < maximum
		end,
		OnHit = function(_, result)
			local target = Target(result.Instance)
			if
				not target
				or not reserved[target]
				or applied[target]
				or not Current(character, state, context)
				or not Opponent(character, target)
			then
				return
			end
			applied[target] = true
			if hit(character, target, damage, label) and slow then
				Status.ApplySlow(target, slow.Ratio, slow.Duration, slow.Key)
			end
		end,
		OnDestroy = function(flight)
			state.Flights[flight] = nil
		end,
	})
	state.Flights[projectile] = true
	Server.Combat.Projectile.FireAll(character, launch.Origin, direction, speed, range, now, maximum)
	return true
end

function Yumi:Cancel(character: Model, id: number?)
	local state = States[character]
	if not state or not Rules.Cancel(state.Charge, id) then
		return
	end
	state.Epoch += 1
	local endsAt = character:GetAttribute("SkillUntil")
	if typeof(endsAt) == "number" and endsAt > Workspace:GetServerTimeNow() then
		character:SetAttribute("SkillUntil", 0)
	end
	state.Pending = nil
	character:SetAttribute("BowDrawStartedAt", 0)
	local flights = {}
	for flight in state.Flights do
		table.insert(flights, flight)
	end
	for _, flight in flights do
		state.Flights[flight] = nil
		Projectiles.Terminate(flight, "Interrupted")
	end
end

function Yumi:Prepare(): boolean
	local bow, arrow = Templates()
	return bow ~= nil and arrow ~= nil
end

function Yumi:Equip(character: Model): boolean
	local hand = character:FindFirstChild("LeftHand")
	local template = Templates()
	if not hand or not hand:IsA("BasePart") or not template or not Living(character) then
		return false
	end
	Yumi:Cancel(character)
	local previous = character:FindFirstChild("Yumi")
	local previousGrip = hand:FindFirstChild("YumiGrip")
	if previous then
		previous:Destroy()
	end
	if previousGrip then
		previousGrip:Destroy()
	end
	local bow = template:Clone()
	local handle = bow.PrimaryPart or bow:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		bow:Destroy()
		return false
	end
	bow.PrimaryPart = handle
	bow:PivotTo(hand.CFrame)
	bow.Parent = character
	local grip = Instance.new("Motor6D")
	grip.Name = "YumiGrip"
	grip.Part0 = hand
	grip.Part1 = handle
	grip.C0 = CFrame.identity
	grip.C1 = CFrame.identity
	grip.Parent = hand
	character:SetAttribute("BowDrawStartedAt", 0)
	if not States[character] then
		local state: State = {
			Charge = { LastId = nil, Id = nil, StartedAt = nil },
			Epoch = 0,
			Pending = nil,
			Connections = {},
			Flights = {},
		}
		States[character] = state
		for _, attribute in INTERRUPTS do
			table.insert(
				state.Connections,
				character:GetAttributeChangedSignal(attribute):Connect(function()
					Yumi:Cancel(character)
				end)
			)
		end
		local player = Players:GetPlayerFromCharacter(character)
		if player then
			table.insert(
				state.Connections,
				player:GetAttributeChangedSignal("CaptureRound"):Connect(function()
					Yumi:Cancel(character)
				end)
			)
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			table.insert(
				state.Connections,
				humanoid.Died:Connect(function()
					Yumi:Cancel(character)
				end)
			)
		end
		table.insert(
			state.Connections,
			character.ChildRemoved:Connect(function(child)
				if child.Name == "Yumi" then
					Yumi:Cancel(character)
				end
			end)
		)
		table.insert(
			state.Connections,
			character.Destroying:Connect(function()
				Yumi:Cancel(character)
				for _, connection in state.Connections do
					connection:Disconnect()
				end
				States[character] = nil
			end)
		)
	end
	return true
end

function Yumi:Begin(character: Model, id: number): boolean
	local state = States[character]
	if not state or state.Pending or not CanStart(character) or not Ready(character, "AttackReadyAt") then
		return false
	end
	local stamina = character:GetAttribute("Stamina")
	if typeof(stamina) ~= "number" or not Rules.Finite(stamina) or stamina < Config.Attack.Stamina then
		return false
	end
	local now = Workspace:GetServerTimeNow()
	if not Rules.Begin(state.Charge, id, now) then
		return false
	end
	character:SetAttribute("BowDrawStartedAt", now)
	character:SetAttribute("Sprinting", false)
	return true
end

function Yumi:Release(character: Model, id: number, requested: Vector3, hit: Hit): boolean
	local state = States[character]
	local direction = Direction(character, requested)
	if not state or state.Charge.Id ~= id or not Rules.ValidId(id) then
		return false
	end
	if not direction or not CanStart(character) or not Ready(character, "AttackReadyAt") then
		Yumi:Cancel(character, id)
		return false
	end
	local now = Workspace:GetServerTimeNow()
	local damage =
		Rules.Release(state.Charge, id, now, Config.ChargeTime or 1, Config.MinDamage or 10, Config.MaxDamage or 28)
	character:SetAttribute("BowDrawStartedAt", 0)
	if not damage or not Status.ConsumeStamina(character, Config.Attack.Stamina) then
		return false
	end
	character:SetAttribute("AttackReadyAt", now + Config.Attack.Cooldown)
	character:SetAttribute("ActionRecoveryUntil", now + RECOVERY)
	return Launch(character, state, direction, Config.Range, damage, "Yumi", 1, hit, nil)
end

function Yumi:Cast(character: Model, slotIndex: number, requested: Vector3, hit: Hit): boolean
	if not Rules.Finite(slotIndex) or slotIndex % 1 ~= 0 then
		return false
	end
	local slot = SkillDefinitions.Slot(slotIndex)
	local state = States[character]
	local direction = Direction(character, requested)
	if
		not slot
		or not state
		or state.Pending
		or not direction
		or not CanStart(character)
		or not Ready(character, "AttackReadyAt")
	then
		return false
	end
	local skill = SkillDefinitions.Resolve("Yumi", slot)
	if
		not skill
		or not skill.Projectile
		or not Ready(character, slot .. "ReadyAt")
		or not Status.ConsumeStamina(character, skill.Stamina)
	then
		return false
	end
	Yumi:Cancel(character)
	local now = Workspace:GetServerTimeNow()
	character:SetAttribute(slot .. "ReadyAt", now + skill.Cooldown)
	character:SetAttribute("ActionRecoveryUntil", now + skill.Duration)
	character:SetAttribute("Sprinting", false)
	state.Pending = { At = now + skill.Windup, Direction = direction, Definition = skill, Hit = hit }
	character:SetAttribute("SkillId", skill.Id)
	character:SetAttribute("SkillStartedAt", now)
	character:SetAttribute("SkillDirection", direction)
	character:SetAttribute("SkillUntil", now + skill.Duration)
	local sequence = character:GetAttribute("SkillSequence")
	character:SetAttribute("SkillSequence", (if typeof(sequence) == "number" then sequence else 0) + 1)
	return true
end

function Yumi:Step(dt: number)
	if not Rules.Finite(dt) or dt < 0 then
		return
	end
	local now = Workspace:GetServerTimeNow()
	for character, state in States do
		if not Active(character) then
			if state.Charge.Id ~= nil or state.Pending or next(state.Flights) then
				Yumi:Cancel(character)
			end
			continue
		end
		local pending = state.Pending
		if not pending or now < pending.At then
			continue
		end
		state.Pending = nil
		local skill = pending.Definition
		local projectile = skill.Projectile
		if not projectile then
			continue
		end
		for _, angle in projectile.Angles do
			local direction = CFrame.Angles(0, math.rad(angle), 0):VectorToWorldSpace(pending.Direction)
			Launch(
				character,
				state,
				direction,
				skill.Range,
				projectile.Damage,
				skill.Name,
				projectile.MaxTargets,
				pending.Hit,
				projectile.Slow
			)
		end
	end
end

return Yumi

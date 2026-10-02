--!strict
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Server = require(ReplicatedStorage.Shared.Network.Server)
local Config = require(ReplicatedStorage.Shared.Combat.Config)
local Weapons = require(ReplicatedStorage.Shared.Combat.Weapons)
local SkillDefinitions = require(ReplicatedStorage.Shared.Combat.SkillDefinitions)
local Tags = require(ReplicatedStorage.Shared.Core.Tags)
local Status = require(script.Status)
local Katana = require(script.Katana)
local Yumi = require(script.Yumi)
local Melee = require(ReplicatedStorage.Shared.Combat.Melee)
local History = require(script.History)
local TrainingRig = require(script.TrainingRig)
local Skills = require(script.Skills)
local SkillHandlers = require(script.SkillHandlers)
local Team = require(script.Team)
local CaptureAuthority = require(ReplicatedStorage.Shared.Capture.Authority)

local Attacks = require(script.Attacks)
local Hits = require(script.Hits)
local Characters = require(script.Characters)

type LethalHandler = Hits.LethalHandler
type HitContext = Hits.HitContext

export type System = {
	Init: (self: System) -> (),
	Start: (self: System) -> (),
	ApplyStatus: (self: System, target: Model, kind: Status.Kind, duration: number) -> boolean,
	ApplyStagger: (
		self: System,
		target: Model,
		level: Status.StaggerLevel,
		duration: number,
		direction: Vector3?,
		impactDamage: number?
	) -> boolean,
	SetGrit: (self: System, player: Player, value: number) -> boolean,
	EquipWeapon: (self: System, player: Player, id: string) -> boolean,
	BeginDraw: (self: System, player: Player, id: number, enabled: boolean) -> boolean,
	ReleaseDraw: (self: System, player: Player, id: number, direction: Vector3) -> boolean,
	CastSlot: (self: System, player: Player, slot: number, direction: Vector3, target: Instance?) -> boolean,
	CastSkill: (self: System, character: Model, id: string, direction: Vector3?, target: Instance?) -> boolean,
	CancelSkills: (self: System, character: Model) -> (),
	ApplyHit: (
		self: System,
		attacker: Model,
		target: Model,
		damage: number,
		knockback: number,
		stun: number?,
		contact: HitContext?,
		stagger: boolean?,
		skill: string?
	) -> boolean,
	ApplySkillHit: (
		self: System,
		attacker: Model,
		target: Model,
		damage: number,
		stagger: boolean?,
		skill: string?
	) -> boolean,
	TryAttack: (
		self: System,
		player: Player,
		attackId: number,
		startedAt: number,
		direction: Vector3,
		kind: number
	) -> boolean,
	TryHitCandidate: (
		self: System,
		player: Player,
		attackId: number,
		target: Instance,
		at: number,
		position: Vector3
	) -> boolean,
	TryNPCAttack: (self: System, character: Model, direction: Vector3) -> boolean,
	RegisterCaptureBot: (self: System, character: Model) -> boolean,
	UnregisterCaptureBot: (self: System, character: Model) -> (),
	ResetCaptureBot: (self: System, character: Model) -> boolean,
	TryCaptureBotSkill: (self: System, character: Model, name: string, direction: Vector3, target: Model?) -> boolean,
	SetCaptureBotBlocking: (self: System, character: Model, enabled: boolean) -> boolean,
	SetCaptureBotLethalHandler: (self: System, handler: ((Model) -> ())?) -> (),
	RegisterDungeonMob: (self: System, character: Model) -> boolean,
	UnregisterDungeonMob: (self: System, character: Model) -> (),
	SetLethalHandler: (self: System, handler: LethalHandler?) -> (),
	TryDash: (self: System, player: Player, direction: Vector3) -> boolean,
	TrySpin: (self: System, player: Player) -> boolean,
	TryCharge: (self: System, player: Player, target: Instance) -> boolean,
	TryRisingCrash: (self: System, player: Player, direction: Vector3) -> boolean,
	TryGroundShock: (self: System, player: Player, direction: Vector3) -> boolean,
	SetSprinting: (self: System, player: Player, enabled: boolean) -> boolean,
	SetBlocking: (self: System, player: Player, enabled: boolean) -> boolean,
}

local System = {} :: System

local BoundBots: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local function OffensiveAllowed(character: Model?): boolean
	return character ~= nil
		and CaptureAuthority.CanAttack(CaptureAuthority.Read(character), Workspace:GetServerTimeNow())
end

local function GetLiving(model: Model?): (Humanoid?, BasePart?)
	if not model then
		return nil, nil
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, nil
	end
	return humanoid, root
end

local function GetDirection(direction: Vector3, root: BasePart): Vector3?
	if typeof(direction) ~= "Vector3" then
		return nil
	end
	if
		direction.X ~= direction.X
		or direction.Z ~= direction.Z
		or math.abs(direction.X) > 1e6
		or math.abs(direction.Z) > 1e6
	then
		return nil
	end
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.01 then
		local facing = root.CFrame.LookVector
		flat = Vector3.new(facing.X, 0, facing.Z)
	end
	return if flat.Magnitude > 0.01 then flat.Unit else nil
end

function System:EquipWeapon(player: Player, id: string): boolean
	return Characters:EquipWeapon(player, id)
end

function System:SetGrit(player: Player, value: number): boolean
	return Characters:SetGrit(player, value)
end

function System:ApplyHit(
	attacker: Model,
	target: Model,
	damage: number,
	knockback: number,
	stun: number?,
	contact: HitContext?,
	stagger: boolean?,
	skill: string?
): boolean
	return Hits:ApplyHit(attacker, target, damage, knockback, stun, contact, stagger, skill)
end

function System:ApplySkillHit(
	attacker: Model,
	target: Model,
	damage: number,
	stagger: boolean?,
	skill: string?
): boolean
	return Hits:ApplySkillHit(attacker, target, damage, stagger, skill)
end

function System:TryAttack(
	player: Player,
	attackId: number,
	startedAt: number,
	direction: Vector3,
	kind: number
): boolean
	return Attacks:TryAttack(player, attackId, startedAt, direction, kind)
end

function System:TryHitCandidate(
	player: Player,
	attackId: number,
	target: Instance,
	at: number,
	position: Vector3
): boolean
	return Attacks:TryHitCandidate(
		player,
		attackId,
		target,
		at,
		position,
		function(attacker, victim, damage, knockback, stun, contact, stagger, skill)
			return self:ApplyHit(attacker, victim, damage, knockback, stun, contact, stagger, skill)
		end
	)
end

function System:TryNPCAttack(character: Model, direction: Vector3): boolean
	return Attacks:TryNPCAttack(
		character,
		direction,
		function(attacker, victim, damage, knockback, stun, contact, stagger, skill)
			return self:ApplyHit(attacker, victim, damage, knockback, stun, contact, stagger, skill)
		end
	)
end

function System:BeginDraw(player: Player, id: number, enabled: boolean): boolean
	local character = player.Character
	if not character then
		return false
	end
	if not enabled then
		Yumi:Cancel(character, id)
		return true
	end
	return Yumi:Begin(character, id)
end

function System:ReleaseDraw(player: Player, id: number, direction: Vector3): boolean
	local character = player.Character
	return character ~= nil
		and Yumi:Release(character, id, direction, function(attacker, target, damage, label)
			return self:ApplySkillHit(attacker, target, damage, false, label)
		end)
end

function System:CastSkill(character: Model, id: string, direction: Vector3?, target: Instance?): boolean
	local definition = SkillDefinitions.Get(id)
	if not definition or not CollectionService:HasTag(character, Tags.Combatant) or not OffensiveAllowed(character) then
		return false
	end
	local _, root = GetLiving(character)
	return SkillHandlers.Cast(character, definition, {
		Direction = direction or (if root then root.CFrame.LookVector else Vector3.zero),
		Target = target,
		Player = Players:GetPlayerFromCharacter(character),
	}, function(attacker, victim, damage, label, stagger)
		return self:ApplySkillHit(attacker, victim, damage, stagger, label)
	end)
end

function System:CancelSkills(character: Model)
	Skills.Cancel(character)
	Yumi:Cancel(character)
end

function System:CastSlot(player: Player, slot: number, direction: Vector3, target: Instance?): boolean
	local character = player.Character
	local name = SkillDefinitions.Slot(slot)
	local definition = name and SkillDefinitions.Resolve(Weapons.Weapon(character), name)
	return character ~= nil and definition ~= nil and self:CastSkill(character, definition.Id, direction, target)
end

function System:ApplyStatus(target: Model, kind: Status.Kind, duration: number): boolean
	local applied = Status.Apply(target, kind, duration)
	if applied and kind ~= "Confuse" then
		Skills.Cancel(target)
		Yumi:Cancel(target)
		Attacks:Clear(target)
		Melee:Cancel(target)
	end
	return applied
end

function System:ApplyStagger(
	target: Model,
	level: Status.StaggerLevel,
	duration: number,
	direction: Vector3?,
	impactDamage: number?
): boolean
	local applied = Status.ApplyStagger(target, level, duration, direction, nil, impactDamage)
	if applied then
		Skills.Cancel(target)
		Yumi:Cancel(target)
		Attacks:Clear(target)
		Melee:Cancel(target)
	end
	return applied
end

function System:RegisterDungeonMob(character: Model): boolean
	local humanoid, root = GetLiving(character)
	if not humanoid or not root or character:GetAttribute("DungeonRunId") == nil then
		return false
	end
	if not Katana.Equip(character) or not Melee:Bind(character) or not Status.Attach(character) then
		return false
	end
	Status.OwnNPC(character)
	CollectionService:AddTag(character, "DungeonMob")
	character:SetAttribute("AttackReadyAt", 0)
	character:SetAttribute("StrikeIndex", 0)
	return true
end

function System:ResetCaptureBot(character: Model): boolean
	Skills.Cancel(character)
	Melee:Cancel(character)
	Attacks:Clear(character)
	Team.Clear(character)
	for _, name in { "Attack", "Spin", "Charge", "RisingCrash", "GroundShock", "Dash" } do
		character:SetAttribute(name .. "ReadyAt", 0)
	end
	return Status.Reset(character)
end

function System:RegisterCaptureBot(character: Model): boolean
	local humanoid, root = GetLiving(character)
	if not humanoid or not root or character:GetAttribute("CaptureBot") ~= true then
		return false
	end
	local weapon = character:FindFirstChild("Katana")
	local hand = character:FindFirstChild("RightHand")
	if
		not weapon
		or not weapon:IsA("Model")
		or not weapon:FindFirstChild("Sword")
		or not hand
		or not hand:FindFirstChild("KatanaGrip")
	then
		warn("[Combat] Capture bot requires an authored katana and grip: " .. character.Name)
		return false
	end
	if not BoundBots[character] and not Melee:Bind(character) then
		return false
	end
	if not Status.Attach(character) then
		return false
	end
	BoundBots[character] = true
	CollectionService:AddTag(character, Tags.Combatant)
	Status.OwnNPC(character)
	return self:ResetCaptureBot(character)
end

function System:UnregisterCaptureBot(character: Model)
	self:ResetCaptureBot(character)
	CollectionService:RemoveTag(character, Tags.Combatant)
	-- Pooled rigs keep their cast bindings between rounds.
end

function System:SetCaptureBotLethalHandler(handler: ((Model) -> ())?)
	Hits:SetCaptureBotLethalHandler(handler)
end

function System:SetCaptureBotBlocking(character: Model, enabled: boolean): boolean
	return character:GetAttribute("CaptureBot") == true and Status.SetBlocking(character, enabled)
end

function System:TryCaptureBotSkill(character: Model, name: string, direction: Vector3, target: Model?): boolean
	if
		character:GetAttribute("CaptureBot") ~= true
		or not CollectionService:HasTag(character, Tags.Combatant)
		or not OffensiveAllowed(character)
	then
		return false
	end
	local definition = SkillDefinitions.Resolve(Weapons.Weapon(character), name)
	return definition ~= nil and self:CastSkill(character, definition.Id, direction, target)
end

function System:UnregisterDungeonMob(character: Model)
	CollectionService:RemoveTag(character, "DungeonMob")
	CollectionService:RemoveTag(character, Tags.Combatant)
	Melee:Unbind(character)
	Attacks:Clear(character)
end

function System:SetLethalHandler(handler: LethalHandler?)
	Hits:SetLethalHandler(handler)
end

function System:TryDash(player: Player, direction: Vector3): boolean
	local character = player.Character
	local humanoid, root = GetLiving(character)
	if
		not character
		or not humanoid
		or not root
		or not Status.CanAct(character)
		or Status.Busy(character)
		or Status.Rooted(character)
		or character:GetAttribute("DungeonDowned") == true
	then
		return false
	end
	local now = Workspace:GetServerTimeNow()
	local readyAt = character:GetAttribute("DashReadyAt")
	if typeof(readyAt) == "number" and readyAt > now then
		return false
	end
	local aim = GetDirection(direction, root)
	if not aim then
		return false
	end
	if Status.Active(character, "Confuse") then
		aim = -aim
	end
	if not Status.ConsumeStamina(character, Config.Stamina.Dash) then
		return false
	end
	Yumi:Cancel(character)
	character:SetAttribute("DashReadyAt", now + Config.DashCooldown)
	character:SetAttribute("DashingUntil", now + Config.DashDuration)
	local attachment = Instance.new("Attachment")
	attachment.Name = "DashAttachment"
	attachment.Parent = root
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "DashVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.ForceLimitsEnabled = true
	velocity.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	local horizontalForce = root.AssemblyMass * 600
	velocity.MaxAxesForce = Vector3.new(horizontalForce, 0, horizontalForce)
	velocity.VectorVelocity = aim * Config.DashSpeed
	velocity.Parent = root
	root.AssemblyLinearVelocity = aim * Config.DashSpeed + Vector3.yAxis * root.AssemblyLinearVelocity.Y
	task.delay(Config.DashDuration, function()
		velocity:Destroy()
		attachment:Destroy()
	end)
	return true
end

function System:TrySpin(player: Player): boolean
	local character = player.Character
	return character ~= nil and self:CastSkill(character, "WindSpin")
end

function System:TryCharge(player: Player, target: Instance): boolean
	local character = player.Character
	return character ~= nil and self:CastSkill(character, "Charge", nil, target)
end

function System:TryRisingCrash(player: Player, direction: Vector3): boolean
	local character = player.Character
	return character ~= nil and self:CastSkill(character, "RisingCrash", direction)
end

function System:TryGroundShock(player: Player, direction: Vector3): boolean
	local character = player.Character
	return character ~= nil and self:CastSkill(character, "GroundShock", direction)
end

function System:SetSprinting(player: Player, enabled: boolean): boolean
	local character = player.Character
	return character ~= nil
		and character:GetAttribute("DungeonDowned") ~= true
		and Status.SetSprinting(character, enabled)
end

function System:SetBlocking(player: Player, enabled: boolean): boolean
	local character = player.Character
	if character and enabled then
		Yumi:Cancel(character)
	end
	return character ~= nil
		and character:GetAttribute("DungeonDowned") ~= true
		and Status.SetBlocking(character, enabled)
end

function System:Init()
	Team.Init()
	Katana.Prepare()
	Yumi:Prepare()
	require(script.Parent.Capture.Bots).Configure(self)
	Characters:Init()
	RunService.Heartbeat:Connect(Status.Step)
	RunService.Heartbeat:Connect(function(dt)
		Yumi:Step(dt)
	end)
	RunService.Heartbeat:Connect(History.Step)
	task.spawn(function()
		TrainingRig:Start(function(rig, role)
			Status.Attach(rig)
			if role ~= "Idle" then
				if Katana.Equip(rig) then
					Melee:Bind(rig)
				else
					warn("[Combat] Could not equip training katana for " .. rig.Name)
				end
			end
			Status.OwnNPC(rig)
		end, function(rig, direction)
			self:TryNPCAttack(rig, direction)
		end)
	end)

	Characters:BindPlayers()

	Server.Combat.Equip.On(function(player, id)
		self:EquipWeapon(player, id)
	end)
	Server.Combat.Draw.On(function(player, id, enabled)
		self:BeginDraw(player, id, enabled)
	end)
	Server.Combat.Release.On(function(player, id, direction)
		self:ReleaseDraw(player, id, direction)
	end)
	Server.Combat.CastSlot.On(function(player, slot, direction, target)
		self:CastSlot(player, slot, direction, target)
	end)
	Server.Combat.Attack.On(function(player, attackId, startedAt, direction, kind)
		self:TryAttack(player, attackId, startedAt, direction, kind)
	end)
	Server.Combat.HitCandidate.On(function(player, attackId, target, at, position)
		self:TryHitCandidate(player, attackId, target, at, position)
	end)
	Server.Combat.Sprint.On(function(player, enabled)
		self:SetSprinting(player, enabled)
	end)
	Server.Combat.Dash.On(function(player, direction)
		self:TryDash(player, direction)
	end)
	Server.Combat.Spin.On(function(player, enabled)
		if enabled then
			self:TrySpin(player)
		end
	end)
	Server.Combat.Charge.On(function(player, target)
		self:TryCharge(player, target)
	end)
	Server.Combat.RisingCrash.On(function(player, direction)
		self:TryRisingCrash(player, direction)
	end)
	Server.Combat.GroundShock.On(function(player, direction)
		self:TryGroundShock(player, direction)
	end)
	Server.Combat.Block.On(function(player, enabled)
		self:SetBlocking(player, enabled)
	end)
end

function System:Start() end

return System

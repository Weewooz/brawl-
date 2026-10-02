--!strict
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Combat.Config)
local Weapons = require(ReplicatedStorage.Shared.Combat.Weapons)
local Tags = require(ReplicatedStorage.Shared.Core.Tags)
local Melee = require(ReplicatedStorage.Shared.Combat.Melee)
local CaptureAuthority = require(ReplicatedStorage.Shared.Capture.Authority)
local Status = require(script.Parent.Status)
local History = require(script.Parent.History)
local AnimationAssets = ReplicatedStorage.Assets:WaitForChild("CombatAnimations")

export type HitContext = {
	AttackerPosition: Vector3,
	TargetPosition: Vector3,
	TargetFacing: Vector3,
	TargetBlocking: boolean,
}

type AttackState = {
	Id: number,
	Kind: number,
	StartedAt: number,
	Aim: Vector3,
	Targets: { [Model]: boolean },
	Candidates: number,
}

export type Hit = (
	attacker: Model,
	target: Model,
	damage: number,
	knockback: number,
	stun: number?,
	contact: HitContext?,
	stagger: boolean?,
	skill: string?
) -> boolean
export type API = {
	Clear: (self: API, character: Model) -> (),
	StopTracks: (self: API, character: Model) -> (),
	TryAttack: (
		self: API,
		player: Player,
		attackId: number,
		startedAt: number,
		direction: Vector3,
		kind: number
	) -> boolean,
	TryHitCandidate: (
		self: API,
		player: Player,
		attackId: number,
		target: Instance,
		at: number,
		position: Vector3,
		hit: Hit
	) -> boolean,
	TryNPCAttack: (self: API, character: Model, direction: Vector3, hit: Hit) -> boolean,
}

local Attacks = {} :: API
local Tracks: { [Model]: { AnimationTrack } } = {}
local Sources: { Animation } = {}
local ActiveAttacks: { [Model]: AttackState } = {}
local ATTACK_NAMES = { "Slash", "Reverse" }
local M1_ATTACK = 1
local MAX_LAG = 0.4
local MAX_CANDIDATES = 12
local CONTACT_TOLERANCE = 0.08

local function OffensiveAllowed(character: Model?): boolean
	return character ~= nil
		and CaptureAuthority.CanAttack(CaptureAuthority.Read(character), Workspace:GetServerTimeNow())
end

for _, name in ATTACK_NAMES do
	local source = AnimationAssets:WaitForChild(name)
	assert(source:IsA("Animation"), "[Combat] Missing authored attack animation " .. name)
	table.insert(Sources, source)
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

local function GetTracks(model: Model): { AnimationTrack }?
	local cached = Tracks[model]
	if cached then
		return cached
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local animator: Animator? = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		local created = Instance.new("Animator")
		created.Parent = humanoid
		animator = created
	end
	local loaded = {}
	for _, source in Sources do
		local track = (animator :: Animator):LoadAnimation(source)
		track.Looped = false
		track.Priority = Enum.AnimationPriority.Action3
		table.insert(loaded, track)
	end
	Tracks[model] = loaded
	model.Destroying:Connect(function()
		for _, track in loaded do
			track:Destroy()
		end
		Tracks[model] = nil
	end)
	return loaded
end

local function ClearSight(attacker: Model, origin: BasePart, target: Model, targetRoot: BasePart): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { attacker }
	local direction = targetRoot.Position - origin.Position
	local result = Workspace:Raycast(origin.Position, direction, params)
	return result == nil or result.Instance:IsDescendantOf(target)
end

local function ClearStaticSight(origin: Vector3, position: Vector3): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = CollectionService:GetTagged(Tags.Combatant)
	return Workspace:Raycast(origin, position - origin, params) == nil
end

local function FiniteVector(value: Vector3): boolean
	return typeof(value) == "Vector3"
		and value.X == value.X
		and value.Y == value.Y
		and value.Z == value.Z
		and math.abs(value.X) < 1e6
		and math.abs(value.Y) < 1e6
		and math.abs(value.Z) < 1e6
end

function Attacks:Clear(character: Model)
	ActiveAttacks[character] = nil
end

function Attacks:StopTracks(character: Model)
	local tracks = Tracks[character]
	if tracks then
		for _, track in tracks do
			track:Stop(0.05)
		end
	end
end

local function StartAttack(
	hit: Hit,
	character: Model,
	direction: Vector3,
	damage: number,
	knockback: number,
	stun: number?,
	cooldown: number,
	playersOnly: boolean
): boolean
	local humanoid, root = GetLiving(character)
	if
		not humanoid
		or not root
		or not Status.CanAct(character)
		or Status.Busy(character)
		or character:GetAttribute("DungeonDowned") == true
	then
		return false
	end
	local now = Workspace:GetServerTimeNow()
	local readyAt = character:GetAttribute("AttackReadyAt")
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

	character:SetAttribute("AttackReadyAt", now + cooldown)
	local index = ((character:GetAttribute("StrikeIndex") or 0) :: number) % #ATTACK_NAMES + 1
	character:SetAttribute("StrikeIndex", index)
	local isPlayer = Players:GetPlayerFromCharacter(character) ~= nil
	if not isPlayer then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + aim)
		local autoRotate = humanoid.AutoRotate
		humanoid.AutoRotate = false
		task.delay(Config.Attack.Windup + Config.Attack.Active, function()
			if humanoid.Parent then
				humanoid.AutoRotate = autoRotate
			end
		end)
	end
	local tracks = GetTracks(character)
	if tracks and not isPlayer then
		tracks[index]:Play(0.05)
	end
	task.delay(Config.Attack.Windup, function()
		if not Status.CanAct(character) or character:GetAttribute("DungeonDowned") == true then
			return
		end
		Melee:Swing(character, aim, Config.Attack.Active, function(target)
			if not Status.CanAct(character) or character:GetAttribute("DungeonDowned") == true then
				return
			end
			if playersOnly and not Players:GetPlayerFromCharacter(target) then
				return
			end
			local _, currentRoot = GetLiving(character)
			local _, targetRoot = GetLiving(target)
			if currentRoot and targetRoot and ClearSight(character, currentRoot, target, targetRoot) then
				hit(character, target, damage, knockback, stun)
			end
		end)
	end)
	return true
end

function Attacks:TryAttack(
	player: Player,
	attackId: number,
	startedAt: number,
	direction: Vector3,
	kind: number
): boolean
	if Weapons.Weapon(player.Character) ~= "Katana" or not OffensiveAllowed(player.Character) then
		return false
	end
	if kind ~= M1_ATTACK then
		return false
	end
	local config = Config.Attack
	local character = player.Character
	local humanoid, root = GetLiving(character)
	if
		not character
		or not humanoid
		or not root
		or not Status.CanAct(character)
		or Status.Busy(character)
		or character:GetAttribute("DungeonDowned") == true
	then
		return false
	end
	local now = Workspace:GetServerTimeNow()
	if
		typeof(attackId) ~= "number"
		or attackId % 1 ~= 0
		or attackId <= 0
		or attackId > 4294967295
		or typeof(startedAt) ~= "number"
		or startedAt ~= startedAt
		or startedAt < now - MAX_LAG
		or startedAt > now + 0.05
	then
		return false
	end
	local readyAt = character:GetAttribute("AttackReadyAt")
	if typeof(readyAt) == "number" and startedAt < readyAt then
		return false
	end
	local aim = GetDirection(direction, root)
	local weapon = character:FindFirstChild("Katana")
	if not aim or not weapon or not weapon:FindFirstChild("Sword") then
		return false
	end
	if Status.Active(character, "Confuse") then
		aim = -aim
	end
	character:SetAttribute("AttackReadyAt", startedAt + config.Cooldown)
	ActiveAttacks[character] = {
		Id = attackId,
		Kind = kind,
		StartedAt = startedAt,
		Aim = aim,
		Targets = {},
		Candidates = 0,
	}
	return true
end

function Attacks:TryHitCandidate(
	player: Player,
	attackId: number,
	target: Instance,
	at: number,
	position: Vector3,
	hit: Hit
): boolean
	local character = player.Character
	local state = character and ActiveAttacks[character]
	if
		not character
		or not state
		or character:GetAttribute("DungeonDowned") == true
		or state.Id ~= attackId
		or state.Candidates >= MAX_CANDIDATES
	then
		return false
	end
	state.Candidates += 1
	local now = Workspace:GetServerTimeNow()
	if
		typeof(target) ~= "Instance"
		or not target:IsA("Model")
		or target == character
		or not target:IsDescendantOf(Workspace)
		or not CollectionService:HasTag(target, Tags.Combatant)
		or state.Targets[target]
		or typeof(at) ~= "number"
		or at ~= at
		or at < now - MAX_LAG
		or at > now + 0.05
		or not FiniteVector(position)
	then
		return false
	end
	local elapsed = at - state.StartedAt
	local config = Config.Attack
	if elapsed < config.Windup - CONTACT_TOLERANCE or elapsed > config.Windup + config.Active + CONTACT_TOLERANCE then
		return false
	end
	local targetModel = target :: Model
	local _, attackerRoot = GetLiving(character)
	local _, targetRoot = GetLiving(targetModel)
	local attackerSample = History.Get(character, math.min(at, now))
	local targetSample = History.FindTarget(targetModel, at, position)
	if not attackerRoot or not targetRoot or not attackerSample or not targetSample then
		return false
	end
	local weapon = character:FindFirstChild("Katana")
	local sword = weapon and weapon:FindFirstChild("Sword")
	if not sword or not sword:IsA("BasePart") then
		return false
	end
	local attackerPosition = attackerSample.CFrame.Position
	local targetPosition = targetSample.CFrame.Position
	local reach = sword.Size.Y + 1.5
	local displacement = position - attackerPosition
	local horizontal = Vector3.new(displacement.X, 0, displacement.Z)
	if
		displacement.Magnitude > reach
		or horizontal:Dot(state.Aim) < -1.5
		or math.abs(displacement.Y) > config.Height
		or (targetPosition - position).Magnitude > 3.5
		or (targetPosition - attackerPosition).Magnitude > reach + 3.5
		or not ClearStaticSight(attackerPosition, position)
	then
		return false
	end
	state.Targets[targetModel] = true
	return hit(character, targetModel, config.Damage, config.Knockback, nil, {
		AttackerPosition = attackerPosition,
		TargetPosition = targetSample.CFrame.Position,
		TargetFacing = targetSample.CFrame.LookVector,
		TargetBlocking = targetSample.Blocking,
	})
end

function Attacks:TryNPCAttack(character: Model, direction: Vector3, hit: Hit): boolean
	if not OffensiveAllowed(character) then
		return false
	end
	if character:GetAttribute("CaptureBot") == true then
		local attack = Config.Attack
		return StartAttack(hit, character, direction, attack.Damage, attack.Knockback, nil, attack.Cooldown, false)
	end
	if CollectionService:HasTag(character, "DungeonMob") then
		local damage = character:GetAttribute("DungeonDamage")
		local cooldown = character:GetAttribute("DungeonCooldown")
		local knockback = character:GetAttribute("DungeonKnockback")
		if typeof(damage) ~= "number" or damage ~= damage or damage < 1 or damage > 100 then
			return false
		end
		if typeof(cooldown) ~= "number" or cooldown ~= cooldown or cooldown < 0.25 or cooldown > 10 then
			return false
		end
		if typeof(knockback) ~= "number" or knockback ~= knockback or knockback < 0 or knockback > 100 then
			return false
		end
		return StartAttack(hit, character, direction, damage, knockback, nil, cooldown, true)
	end
	if character:GetAttribute("TrainingRole") ~= "Attacking" then
		return false
	end
	local npc = Config.TrainingNPC
	return StartAttack(hit, character, direction, npc.Damage, npc.Knockback, nil, npc.Cooldown, true)
end

return Attacks

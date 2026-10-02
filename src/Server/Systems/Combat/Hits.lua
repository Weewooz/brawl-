--!strict
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Server = require(ReplicatedStorage.Shared.Network.Server)
local Config = require(ReplicatedStorage.Shared.Combat.Config)
local Tags = require(ReplicatedStorage.Shared.Core.Tags)
local Melee = require(ReplicatedStorage.Shared.Combat.Melee)
local CaptureAuthority = require(ReplicatedStorage.Shared.Capture.Authority)
local CaptureOutcomes = require(script.Parent.Parent.Capture.Outcomes)
local Status = require(script.Parent.Status)
local Skills = require(script.Parent.Skills)
local Team = require(script.Parent.Team)
local Attacks = require(script.Parent.Attacks)

export type HitContext = Attacks.HitContext
export type LethalHandler = (Player, Model, Model, number) -> boolean
export type API = {
	ApplyHit: (
		self: API,
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
		self: API,
		attacker: Model,
		target: Model,
		damage: number,
		stagger: boolean?,
		skill: string?
	) -> boolean,
	SetLethalHandler: (self: API, handler: LethalHandler?) -> (),
	SetCaptureBotLethalHandler: (self: API, handler: ((Model) -> ())?) -> (),
}

local Hits = {} :: API
local LethalCallback: LethalHandler? = nil
local BotLethalCallback: ((Model) -> ())? = nil

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

function Hits:ApplyHit(
	attacker: Model,
	target: Model,
	damage: number,
	knockback: number,
	stun: number?,
	contact: HitContext?,
	stagger: boolean?,
	skill: string?
): boolean
	if attacker == target or not CollectionService:HasTag(target, Tags.Combatant) then
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
		if runId == nil or runId ~= target:GetAttribute("DungeonRunId") then
			return false
		end
	end
	local attackerHumanoid, attackerRoot = GetLiving(attacker)
	local targetHumanoid, targetRoot = GetLiving(target)
	if not attackerHumanoid or not attackerRoot or not targetHumanoid or not targetRoot then
		return false
	end
	if damage ~= damage or damage <= 0 or damage == math.huge then
		return false
	end
	local attackerPlayer = Players:GetPlayerFromCharacter(attacker)
	local targetPlayer = Players:GetPlayerFromCharacter(target)
	local dashingUntil = target:GetAttribute("DashingUntil")
	if targetPlayer and typeof(dashingUntil) == "number" and dashingUntil > Workspace:GetServerTimeNow() then
		return false
	end
	local guardBroken = false
	local blocking = if contact then contact.TargetBlocking else target:GetAttribute("Blocking") == true
	if blocking and not Status.Active(target, "Stun") then
		local attackerPosition = if contact then contact.AttackerPosition else attackerRoot.Position
		local targetPosition = if contact then contact.TargetPosition else targetRoot.Position
		local targetFacing = if contact then contact.TargetFacing else targetRoot.CFrame.LookVector
		local incoming = attackerPosition - targetPosition
		local flat = Vector3.new(incoming.X, 0, incoming.Z)
		if flat.Magnitude > 0.01 and targetFacing:Dot(flat.Unit) > 0.2 then
			local wasBlocking = target:GetAttribute("Blocking") == true
			local perfect = wasBlocking and Status.TryPerfectGuard(target)
			local trainingGuard = not targetPlayer and target:GetAttribute("CaptureBot") ~= true
			local protected = perfect
				or trainingGuard
				or Status.BlockHit(target, targetRoot.Position - attackerRoot.Position, damage)
			if perfect then
				local now = Workspace:GetServerTimeNow()
				attacker:SetAttribute(
					"ActionRecoveryUntil",
					math.max(
						(attacker:GetAttribute("ActionRecoveryUntil") or 0) :: number,
						now + Config.PerfectGuard.Recovery
					)
				)
				attacker:SetAttribute(
					"AttackReadyAt",
					math.max(
						(attacker:GetAttribute("AttackReadyAt") or 0) :: number,
						now + Config.PerfectGuard.Recovery
					)
				)
				Attacks:Clear(attacker)
				Melee:Cancel(attacker)
				Skills.Cancel(attacker)
				if targetPlayer then
					Server.Combat.Feedback.Fire(targetPlayer, "PerfectGuard", targetRoot.Position)
				end
				if attackerPlayer then
					Server.Combat.Feedback.Fire(attackerPlayer, "GuardParried", targetRoot.Position)
				end
			end
			if targetPlayer and wasBlocking and target:GetAttribute("Blocking") ~= true then
				guardBroken = true
				Server.Combat.Feedback.Fire(targetPlayer, "GuardBroken", targetRoot.Position)
			end
			if Status.Active(target, "Stagger") then
				Attacks:Clear(target)
			end
			if protected then
				target:SetAttribute("LastBlockedAt", Workspace:GetServerTimeNow())
				if attackerPlayer and guardBroken then
					Server.Combat.Feedback.Fire(attackerPlayer, "GuardBreak", targetRoot.Position)
				end
				return false
			end
		end
	end
	local health = targetHumanoid.Health
	local protectedByForceField = target:FindFirstChildOfClass("ForceField") ~= nil
	if not protectedByForceField then
		Status.CancelDash(target)
	end
	local exposed = target:GetAttribute("ExposedUntil")
	local multiplier = if typeof(exposed) == "number" and exposed > Workspace:GetServerTimeNow()
		then 1 + Config.RisingCrash.ExposedBonus
		else 1
	local effectiveDamage = damage * Status.ImpactRatio(target, damage) * multiplier
	if targetPlayer and not protectedByForceField and effectiveDamage >= health and LethalCallback then
		local handled = LethalCallback(targetPlayer, target, attacker, effectiveDamage)
		if handled then
			Team.Record(attacker, target, math.min(health, effectiveDamage), skill or "Slash", "DOWNED")
			Team.Recap(target)
			if target:GetAttribute("DungeonDowned") == true then
				targetHumanoid.Health = 1
			end
			Attacks:Clear(target)
			Melee:Cancel(target)
			Skills.Cancel(target)
			return true
		end
	end
	if not protectedByForceField then
		CaptureOutcomes.Record(attacker, target, Workspace:GetServerTimeNow())
	end
	if
		not protectedByForceField
		and target:GetAttribute("CaptureBot") == true
		and effectiveDamage >= health
		and BotLethalCallback
	then
		BotLethalCallback(target)
		Attacks:Clear(target)
		Melee:Cancel(target)
		Skills.Cancel(target)
		if attackerPlayer then
			Server.Combat.Feedback.Fire(attackerPlayer, "Elimination", targetRoot.Position)
		end
		return true
	end
	targetHumanoid:TakeDamage(effectiveDamage)
	if targetHumanoid.Health >= health then
		if attackerPlayer and guardBroken then
			Server.Combat.Feedback.Fire(attackerPlayer, "GuardBreak", targetRoot.Position)
		end
		return false
	end
	local now = Workspace:GetServerTimeNow()
	local effects = {}
	if (target:GetAttribute("ExposedUntil") or 0) > now or skill == "Rising Crash" then
		table.insert(effects, "EXPOSED")
	end
	if (target:GetAttribute("SlowUntil") or 0) > now or skill == "Charge" or skill == "Ground Shock" then
		table.insert(effects, "SLOWED")
	end
	Team.Record(attacker, target, health - targetHumanoid.Health, skill or "Slash", table.concat(effects, " / "))
	if targetHumanoid.Health <= 0 then
		Team.Recap(target)
	end
	if attackerPlayer then
		if targetHumanoid.Health <= 0 then
			Server.Combat.Feedback.Fire(attackerPlayer, "Elimination", targetRoot.Position)
		elseif guardBroken then
			Server.Combat.Feedback.Fire(attackerPlayer, "GuardBreak", targetRoot.Position)
		elseif health - targetHumanoid.Health >= Config.Attack.Damage * 1.5 then
			Server.Combat.Feedback.Fire(attackerPlayer, "HeavyHit", targetRoot.Position)
		end
	end
	if stun and stun > 0 then
		Status.Apply(target, "Stun", stun)
	end
	if
		stagger ~= false
		and Status.ApplyStagger(
			target,
			"Weak",
			Config.Attack.Stagger,
			targetRoot.Position - attackerRoot.Position,
			knockback,
			damage
		)
	then
		Skills.Cancel(target)
		Attacks:Clear(target)
		Melee:Cancel(target)
		Attacks:StopTracks(target)
	end
	return true
end

function Hits:ApplySkillHit(attacker: Model, target: Model, damage: number, stagger: boolean?, skill: string?): boolean
	local blockedAt = target:GetAttribute("LastBlockedAt")
	local applied = self:ApplyHit(attacker, target, damage, 0, nil, nil, stagger, skill)
	local player = Players:GetPlayerFromCharacter(attacker)
	if player then
		if applied then
			Server.Combat.SkillContact.Fire(player, target, false)
		elseif target:GetAttribute("LastBlockedAt") ~= blockedAt then
			Server.Combat.SkillContact.Fire(player, target, true)
		end
	end
	return applied
end

function Hits:SetLethalHandler(handler: LethalHandler?)
	LethalCallback = handler
end

function Hits:SetCaptureBotLethalHandler(handler: ((Model) -> ())?)
	BotLethalCallback = handler
end

return Hits

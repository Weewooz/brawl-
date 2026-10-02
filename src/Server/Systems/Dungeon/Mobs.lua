--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Mobs = {}

type AnimationSet = { [string]: AnimationTrack }

export type Actor = {
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Zone: number,
	Animations: AnimationSet,
	StaggerConnection: RBXScriptConnection?,
	DiedConnection: RBXScriptConnection?,
	NextMoveAt: number,
}

type CombatApi = {
	RegisterDungeonMob: (CombatApi, Model) -> boolean,
	TryNPCAttack: (CombatApi, Model, Vector3) -> boolean,
	UnregisterDungeonMob: (CombatApi, Model) -> (),
}

local Template: Model? = nil
local MOVE_INTERVAL = 0.3
local ATTACK_RANGE = 3.2
local RUN_RANGE = 18
local ANIMATION_NAMES = { "Idle", "Walk", "Run", "Impact" }

local function LoadAnimations(humanoid: Humanoid): AnimationSet?
	local animator = humanoid:FindFirstChildOfClass("Animator")
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("DungeonAnimations")
	if not animator or not folder then
		warn("[Dungeon] Mob Animator or ReplicatedStorage.Assets.DungeonAnimations is missing")
		return nil
	end
	local loaded: { [string]: AnimationTrack } = {}
	for _, name in ANIMATION_NAMES do
		local source = folder:FindFirstChild(name)
		if not source or not source:IsA("Animation") then
			warn("[Dungeon] DungeonAnimations." .. name .. " is missing")
			for _, track in loaded do
				track:Destroy()
			end
			return nil
		end
		local ok, result = pcall(function()
			return animator:LoadAnimation(source)
		end)
		if not ok then
			warn("[Dungeon] Could not load mob " .. name .. " animation: " .. tostring(result))
			for _, track in loaded do
				track:Destroy()
			end
			return nil
		end
		local track = result :: AnimationTrack
		track.Looped = name ~= "Impact"
		track.Priority = if name == "Impact" then Enum.AnimationPriority.Action4 else Enum.AnimationPriority.Movement
		loaded[name] = track
	end
	loaded.Idle.Priority = Enum.AnimationPriority.Idle
	return loaded :: AnimationSet
end

local function PlayLocomotion(actor: Actor, selected: string?)
	for _, name in { "Idle", "Walk", "Run" } do
		local track = actor.Animations[name]
		if name == selected then
			if not track.IsPlaying then
				track:Play(0.12)
			end
		elseif track.IsPlaying then
			track:Stop(0.12)
		end
	end
end

local function GetTemplate(): Model?
	if Template then
		return Template
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local rigs = assets and assets:FindFirstChild("Rigs")
	local existing = rigs and rigs:FindFirstChild("IncubatorRig")
	if existing and existing:IsA("Model") then
		Template = existing
		return existing
	end
	warn("[Dungeon] ReplicatedStorage.Assets.Rigs.IncubatorRig is missing")
	return nil
end

function Mobs.Spawn(
	container: Instance,
	position: Vector3,
	runId: number,
	zone: number,
	health: number,
	damage: number,
	combat: CombatApi
): Actor?
	local template = GetTemplate()
	if not template then
		return nil
	end
	local model = template:Clone()
	model.Name = `Dungeon Mob {zone}`
	model:SetAttribute("DungeonRunId", runId)
	model:SetAttribute("DungeonZone", zone)
	model:SetAttribute("DungeonDamage", damage)
	model:SetAttribute("DungeonCooldown", 1.1)
	model:SetAttribute("DungeonKnockback", 5)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		model:Destroy()
		warn("[Dungeon] Mob rig lacks Humanoid or HumanoidRootPart")
		return nil
	end
	humanoid.DisplayName = `Zone {zone} Mob`
	humanoid.MaxHealth = health
	humanoid.Health = health
	humanoid.WalkSpeed = 18 + zone
	local animate = model:FindFirstChild("Animate")
	if animate and animate:IsA("LocalScript") then
		animate.Enabled = false
	end
	model:PivotTo(CFrame.new(position))
	model.Parent = container
	if not combat:RegisterDungeonMob(model) then
		model:Destroy()
		return nil
	end
	local animations = LoadAnimations(humanoid)
	if not animations then
		combat:UnregisterDungeonMob(model)
		model:Destroy()
		return nil
	end
	local actor: Actor = {
		Model = model,
		Humanoid = humanoid,
		Root = root,
		Zone = zone,
		Animations = animations,
		StaggerConnection = nil,
		DiedConnection = nil,
		NextMoveAt = 0,
	}
	actor.StaggerConnection = model:GetAttributeChangedSignal("StaggeredUntil"):Connect(function()
		local untilAt = model:GetAttribute("StaggeredUntil")
		if typeof(untilAt) ~= "number" or untilAt <= Workspace:GetServerTimeNow() or humanoid.Health <= 0 then
			return
		end
		PlayLocomotion(actor, nil)
		animations.Impact:Stop(0)
		animations.Impact:Play(0.05)
	end)
	actor.DiedConnection = humanoid.Died:Connect(function()
		PlayLocomotion(actor, nil)
		animations.Impact:Stop(0.05)
	end)
	PlayLocomotion(actor, "Idle")
	return actor
end

function Mobs.Step(actor: Actor, targets: { BasePart }, combat: CombatApi, clockNow: number)
	if actor.Humanoid.Health <= 0 or actor.Model.Parent == nil or clockNow < actor.NextMoveAt then
		return
	end
	local staggeredUntil = actor.Model:GetAttribute("StaggeredUntil")
	if typeof(staggeredUntil) == "number" and staggeredUntil > Workspace:GetServerTimeNow() then
		actor.Humanoid:Move(Vector3.zero)
		PlayLocomotion(actor, nil)
		return
	end
	if actor.Animations.Impact.IsPlaying then
		actor.Animations.Impact:Stop(0.08)
	end
	actor.NextMoveAt = clockNow + MOVE_INTERVAL
	local nearest: BasePart? = nil
	local distance = math.huge
	for _, root in targets do
		local gap = (root.Position - actor.Root.Position).Magnitude
		if gap < distance then
			nearest = root
			distance = gap
		end
	end
	if not nearest then
		actor.Humanoid:MoveTo(actor.Root.Position)
		PlayLocomotion(actor, "Idle")
		return
	end
	if distance > ATTACK_RANGE then
		if distance > RUN_RANGE then
			actor.Humanoid.WalkSpeed = 18 + actor.Zone
			PlayLocomotion(actor, "Run")
		else
			actor.Humanoid.WalkSpeed = 10 + actor.Zone
			PlayLocomotion(actor, "Walk")
		end
		actor.Humanoid:MoveTo(nearest.Position)
	else
		actor.Humanoid:MoveTo(actor.Root.Position)
		PlayLocomotion(actor, "Idle")
		combat:TryNPCAttack(actor.Model, nearest.Position - actor.Root.Position)
	end
end

function Mobs.Remove(actor: Actor, combat: CombatApi)
	if actor.StaggerConnection then
		actor.StaggerConnection:Disconnect()
	end
	if actor.DiedConnection then
		actor.DiedConnection:Disconnect()
	end
	for _, track in actor.Animations do
		track:Stop(0)
		track:Destroy()
	end
	combat:UnregisterDungeonMob(actor.Model)
	actor.Model:Destroy()
end

return Mobs

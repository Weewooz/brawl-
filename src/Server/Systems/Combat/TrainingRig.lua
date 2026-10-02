--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Combat.Config)

export type Role = "Blocking" | "Idle" | "Attacking"
export type Service = {
	Start: (self: Service, onSpawn: (Model, Role) -> (), onAttack: (Model, Vector3) -> ()) -> (),
}

type Actor = {
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Label: TextLabel,
}

local TrainingRig = {} :: Service
local Actors: { Blocking: Actor?, Idle: Actor?, Attacking: Actor? } = {}
local Started = false
local TICK = 0.1
local POSITIONS = {
	Blocking = Vector3.new(-20, 3, -15),
	Idle = Vector3.new(0, 3, -15),
	Attacking = Vector3.new(20, 3, -15),
}
local COLORS = {
	Blocking = Color3.fromRGB(69, 122, 205),
	Idle = Color3.fromRGB(99, 147, 99),
	Attacking = Color3.fromRGB(197, 81, 75),
}

local function GetTemplate(): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local rigs = assets and assets:FindFirstChild("Rigs")
	local template = rigs and rigs:FindFirstChild("IncubatorRig")
	if template and template:IsA("Model") then
		return template
	end
	warn("[Combat] Missing authored ReplicatedStorage.Assets.Rigs.IncubatorRig Model; sync the preview asset with Rojo")
	return nil
end

local function GetAnimation(name: string): Animation?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local animations = assets and assets:FindFirstChild("CombatAnimations")
	local animation = animations and animations:FindFirstChild(name)
	if animation and animation:IsA("Animation") then
		return animation
	end
	warn("[Combat] Missing authored Animation at ReplicatedStorage.Assets.CombatAnimations." .. name)
	return nil
end

local function LoadTrack(
	humanoid: Humanoid,
	animation: Animation,
	priority: Enum.AnimationPriority,
	looped: boolean
): AnimationTrack
	local existing = humanoid:FindFirstChildOfClass("Animator")
	local animator = existing or Instance.new("Animator")
	if not existing then
		animator.Parent = humanoid
	end
	local track = animator:LoadAnimation(animation)
	track.Priority = priority
	track.Looped = looped
	if looped then
		track:Play(0.1)
	end
	return track
end

local function ConfigureLabel(model: Model, role: Role): TextLabel?
	local gui = model:FindFirstChild("TrainingLabel")
	local label = gui and gui:FindFirstChild("Label")
	if not gui or not gui:IsA("BillboardGui") or not label or not label:IsA("TextLabel") then
		warn("[Combat] Authored IncubatorRig requires TrainingLabel BillboardGui with a Label TextLabel")
		return nil
	end
	label.BackgroundColor3 = COLORS[role]
	label.Text = string.upper(role)
	return label
end

local function NearestPlayer(position: Vector3): (BasePart?, number)
	local nearest: BasePart? = nil
	local distance = math.huge
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
			local gap = (root.Position - position).Magnitude
			if gap < distance then
				nearest = root
				distance = gap
			end
		end
	end
	return nearest, distance
end

function TrainingRig:Start(onSpawn: (Model, Role) -> (), onAttack: (Model, Vector3) -> ())
	if Started or not RunService:IsStudio() then
		return
	end
	Started = true
	local template = GetTemplate()
	local idle = GetAnimation("Idle")
	local guard = GetAnimation("Guard")
	local impactAnimation = GetAnimation("Impact")
	if not template or not idle or not guard or not impactAnimation then
		return
	end
	local container = Instance.new("Folder")
	container.Name = "TrainingNPCs"
	container.Parent = Workspace

	local function spawn(role: Role)
		local model = template:Clone()
		model.Name = role .. " NPC"
		model:SetAttribute("TrainingRole", role)
		model:SetAttribute("Blocking", role == "Blocking")
		local position = POSITIONS[role]
		model:PivotTo(CFrame.lookAt(position, Vector3.new(0, position.Y, 0)))
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local root = model:FindFirstChild("HumanoidRootPart")
		local label = ConfigureLabel(model, role)
		if not humanoid or not root or not root:IsA("BasePart") or not label then
			model:Destroy()
			warn("[Combat] Authored training rig requires Humanoid, HumanoidRootPart, and TrainingLabel.Label")
			return
		end
		humanoid.DisplayName = role .. " NPC"
		humanoid.MaxHealth = 100
		humanoid.Health = 100
		humanoid.WalkSpeed = 0
		root.Anchored = false
		model.Parent = container
		local actor: Actor = {
			Model = model,
			Humanoid = humanoid,
			Root = root,
			Label = label,
		}
		Actors[role] = actor
		onSpawn(model, role)
		if role == "Blocking" then
			LoadTrack(humanoid, guard, Enum.AnimationPriority.Action, true)
		else
			LoadTrack(humanoid, idle, Enum.AnimationPriority.Idle, true)
		end
		local impact = LoadTrack(humanoid, impactAnimation, Enum.AnimationPriority.Action4, false)
		model:GetAttributeChangedSignal("StaggeredUntil"):Connect(function()
			local untilAt = model:GetAttribute("StaggeredUntil")
			if typeof(untilAt) == "number" and untilAt > Workspace:GetServerTimeNow() and humanoid.Health > 0 then
				impact:Stop(0)
				impact:Play(0.05)
			end
		end)
		humanoid.Died:Connect(function()
			task.delay(Config.TrainingNPC.Respawn, function()
				if Actors[role] == actor then
					Actors[role] = nil
					model:Destroy()
					spawn(role)
				end
			end)
		end)
	end

	for _, role in { "Blocking", "Idle", "Attacking" } do
		spawn(role :: Role)
	end
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < TICK then
			return
		end
		elapsed = 0
		local blocking = Actors.Blocking
		if blocking then
			local blockedAt = blocking.Model:GetAttribute("LastBlockedAt")
			blocking.Label.Text = if typeof(blockedAt) == "number"
					and Workspace:GetServerTimeNow() - blockedAt < 0.6
				then "BLOCKED"
				else "BLOCKING"
		end
		local actor = Actors.Attacking
		if not actor or actor.Humanoid.Health <= 0 then
			return
		end
		local target, distance = NearestPlayer(actor.Root.Position)
		local aim = if target and distance <= Config.TrainingNPC.AttackRange
			then target.Position - actor.Root.Position
			else actor.Root.CFrame.LookVector
		onAttack(actor.Model, aim)
	end)
end

return TrainingRig

--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Animations = require(ReplicatedStorage.Shared.Combat.Animations)
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
local Actors: { [Role]: Actor } = {}
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
	local description = Instance.new("HumanoidDescription")
	description.Head = 10638267973
	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromDescriptionAsync(description, Enum.HumanoidRigType.R15)
	end)
	description:Destroy()
	if not ok then
		warn("[Combat] Incubator training rig unavailable: " .. tostring(result))
		return nil
	end
	return result :: Model
end

local function LoadTrack(
	humanoid: Humanoid,
	animationId: string,
	priority: Enum.AnimationPriority,
	looped: boolean
): AnimationTrack
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local source = Instance.new("Animation")
	source.AnimationId = "rbxassetid://" .. animationId
	local track = animator:LoadAnimation(source)
	source:Destroy()
	track.Priority = priority
	track.Looped = looped
	if looped then
		track:Play(0.1)
	end
	return track
end

local function CreateLabel(model: Model, role: Role): TextLabel
	local head = model:FindFirstChild("Head")
	local gui = Instance.new("BillboardGui")
	gui.Name = "TrainingLabel"
	gui.Adornee = if head and head:IsA("BasePart") then head else model.PrimaryPart
	gui.Size = UDim2.fromOffset(96, 26)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0)
	gui.AlwaysOnTop = true
	gui.Parent = model
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = COLORS[role]
	label.BackgroundTransparency = 0.12
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.45
	label.TextSize = 13
	label.Font = Enum.Font.GothamBold
	label.Text = string.upper(role)
	label.Parent = gui
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
	if not template then
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
		if not humanoid or not root or not root:IsA("BasePart") then
			model:Destroy()
			warn("[Combat] Training rig is missing Humanoid or HumanoidRootPart")
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
			Label = CreateLabel(model, role),
		}
		Actors[role] = actor
		onSpawn(model, role)
		if role == "Blocking" then
			LoadTrack(humanoid, Animations.Melee.Guard, Enum.AnimationPriority.Action, true)
		else
			LoadTrack(humanoid, Animations.Melee.Idle, Enum.AnimationPriority.Idle, true)
		end
		local impact = LoadTrack(humanoid, Animations.Melee.Impact, Enum.AnimationPriority.Action4, false)
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

	for _, role: Role in { "Blocking", "Idle", "Attacking" } do
		spawn(role)
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

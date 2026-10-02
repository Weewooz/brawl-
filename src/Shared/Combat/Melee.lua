--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local ShapeCastHitbox = require(ReplicatedStorage.Packages.ShapeCastHitbox)
ShapeCastHitbox.Settings.Debug_Visible = false
local Config = require(ReplicatedStorage.Shared.Combat.Config)

type Hitbox = ShapeCastHitbox.Hitbox
type State = {
	Hitbox: Hitbox,
	CastContainer: Folder,
	CastParts: { BasePart },
	Points: { Attachment },
	Root: BasePart,
	Humanoid: Humanoid,
	Sword: BasePart,
	Targets: { [Model]: boolean },
	Aim: Vector3,
	OnTarget: ((Model, Vector3, Vector3, BasePart) -> ())?,
	AcceptUntil: number,
	Updating: RBXScriptConnection?,
	Destroying: RBXScriptConnection?,
}

local Melee = {}
local States: { [Model]: State } = {}
local SECTION = 1
local CAST_SIZE = Vector3.new(1, Config.Attack.Height, 1)

local function SetTrail(character: Model, enabled: boolean)
	local weapon = character:FindFirstChild("Katana")
	if not weapon then
		return
	end
	for _, descendant in weapon:GetDescendants() do
		if descendant:IsA("Trail") then
			descendant.Enabled = enabled
		end
	end
end

local function FindTarget(part: BasePart): Model?
	local ancestor: Instance? = part
	while ancestor do
		if ancestor:IsA("Model") and ancestor:FindFirstChildOfClass("Humanoid") then
			return if part.Parent == ancestor then ancestor else nil
		end
		ancestor = ancestor.Parent
	end
	return nil
end

local function UpdateCastParts(state: State, reset: boolean)
	local root = state.Root
	local sword = state.Sword
	local groundY = root.Position.Y - state.Humanoid.HipHeight - root.Size.Y * 0.5
	local centerY = groundY + CAST_SIZE.Y * 0.5
	local blade = sword.CFrame.UpVector
	local flat = Vector3.new(blade.X, 0, blade.Z)
	local axis = if flat.Magnitude > 0.05 then flat.Unit else state.Aim
	for index, part in state.CastParts do
		local offset = -sword.Size.Y * 0.5 + (index - 0.5) * SECTION
		local bladePosition = sword.CFrame:PointToWorldSpace(Vector3.new(0, offset, 0))
		local position = Vector3.new(bladePosition.X, centerY, bladePosition.Z)
		local facing = CFrame.lookAt(position, position + axis)
		local segment = state.Hitbox:GetSegment(state.Points[index])
		if segment then
			segment.CastData._LastCFrameBlockCast = if reset then facing else part.CFrame
		end
		part.CFrame = facing
	end
end

function Melee:Bind(character: Model): boolean
	self:Unbind(character)
	local weapon = character:FindFirstChild("Katana")
	if not weapon or not weapon:IsA("Model") then
		return false
	end
	local sword = weapon:FindFirstChild("Sword")
	if not sword or not sword:IsA("BasePart") then
		return false
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end
	local container = Instance.new("Folder")
	container.Name = character.Name .. "KatanaCasts"
	container.Parent = if RunService:IsServer() then ServerStorage else ReplicatedStorage
	local castParts: { BasePart } = {}
	local points: { Attachment } = {}
	for index = 1, math.ceil(sword.Size.Y / SECTION) do
		local part = Instance.new("Part")
		part.Name = "CastSection" .. index
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Transparency = 1
		part.Size = CAST_SIZE
		part.Parent = container
		local point = Instance.new("Attachment")
		point.Name = "DmgPoint"
		point.Parent = part
		table.insert(castParts, part)
		table.insert(points, point)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { character }
	local hitbox: Hitbox = ShapeCastHitbox.new(container, params)
	if next(hitbox:GetAllSegments()) == nil then
		hitbox:Destroy()
		container:Destroy()
		warn("[Combat] Katana cast sections unavailable for " .. character.Name)
		return false
	end
	hitbox.FilterPartsHit = true
	hitbox:SetResolution(120)
	hitbox:SetCastData({
		CastType = "Blockcast",
		Radius = 0,
		Size = CAST_SIZE,
		CFrame = CFrame.identity,
	})
	local state: State = {
		Hitbox = hitbox,
		CastContainer = container,
		CastParts = castParts,
		Points = points,
		Root = root,
		Humanoid = humanoid,
		Sword = sword,
		Targets = {},
		Aim = Vector3.zAxis,
		OnTarget = nil,
		AcceptUntil = 0,
		Updating = nil,
		Destroying = nil,
	}
	States[character] = state
	UpdateCastParts(state, true)
	state.Updating = RunService.PreSimulation:Connect(function()
		if hitbox.Active then
			UpdateCastParts(state, false)
		end
	end)
	local function tryPart(part: BasePart, position: Vector3)
		if os.clock() > state.AcceptUntil then
			return
		end
		local target = FindTarget(part)
		if not target or target == character or state.Targets[target] then
			return
		end
		state.Targets[target] = true
		local onTarget = state.OnTarget
		if onTarget then
			onTarget(target, state.Aim, position, part)
		end
	end
	hitbox:OnHit(function(result)
		tryPart(result.Instance, result.Position)
	end)
	hitbox:OnUpdate(function()
		for _, castPart in state.CastParts do
			for _, part in Workspace:GetPartBoundsInBox(castPart.CFrame, CAST_SIZE, overlapParams) do
				tryPart(part, castPart.Position)
			end
		end
	end)
	hitbox:OnStopped(function()
		SetTrail(character, false)
	end)
	state.Destroying = character.Destroying:Connect(function()
		self:Unbind(character)
	end)
	return true
end

function Melee:Swing(
	character: Model,
	aim: Vector3,
	duration: number,
	onTarget: (Model, Vector3, Vector3, BasePart) -> ()
): boolean
	local state = States[character]
	if not state or state.Hitbox.Active then
		return false
	end
	state.Aim = aim
	state.OnTarget = onTarget
	state.AcceptUntil = os.clock() + duration + 0.08
	table.clear(state.Targets)
	UpdateCastParts(state, true)
	SetTrail(character, true)
	state.Hitbox:HitStart(duration)
	return true
end

function Melee:Cancel(character: Model)
	local state = States[character]
	if state and state.Hitbox.Active then
		state.Hitbox:HitStop()
	end
	SetTrail(character, false)
end

function Melee:Unbind(character: Model)
	local state = States[character]
	if not state then
		return
	end
	States[character] = nil
	if state.Destroying then
		state.Destroying:Disconnect()
	end
	if state.Updating then
		state.Updating:Disconnect()
	end
	state.Hitbox:Destroy()
	state.CastContainer:Destroy()
	SetTrail(character, false)
end

return Melee

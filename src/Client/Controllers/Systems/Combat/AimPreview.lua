--!strict
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Combat.Config)
local Weapons = require(ReplicatedStorage.Shared.Combat.Weapons)
local GOLD = Color3.fromRGB(245, 210, 135)
local INVALID = Color3.fromRGB(214, 104, 91)
local ARROW_SIZE = Vector3.new(0.25, 0.25, 0.8)

export type System = {
	Model: Model?,
	Parts: { [string]: { BasePart } },
	Landing: BasePart?,
	Path: BasePart?,
	Init: (self: System) -> (),
	Clear: (self: System) -> (),
	Show: (
		self: System,
		name: string,
		character: Model,
		direction: Vector3,
		target: Model?,
		cancelled: boolean,
		aimPosition: Vector3?
	) -> boolean,
}

local Preview: System = { Model = nil, Parts = {}, Landing = nil, Path = nil } :: System
local COUNTS: { [string]: number } = { RisingCrash = 12, GroundShock = 12, Charge = 24 }

local function Destination(character: Model, root: BasePart, target: Model?): (Vector3?, boolean)
	local targetRoot = target and target:FindFirstChild("HumanoidRootPart")
	if not targetRoot or not targetRoot:IsA("BasePart") then
		return nil, false
	end
	local offset = targetRoot.Position - root.Position
	local horizontal = Vector3.new(offset.X, 0, offset.Z)
	if horizontal.Magnitude < 0.1 then
		return targetRoot.Position, false
	end
	local position = targetRoot.Position - horizontal.Unit * math.min(horizontal.Magnitude, Config.Charge.ContactRange)
	local valid = horizontal.Magnitude <= Config.Charge.Range and math.abs(offset.Y) <= 5
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = CollectionService:GetTagged("Combatant")
	params.RespectCanCollide = true
	valid = valid and workspace:Raycast(root.Position, offset, params) == nil
	local ground = workspace:Raycast(position + Vector3.yAxis * 5, -Vector3.yAxis * 12, params)
	if not ground or ground.Normal.Y < 0.65 then
		return position - Vector3.yAxis * 3, false
	end
	local groundY = ground.Position.Y
	local width, depth = math.max(root.Size.X, 2), math.max(root.Size.Z, 2)
	for _, corner in
		{
			Vector3.new(-width * 0.5, 0, -depth * 0.5),
			Vector3.new(width * 0.5, 0, -depth * 0.5),
			Vector3.new(-width * 0.5, 0, depth * 0.5),
			Vector3.new(width * 0.5, 0, depth * 0.5),
		}
	do
		local support = workspace:Raycast(position + corner + Vector3.yAxis * 5, -Vector3.yAxis * 12, params)
		if support then
			groundY = math.max(groundY, support.Position.Y)
		end
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil, false
	end
	local clearance = humanoid.HipHeight + root.Size.Y * 0.5
	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		local leg = character:FindFirstChild("Left Leg")
		clearance += if leg and leg:IsA("BasePart") then leg.Size.Y else 2
	end
	local landing = Vector3.new(position.X, groundY + clearance + 0.1, position.Z)
	valid = valid and math.abs(landing.Y - root.Position.Y) <= 5
	local destination = CFrame.lookAt(landing, landing + horizontal.Unit)
	local height = clearance + root.Size.Y * 0.5 + 2
	local size = Vector3.new(width, height, depth)
	local bodyOffset = CFrame.new(0, height * 0.5 - clearance, 0)
	local rise = Vector3.yAxis * math.max(0, landing.Y - root.Position.Y)
	if rise.Magnitude > 0.01 and workspace:Blockcast(root.CFrame * bodyOffset, size, rise, params) then
		valid = false
	end
	local travel = Vector3.new(landing.X - root.Position.X, 0, landing.Z - root.Position.Z)
	if travel.Magnitude > 0.01 and workspace:Blockcast(root.CFrame * bodyOffset + rise, size, travel, params) then
		valid = false
	end
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { character }
	overlap.RespectCanCollide = true
	valid = valid and #workspace:GetPartBoundsInBox(destination * bodyOffset, size, overlap) == 0
	return Vector3.new(position.X, groundY + 0.08, position.Z), valid
end

local function Arc(parts: { BasePart }, frame: CFrame, radius: number, angle: number, color: Color3)
	local step = angle * 2 / #parts
	for index, part in parts do
		local theta = -angle + (index - 0.5) * step
		local normal = frame.LookVector * math.cos(theta) + frame.RightVector * math.sin(theta)
		local tangent = frame.RightVector * math.cos(theta) - frame.LookVector * math.sin(theta)
		local position = frame.Position + normal * radius
		part.CFrame = CFrame.lookAt(position, position + tangent)
		part.Size = Vector3.new(0.12, 0.06, math.max(0.1, 2 * radius * math.sin(step * 0.5)))
		part.Color = color
		part.Transparency = 0.25
	end
end

local function Hide(preview: System)
	for _, parts in preview.Parts do
		for _, part in parts do
			part.Transparency = 1
		end
	end
	if preview.Landing then
		preview.Landing.Transparency = 1
	end
	if preview.Path then
		preview.Path.Transparency = 1
	end
end

function Preview:Init()
	local model = ReplicatedStorage.Assets:WaitForChild("CombatAimPreview") :: Model
	self.Model = model
	for name, count in COUNTS do
		local parts: { BasePart } = {}
		local folder = model:WaitForChild(name)
		for index = 1, count do
			table.insert(parts, folder:WaitForChild(tostring(index)) :: BasePart)
		end
		self.Parts[name] = parts
	end
	self.Landing = model:WaitForChild("Landing") :: BasePart
	self.Path = model:WaitForChild("Path") :: BasePart
	self:Clear()
end

function Preview:Clear()
	Hide(self)
	if self.Model then
		self.Model.Parent = ReplicatedStorage.Assets
	end
end

function Preview:Show(
	name: string,
	character: Model,
	direction: Vector3,
	target: Model?,
	cancelled: boolean,
	aimPosition: Vector3?
): boolean
	Hide(self)
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not self.Model or not root or not root:IsA("BasePart") or not humanoid then
		return false
	end
	self.Model.Parent = workspace
	local clearance = humanoid.HipHeight + root.Size.Y * 0.5
	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		local leg = character:FindFirstChild("Left Leg")
		clearance += if leg and leg:IsA("BasePart") then leg.Size.Y else 2
	end
	local floor = root.Position - Vector3.yAxis * (clearance - 0.08)
	local color = if cancelled then INVALID else GOLD
	local definition = Weapons.Get(Weapons.Weapon(character))
	if definition and definition.IsRanged then
		local path = self.Path
		if not path then
			return false
		end
		local skill = definition.Skills[name]
		local range = if skill then skill.Range else definition.Range
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = CollectionService:GetTagged("Combatant")
		params.RespectCanCollide = false
		local bow = character:FindFirstChild("Yumi")
		local muzzle = bow and bow:FindFirstChild("Muzzle", true)
		local muzzlePosition = if muzzle and muzzle:IsA("Attachment")
			then muzzle.WorldPosition
			else root.Position + Vector3.yAxis * 0.5 + direction * 1.5
		local origin = muzzlePosition + direction * (ARROW_SIZE.Z * 0.5 + 0.1)
		local hit =
			workspace:Blockcast(CFrame.lookAt(origin, origin + direction), ARROW_SIZE, direction * range, params)
		local distance = if hit then hit.Distance else range
		local height = if aimPosition then aimPosition.Y + 0.04 else floor.Y
		local groundOrigin = Vector3.new(origin.X, height, origin.Z)
		path.CFrame = CFrame.lookAt(groundOrigin + direction * distance * 0.5, groundOrigin + direction * distance)
		path.Size = Vector3.new(if name == "Spin" then 1.4 else 0.16, 0.06, math.max(0.1, distance))
		path.Color = color
		path.Transparency = 0.25
		return not cancelled
	end
	if name == "Charge" then
		local destination, valid = Destination(character, root, target)
		color = if valid and not cancelled then GOLD else INVALID
		if not destination then
			Arc(self.Parts.Charge, CFrame.new(floor), Config.Charge.ContactRange, math.pi, color)
			return false
		end
		Arc(self.Parts.Charge, CFrame.new(destination), 1.4, math.pi, color)
		local landing, path = self.Landing, self.Path
		if landing and path then
			landing.CFrame = CFrame.new(destination)
			landing.Color = color
			landing.Transparency = 0.7
			local offset = destination - floor
			if offset.Magnitude > 0.01 then
				path.CFrame = CFrame.lookAt((floor + destination) * 0.5, destination)
				path.Size = Vector3.new(0.1, 0.05, offset.Magnitude)
				path.Color = color
				path.Transparency = 0.5
			end
		end
		return valid
	end
	local config = if name == "RisingCrash" then Config.RisingCrash else Config.GroundShock
	Arc(self.Parts[name], CFrame.lookAt(floor, floor + direction), config.Range, math.rad(config.HalfAngle), color)
	return true
end

return Preview

--!strict
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Weapons = require(ReplicatedStorage.Shared.Combat.Weapons)
local SkillDefinitions = require(ReplicatedStorage.Shared.Combat.SkillDefinitions)
local Player = Players.LocalPlayer
local INTERVAL = 1 / 30
local GUARD_ANGLE = math.acos(0.2)
local GUARD_RADIUS = 3.5
local COLORS = {
	Local = Color3.fromRGB(255, 211, 107),
	Ally = Color3.fromRGB(98, 194, 255),
	Enemy = Color3.fromRGB(255, 120, 115),
}

type Slot = {
	Model: Model,
	Character: Model?,
	Guard: { BasePart },
	Spin: { BasePart },
	RisingCrash: { BasePart },
	GroundShock: { BasePart },
	Trail: BasePart,
	GuardVisible: boolean,
	SpinVisible: boolean,
	RisingCrashVisible: boolean,
	GroundShockVisible: boolean,
}

export type System = {
	Pool: Folder?,
	Slots: { Slot },
	Elapsed: number,
	Init: (self: System) -> (),
	Step: (self: System, dt: number) -> (),
}

local Telegraphs: System = {} :: System
Telegraphs.Slots = {}
Telegraphs.Elapsed = 0

local function Hide(parts: { BasePart })
	for _, part in parts do
		part.Transparency = 1
	end
end

local function ReadParts(folder: Instance, count: number): { BasePart }
	local parts: { BasePart } = {}
	for index = 1, count do
		local part = folder:WaitForChild(tostring(index))
		assert(part:IsA("BasePart"), "[Combat] Telegraph segment must be a BasePart")
		part.Transparency = 1
		table.insert(parts, part)
	end
	return parts
end

local function Release(slot: Slot, pool: Folder?)
	Hide(slot.Guard)
	Hide(slot.Spin)
	Hide(slot.RisingCrash)
	Hide(slot.GroundShock)
	slot.Trail.Transparency = 1
	slot.GuardVisible = false
	slot.SpinVisible = false
	slot.RisingCrashVisible = false
	slot.GroundShockVisible = false
	slot.Character = nil
	slot.Model.Parent = pool
end

local function Living(character: Model): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	return character.Parent ~= nil
		and character:GetAttribute("CaptureActive") ~= false
		and humanoid ~= nil
		and humanoid.Health > 0
		and root ~= nil
		and root:IsA("BasePart")
end

local function Active(character: Model, name: string, now: number): boolean
	local value = character:GetAttribute(name)
	return typeof(value) == "number" and value > now
end

local function SkillFrame(character: Model, name: string, floor: Vector3, fallback: CFrame): CFrame
	local direction = character:GetAttribute(name .. "Direction")
	if typeof(direction) ~= "Vector3" then
		return fallback
	end
	local horizontal = Vector3.new(direction.X, 0, direction.Z)
	if
		horizontal.Magnitude < 0.001
		or horizontal.Magnitude ~= horizontal.Magnitude
		or horizontal.Magnitude == math.huge
	then
		return fallback
	end
	return CFrame.lookAt(floor, floor + horizontal.Unit)
end

local function Arc(
	parts: { BasePart },
	frame: CFrame,
	radius: number,
	start: number,
	span: number,
	color: Color3,
	transparency: number
)
	local step = span / #parts
	for index, part in parts do
		local angle = start + (index - 0.5) * step
		local normal = frame.LookVector * math.cos(angle) + frame.RightVector * math.sin(angle)
		local tangent = frame.RightVector * math.cos(angle) - frame.LookVector * math.sin(angle)
		local position = frame.Position + normal * radius
		part.CFrame = CFrame.lookAt(position, position + tangent)
		part.Size = Vector3.new(part.Size.X, part.Size.Y, math.max(0.1, 2 * radius * math.sin(step * 0.5)))
		part.Color = color
		part.Transparency = transparency
	end
end

function Telegraphs:Init()
	if self.Pool then
		return
	end
	local pool = ReplicatedStorage.Assets:WaitForChild("CombatTelegraphs") :: Folder
	self.Pool = pool
	for index = 1, 10 do
		local model = pool:WaitForChild(tostring(index)) :: Model
		local trail = model:WaitForChild("Dash") :: BasePart
		trail.Transparency = 1
		table.insert(self.Slots, {
			Model = model,
			Character = nil,
			Guard = ReadParts(model:WaitForChild("Guard"), 12),
			Spin = ReadParts(model:WaitForChild("Spin"), 24),
			RisingCrash = ReadParts(model:WaitForChild("RisingCrash"), 12),
			GroundShock = ReadParts(model:WaitForChild("GroundShock"), 12),
			Trail = trail,
			GuardVisible = false,
			SpinVisible = false,
			RisingCrashVisible = false,
			GroundShockVisible = false,
		})
	end
end

function Telegraphs:Step(dt: number)
	self.Elapsed += dt
	if self.Elapsed < INTERVAL then
		return
	end
	self.Elapsed %= INTERVAL
	for _, slot in self.Slots do
		local character = slot.Character
		if character and (not Living(character) or not CollectionService:HasTag(character, "Combatant")) then
			Release(slot, self.Pool)
		end
	end
	local characters: { Model } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character and Living(character) then
			table.insert(characters, character)
		end
	end
	local npcs: { Model } = {}
	for _, instance in CollectionService:GetTagged("Combatant") do
		if instance:IsA("Model") and not Players:GetPlayerFromCharacter(instance) and Living(instance) then
			table.insert(npcs, instance)
		end
	end
	table.sort(npcs, function(first, second)
		local firstMatch, secondMatch =
			first:GetAttribute("CaptureActive") == true, second:GetAttribute("CaptureActive") == true
		if firstMatch ~= secondMatch then
			return firstMatch
		end
		local origin = if Player.Character then Player.Character:GetPivot().Position else Vector3.zero
		return (first:GetPivot().Position - origin).Magnitude < (second:GetPivot().Position - origin).Magnitude
	end)
	for _, character in npcs do
		table.insert(characters, character)
	end
	local selected: { [Model]: boolean } = {}
	for index, character in characters do
		if index <= #self.Slots then
			selected[character] = true
		end
	end
	for _, slot in self.Slots do
		if slot.Character and not selected[slot.Character] then
			Release(slot, self.Pool)
		end
	end
	for _, character in characters do
		if not selected[character] then
			continue
		end
		local assigned: Slot? = nil
		local available: Slot? = nil
		for _, slot in self.Slots do
			if slot.Character == character then
				assigned = slot
				break
			elseif not slot.Character then
				available = available or slot
			end
		end
		if not assigned and available then
			available.Character = character
			available.Model.Parent = workspace
		end
	end
	local now = workspace:GetServerTimeNow()
	local transparency = if Player:GetAttribute("ReduceFlashes") == true then 0.6 else 0.3
	for _, slot in self.Slots do
		local character = slot.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not character or not humanoid or not root or not root:IsA("BasePart") then
			continue
		end
		local localCharacter = character == Player.Character
		local team = Player:GetAttribute("CaptureTeam")
		local color = if localCharacter
			then COLORS.Local
			elseif team ~= nil and character:GetAttribute("CaptureTeam") == team then COLORS.Ally
			else COLORS.Enemy
		local facing = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
		if facing.Magnitude < 0.01 then
			continue
		end
		local floor = root.Position - Vector3.yAxis * (humanoid.HipHeight + root.Size.Y * 0.5 - 0.08)
		local frame = CFrame.lookAt(floor, floor + facing)
		local guard = localCharacter and character:GetAttribute("Blocking") == true
		if guard then
			Arc(slot.Guard, frame, GUARD_RADIUS, -GUARD_ANGLE, GUARD_ANGLE * 2, color, transparency)
		elseif slot.GuardVisible then
			Hide(slot.Guard)
		end
		slot.GuardVisible = guard
		local katana = Weapons.Weapon(character) == "Katana"
		local spinSkill = SkillDefinitions.Get("WindSpin")
		local risingSkill = SkillDefinitions.Get("RisingCrash")
		local shockSkill = SkillDefinitions.Get("GroundShock")
		local spin = katana and Active(character, "SpinUntil", now)
		if spin and spinSkill then
			Arc(slot.Spin, CFrame.new(floor), spinSkill.Range, 0, math.pi * 2, color, transparency)
		elseif slot.SpinVisible then
			Hide(slot.Spin)
		end
		slot.SpinVisible = spin
		local rising = katana and Active(character, "RisingCrashUntil", now)
		if rising and risingSkill then
			local angle = math.rad(risingSkill.Presentation.HalfAngle or 0)
			Arc(
				slot.RisingCrash,
				SkillFrame(character, "RisingCrash", floor, frame),
				risingSkill.Range,
				-angle,
				angle * 2,
				color,
				transparency
			)
		elseif slot.RisingCrashVisible then
			Hide(slot.RisingCrash)
		end
		slot.RisingCrashVisible = rising
		local shock = katana and Active(character, "GroundShockUntil", now)
		if shock and shockSkill then
			local endsAt = character:GetAttribute("GroundShockUntil") :: number
			local elapsed = shockSkill.Duration - (endsAt - now)
			local winding = elapsed < shockSkill.Windup
			local progress = if winding
				then 1
				else math.clamp((elapsed - shockSkill.Windup) / (shockSkill.Duration - shockSkill.Windup), 0.2, 1)
			local opacity = if winding then math.max(0.6, transparency) else transparency
			local angle = math.rad(shockSkill.Presentation.HalfAngle or 0)
			Arc(
				slot.GroundShock,
				SkillFrame(character, "GroundShock", floor, frame),
				shockSkill.Range * progress,
				-angle,
				angle * 2,
				color,
				opacity
			)
		elseif slot.GroundShockVisible then
			Hide(slot.GroundShock)
		end
		slot.GroundShockVisible = shock
		if katana and Active(character, "ChargeUntil", now) then
			slot.Trail.CFrame = frame * CFrame.new(0, 0, 2)
			slot.Trail.Color = color
			slot.Trail.Transparency = math.min(0.8, transparency + 0.2)
		else
			slot.Trail.Transparency = 1
		end
	end
end

return Telegraphs

--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AudioUtilities = require(ReplicatedStorage.Shared.Utilities.AudioUtilities)
local HighlightPool = ReplicatedStorage.Assets:WaitForChild("CombatHighlightPool")
local Camera = require(script.Parent.Parent.Camera)
local Player = Players.LocalPlayer
local MULTIKILL_WINDOW = 4
local FLASH_DURATION = 0.2
local FLASH_POOL_SIZE = 16
local WEAPON_HIT_CUES: { [string]: { Flesh: string, Metal: string } } = {
	Katana = { Flesh = "KatanaFlesh", Metal = "KatanaMetal" },
}

type FlashSlot = {
	Highlight: Highlight,
	Target: Model?,
	StartedAt: number,
	FillStart: number,
}

export type Feedback = {
	Init: (self: Feedback) -> (),
	Bind: (self: Feedback, character: Model?, root: BasePart?) -> (),
	Play: (self: Feedback, name: string, part: BasePart?, volume: number) -> (),
	Block: (self: Feedback, part: BasePart?, accented: boolean) -> (),
	Flash: (self: Feedback, target: Model, color: Color3, transparency: number) -> (),
	Contact: (self: Feedback, target: Model, hitPart: BasePart, contactAccent: boolean, hitAccent: boolean) -> boolean,
	SkillContact: (self: Feedback, instance: Instance, blocked: boolean) -> (),
	Show: (self: Feedback, kind: string, position: Vector3) -> (),
	Step: (self: Feedback) -> (),
	ClearCharacter: (self: Feedback, character: Model) -> (),
}

local Feedback = {} :: Feedback
local Character: Model? = nil
local Root: BasePart? = nil
local FlashSlots: { FlashSlot } = {}
local LastEliminationAt = -math.huge
local EliminationCount = 0
local LastHeavyAt = -math.huge
local LastSkillContactAt = -math.huge

local function Friendly(target: Model): boolean
	local team = Character and Character:GetAttribute("CaptureTeam") or Player:GetAttribute("CaptureTeam")
	local targetPlayer = Players:GetPlayerFromCharacter(target)
	local targetTeam = target:GetAttribute("CaptureTeam") or (targetPlayer and targetPlayer:GetAttribute("CaptureTeam"))
	return team ~= nil and targetTeam == team
end

function Feedback:Play(name: string, part: BasePart?, volume: number)
	if not part then
		return
	end
	AudioUtilities.PlayAtPart(name, part, volume)
end

local function ImpactKind(target: Model, part: BasePart): string
	local override = part:GetAttribute("CombatImpactMaterial") or target:GetAttribute("CombatImpactMaterial")
	if override == "Metal" or override == "Flesh" then
		return override
	end
	local material = part.Material
	if
		material == Enum.Material.Metal
		or material == Enum.Material.CorrodedMetal
		or material == Enum.Material.DiamondPlate
		or material == Enum.Material.Foil
	then
		return "Metal"
	end
	return "Flesh"
end

local function WeaponHitCue(kind: string): string
	local character = Character
	if character then
		for weaponName, cue in WEAPON_HIT_CUES do
			if character:FindFirstChild(weaponName) then
				return if kind == "Metal" then cue.Metal else cue.Flesh
			end
		end
	end
	return "Hit"
end

local function ReleaseFlash(slot: FlashSlot)
	local highlight = slot.Highlight
	highlight.Enabled = false
	highlight.Adornee = nil
	highlight.Parent = HighlightPool
	slot.Target = nil
end

function Feedback:Flash(target: Model, color: Color3, transparency: number)
	if Player:GetAttribute("ReduceFlashes") == true then
		transparency = math.max(transparency, 0.85)
	end
	local selected: FlashSlot? = nil
	local oldest: FlashSlot? = nil
	for _, slot in FlashSlots do
		if slot.Target == target then
			selected = slot
			break
		end
		if not slot.Target then
			selected = selected or slot
		elseif not oldest or slot.StartedAt < oldest.StartedAt then
			oldest = slot
		end
	end
	local slot = selected or oldest
	if not slot then
		return
	end
	local highlight = slot.Highlight
	slot.Target = target
	slot.StartedAt = os.clock()
	slot.FillStart = transparency
	highlight.FillColor = color
	highlight.FillTransparency = transparency
	highlight.OutlineColor = color
	highlight.OutlineTransparency = if Player:GetAttribute("ReduceFlashes") == true then 1 else 0.45
	highlight.Adornee = target
	highlight.Parent = workspace
	highlight.Enabled = true
end

function Feedback:Step()
	local now = os.clock()
	for _, slot in FlashSlots do
		local target = slot.Target
		if not target then
			continue
		end
		local progress = (now - slot.StartedAt) / FLASH_DURATION
		if progress >= 1 or not target.Parent then
			ReleaseFlash(slot)
		else
			local faded = 1 - (1 - progress) ^ 2
			slot.Highlight.FillTransparency = slot.FillStart + (1 - slot.FillStart) * faded
			slot.Highlight.OutlineTransparency = if Player:GetAttribute("ReduceFlashes") == true
				then 1
				else 0.45 + 0.55 * faded
		end
	end
end

function Feedback:Block(part: BasePart?, accented: boolean)
	Feedback:Play("Block", part, if accented then 0.62 else 0.37)
	Feedback:Play("BlockClank", part, if accented then 0.32 else 0.18)
	if accented then
		Feedback:Play("BodyImpact", part, 0.3)
	end
end

function Feedback:Contact(target: Model, hitPart: BasePart, contactAccent: boolean, hitAccent: boolean): boolean
	if Friendly(target) or target:GetAttribute("CaptureActive") == false then
		return false
	end
	local dashingUntil = target:GetAttribute("DashingUntil")
	if
		Players:GetPlayerFromCharacter(target)
		and typeof(dashingUntil) == "number"
		and dashingUntil > workspace:GetServerTimeNow()
	then
		return false
	end
	local blocked = target:GetAttribute("Blocking") == true
	local cue = if blocked then "Block" else WeaponHitCue(ImpactKind(target, hitPart))
	Feedback:Flash(target, if blocked then Color3.fromRGB(111, 190, 255) else Color3.fromRGB(255, 230, 157), 0.34)
	if blocked then
		Feedback:Block(hitPart, contactAccent)
	else
		Feedback:Play(cue, hitPart, if contactAccent then 0.36 else 0.22)
	end
	if not blocked and hitAccent then
		if cue ~= "Hit" then
			Feedback:Play("BodyImpact", hitPart, if cue == "KatanaMetal" then 0.12 else 0.26)
		end
		Feedback:Play("HitConfirm", Root, 0.09)
	end
	if contactAccent then
		Camera:Shake(if blocked then 0.11 else 0.18, 0.13)
	end
	return not blocked and hitAccent
end

function Feedback:SkillContact(instance: Instance, blocked: boolean)
	if not instance:IsA("Model") or not instance:IsDescendantOf(workspace) or not Root then
		return
	end
	local root = instance:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	Feedback:Flash(instance, if blocked then Color3.fromRGB(111, 190, 255) else Color3.fromRGB(255, 230, 157), 0.34)
	local now = os.clock()
	if now - LastSkillContactAt < 0.04 then
		return
	end
	LastSkillContactAt = now
	if blocked then
		Feedback:Block(root, true)
	else
		local cue = WeaponHitCue(ImpactKind(instance, root))
		Feedback:Play(cue, root, 0.36)
		Feedback:Play("BodyImpact", root, if cue == "KatanaMetal" then 0.12 else 0.26)
		Feedback:Play("HitConfirm", Root, 0.09)
	end
	Camera:Shake(if blocked then 0.11 else 0.18, 0.13)
end

local function PlayHeavy(position: Vector3, volume: number)
	local now = os.clock()
	if now - LastHeavyAt < 0.1 then
		return
	end
	LastHeavyAt = now
	AudioUtilities.PlayAtPosition("HeavyImpact", position, volume)
	Camera:Shake(0.24, 0.16)
end

function Feedback:Show(kind: string, position: Vector3)
	if not Root then
		return
	end
	if kind == "Elimination" then
		local now = os.clock()
		EliminationCount = if now - LastEliminationAt <= MULTIKILL_WINDOW then EliminationCount + 1 else 1
		LastEliminationAt = now
		AudioUtilities.Stop("Elimination")
		AudioUtilities.Stop("MultiKill")
		Feedback:Play(if EliminationCount > 1 then "MultiKill" else "Elimination", Root, 0.36)
		PlayHeavy(position, 0.34)
	elseif kind == "GuardBreak" or kind == "GuardBroken" then
		AudioUtilities.PlayAtPosition("GuardBreak", position, if kind == "GuardBreak" then 0.32 else 0.24)
		PlayHeavy(position, if kind == "GuardBreak" then 0.3 else 0.18)
		if kind == "GuardBreak" then
			Feedback:Play("HitConfirm", Root, 0.12)
		end
	elseif kind == "HeavyHit" then
		PlayHeavy(position, 0.42)
	elseif kind == "PerfectGuard" and Character then
		Feedback:Flash(Character, Color3.fromRGB(255, 224, 143), 0.3)
		Feedback:Play("BlockClank", Root, 0.3)
		Feedback:Play("HitConfirm", Root, 0.13)
		Camera:Shake(0.2, 0.13)
	elseif kind == "GuardParried" then
		Camera:Shake(0.12, 0.12)
	end
end

function Feedback:Init()
	for index = 1, FLASH_POOL_SIZE do
		local highlight = HighlightPool:WaitForChild(tostring(index))
		if highlight:IsA("Highlight") then
			highlight.Enabled = false
			highlight.Adornee = nil
			highlight.DepthMode = Enum.HighlightDepthMode.Occluded
			table.insert(FlashSlots, { Highlight = highlight, Target = nil, StartedAt = 0, FillStart = 1 })
		end
	end
end

function Feedback:Bind(character: Model?, root: BasePart?)
	Character = character
	Root = root
end

function Feedback:ClearCharacter(character: Model)
	for _, slot in FlashSlots do
		if slot.Target == character then
			ReleaseFlash(slot)
		end
	end
	LastEliminationAt = -math.huge
	EliminationCount = 0
	LastHeavyAt = -math.huge
	AudioUtilities.Stop("Elimination")
	AudioUtilities.Stop("MultiKill")
end

return Feedback

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Katana = {}

local function GetTemplate(): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local weapons = assets and assets:FindFirstChild("Weapons")
	local template = weapons and weapons:FindFirstChild("Katana")
	if not template or not template:IsA("Model") then
		warn(
			"[Combat] Missing authored ReplicatedStorage.Assets.Weapons.Katana Model; sync the preview asset with Rojo"
		)
		return nil
	end
	local handle = template:FindFirstChild("Handle")
	local sword = template:FindFirstChild("Sword")
	if
		not handle
		or not handle:IsA("BasePart")
		or template.PrimaryPart ~= handle
		or not sword
		or not sword:IsA("BasePart")
	then
		warn("[Combat] Authored Katana requires Handle as PrimaryPart and a Sword BasePart")
		return nil
	end
	return template
end

function Katana.Prepare(): boolean
	return GetTemplate() ~= nil
end

function Katana.Equip(character: Model): boolean
	local hand = character:FindFirstChild("RightHand")
	if not hand or not hand:IsA("BasePart") then
		return false
	end
	local template = GetTemplate()
	if not template then
		return false
	end
	local previous = character:FindFirstChild("Katana")
	if previous then
		previous:Destroy()
	end
	local previousMotor = hand:FindFirstChild("KatanaGrip")
	if previousMotor then
		previousMotor:Destroy()
	end
	local weapon = template:Clone()
	local handle = weapon.PrimaryPart
	if not handle then
		weapon:Destroy()
		return false
	end
	weapon:PivotTo(hand.CFrame)
	weapon.Parent = character
	local motor = Instance.new("Motor6D")
	motor.Name = "KatanaGrip"
	motor.Part0 = hand
	motor.Part1 = handle
	motor.C0 = CFrame.identity
	motor.C1 = CFrame.identity
	motor.Parent = hand
	return true
end

function Katana.SetTrail(character: Model, enabled: boolean)
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

return Katana

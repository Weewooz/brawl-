--!strict
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Katana = {}

local MESH = "rbxassetid://13662643071"
local TEXTURE = "rbxassetid://13662522227"
local BLADE_SIZE = Vector3.new(0.42067757, 4.67618608, 0.39863265)
local BLADE_OFFSET =
	CFrame.fromMatrix(Vector3.new(-0.02148628, -0.05861545, -1.71557236), Vector3.yAxis, -Vector3.zAxis, -Vector3.xAxis)

local function AddTrail(
	sword: MeshPart,
	first: Attachment,
	last: Attachment,
	name: string,
	texture: string,
	color: Color3
)
	local trail = Instance.new("Trail")
	trail.Name = name
	trail.Attachment0 = first
	trail.Attachment1 = last
	trail.Texture = texture
	trail.Color = ColorSequence.new(color)
	trail.Lifetime = 0.1
	trail.Enabled = false
	trail.Parent = sword
end

local function Build(): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		return nil
	end
	local weapons = assets:FindFirstChild("Weapons")
	if not weapons then
		weapons = Instance.new("Folder")
		weapons.Name = "Weapons"
		weapons.Parent = assets
	end
	local existing = weapons:FindFirstChild("Katana")
	if existing and existing:IsA("Model") then
		return existing
	end

	local ok, result = pcall(function()
		return AssetService:CreateMeshPartAsync(Content.fromUri(MESH))
	end)
	if not ok then
		warn("[Combat] Incubator katana mesh unavailable: " .. tostring(result))
		return nil
	end
	local sword = result :: MeshPart
	sword.Name = "Sword"
	sword.Size = BLADE_SIZE
	sword.TextureID = TEXTURE
	sword.CanCollide = false
	sword.CanTouch = false
	sword.CanQuery = false
	sword.Massless = true
	sword.CastShadow = false
	sword.CFrame = BLADE_OFFSET

	local first = Instance.new("Attachment")
	first.Name = "TrailTip"
	first.Position = Vector3.new(-0.12395477, 2.26144409, 0)
	first.Parent = sword
	local last = Instance.new("Attachment")
	last.Name = "TrailBase"
	last.Position = Vector3.new(-0.01023579, -0.91255188, 0)
	last.Parent = sword
	AddTrail(sword, first, last, "Trail", "rbxassetid://9035801067", Color3.fromRGB(121, 121, 121))
	AddTrail(sword, first, last, "Trail2", "rbxassetid://9035800962", Color3.new(1, 1, 1))
	AddTrail(sword, first, last, "Trail3", "rbxassetid://9035819980", Color3.fromRGB(94, 94, 94))

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.one
	handle.Transparency = 1
	handle.CanCollide = false
	handle.CanTouch = false
	handle.CanQuery = false
	handle.Massless = true
	handle.CastShadow = false
	handle.CFrame = CFrame.identity
	local weld = Instance.new("WeldConstraint")
	weld.Name = "HandleWeld"
	weld.Part0 = handle
	weld.Part1 = sword
	weld.Parent = handle

	local model = Instance.new("Model")
	model.Name = "Katana"
	model.PrimaryPart = handle
	handle.Parent = model
	sword.Parent = model
	model.Parent = weapons
	return model
end

function Katana.Prepare(): boolean
	return Build() ~= nil
end

function Katana.Equip(character: Model): boolean
	local hand = character:FindFirstChild("RightHand")
	if not hand or not hand:IsA("BasePart") then
		return false
	end
	local template = Build()
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

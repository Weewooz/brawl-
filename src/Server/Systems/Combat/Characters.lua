--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Profile = require(ServerScriptService.Systems.Profile)
local Config = require(ReplicatedStorage.Shared.Combat.Config)
local Weapons = require(ReplicatedStorage.Shared.Combat.Weapons)
local Melee = require(ReplicatedStorage.Shared.Combat.Melee)
local Status = require(script.Parent.Status)
local Katana = require(script.Parent.Katana)
local Yumi = require(script.Parent.Yumi)
local Skills = require(script.Parent.Skills)
local Attacks = require(script.Parent.Attacks)

export type API = {
	Init: (self: API) -> (),
	BindPlayers: (self: API) -> (),
	EquipWeapon: (self: API, player: Player, id: string) -> boolean,
	SetGrit: (self: API, player: Player, value: number) -> boolean,
}

local Characters = {} :: API
local GritByPlayer: { [Player]: number } = {}
local WeaponByPlayer: { [Player]: Weapons.Id } = {}
local SelectionAt: { [Player]: number } = {}

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

local function EquipCharacter(character: Model, id: Weapons.Id): boolean
	local equipped = if id == "Yumi" then Yumi:Equip(character) else Katana.Equip(character)
	if not equipped then
		return false
	end
	Yumi:Cancel(character)
	Skills.Cancel(character)
	Attacks:Clear(character)
	Melee:Unbind(character)
	local previous = if id == "Yumi" then "Katana" else "Yumi"
	local model = character:FindFirstChild(previous)
	if model then
		model:Destroy()
	end
	for _, name in { "LeftHand", "RightHand" } do
		local hand = character:FindFirstChild(name)
		local grip = hand and hand:FindFirstChild(previous .. "Grip")
		if grip then
			grip:Destroy()
		end
	end
	character:SetAttribute("Weapon", id)
	return true
end

local function AttachCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	Status.Attach(character)
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		Status.SetGrit(character, GritByPlayer[player] or 0)
	end
	character:SetAttribute("AttackReadyAt", 0)
	character:SetAttribute("DashReadyAt", 0)
	character:SetAttribute("SpinReadyAt", 0)
	character:SetAttribute("ChargeReadyAt", 0)
	character:SetAttribute("RisingCrashReadyAt", 0)
	character:SetAttribute("GroundShockReadyAt", 0)
	character:SetAttribute("StrikeIndex", 0)
	character.Destroying:Connect(function()
		Attacks:Clear(character)
		Skills.Cancel(character)
		Yumi:Cancel(character)
	end)
	humanoid.Died:Connect(function()
		Attacks:Clear(character)
		Skills.Cancel(character)
		Yumi:Cancel(character)
		Status.ClearEffects(character)
	end)
	character:WaitForChild("RightHand", 5)
	character:WaitForChild("LeftHand", 5)
	if player and player.Character ~= character then
		return
	end
	local profile = if player and Profile:IsLoaded(player) then Profile:Get(player) else nil
	local saved: Weapons.Id = if profile and profile.Combat.Weapon == "Yumi" then "Yumi" else "Katana"
	local id: Weapons.Id = if player then WeaponByPlayer[player] or saved else "Katana"
	if not EquipCharacter(character, id) then
		warn("[Combat] Could not equip " .. id .. " for " .. character.Name)
	end
end

function Characters:EquipWeapon(player: Player, id: string): boolean
	local now = Workspace:GetServerTimeNow()
	if now < (SelectionAt[player] or 0) then
		return false
	end
	SelectionAt[player] = now + 0.5
	local definition = Weapons.Get(id)
	if not definition then
		player:SetAttribute("WeaponMessage", "Unknown weapon discipline")
		return false
	end
	local character = player.Character
	if
		not Weapons.CanEquip(
			player:GetAttribute("CaptureStatus") :: string?,
			player:GetAttribute("DungeonRunId") ~= nil
		)
	then
		player:SetAttribute("WeaponMessage", "Leave the queue or activity to change weapons")
		return false
	end
	local humanoid = GetLiving(character)
	if
		not character
		or not humanoid
		or not Status.CanAct(character)
		or Status.Busy(character)
		or Status.Dashing(character)
	then
		player:SetAttribute("WeaponMessage", "Finish your action before changing weapons")
		return false
	end
	if not Profile:IsLoaded(player) then
		player:SetAttribute("WeaponMessage", "Your character is still loading")
		return false
	end
	local weapon: Weapons.Id = id :: Weapons.Id
	if character:GetAttribute("Weapon") == weapon and character:FindFirstChild(weapon) then
		player:SetAttribute("WeaponMessage", "")
		return true
	end
	if not EquipCharacter(character, weapon) then
		player:SetAttribute("WeaponMessage", "Weapon asset unavailable; try again")
		return false
	end
	WeaponByPlayer[player] = weapon
	Profile:Update(player, "Combat", "Weapon", weapon)
	player:SetAttribute("Weapon", weapon)
	player:SetAttribute("WeaponMessage", "")
	return true
end

function Characters:SetGrit(player: Player, value: number): boolean
	if typeof(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
		return false
	end
	local profile = Profile:Get(player)
	if not profile then
		return false
	end
	local grit = math.clamp(value, 0, Config.Stagger.GritMax)
	Profile:Update(player, "Combat", "Grit", grit)
	GritByPlayer[player] = grit
	local character = player.Character
	if character then
		Status.SetGrit(character, grit)
	end
	return true
end

function Characters:Init()
	Profile.Loaded:Connect(function(player, profile)
		local savedGrit = profile.Combat.Grit
		local grit = if typeof(savedGrit) == "number"
				and savedGrit == savedGrit
				and math.abs(savedGrit) < math.huge
			then math.clamp(savedGrit, 0, Config.Stagger.GritMax)
			else 0
		GritByPlayer[player] = grit
		local savedWeapon = profile.Combat.Weapon
		local weapon: Weapons.Id = if savedWeapon == "Yumi" then "Yumi" else "Katana"
		WeaponByPlayer[player] = weapon
		player:SetAttribute("Weapon", weapon)
		local character = player.Character
		if character then
			Status.SetGrit(character, grit)
			if character:FindFirstChild("RightHand") and character:FindFirstChild("LeftHand") then
				EquipCharacter(character, weapon)
			end
		end
	end)
	Profile.Releasing:Connect(function(player)
		GritByPlayer[player] = nil
		WeaponByPlayer[player] = nil
		SelectionAt[player] = nil
	end)
end

function Characters:BindPlayers()
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			task.spawn(AttachCharacter, character)
		end)
		if player.Character then
			task.spawn(AttachCharacter, player.Character)
		end
	end)
	for _, player in Players:GetPlayers() do
		if player.Character then
			task.spawn(AttachCharacter, player.Character)
		end
		player.CharacterAdded:Connect(function(character)
			task.spawn(AttachCharacter, character)
		end)
	end
end

return Characters

--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Server = require(ReplicatedStorage.Shared.Network.Server)

export type Entry = { Source: string, Skill: string, Damage: number, Effect: string, At: number }
local Team = {}
local Damage: { [Model]: { Entry } } = setmetatable({}, { __mode = "k" }) :: any
local Requests: { [Player]: number } = {}
local KINDS: { [string]: boolean } = { Attack = true, Defend = true, Regroup = true }
local WINDOW = 12

function Team.Record(attacker: Model, target: Model, amount: number, skill: string, effect: string)
	if not Players:GetPlayerFromCharacter(target) then
		return
	end
	local now = Workspace:GetServerTimeNow()
	local entries = Damage[target] or {}
	local source = Players:GetPlayerFromCharacter(attacker)
	local humanoid = attacker:FindFirstChildOfClass("Humanoid")
	while #entries > 0 and now - entries[1].At > WINDOW do
		table.remove(entries, 1)
	end
	table.insert(entries, {
		Source = if source
			then source.DisplayName
			elseif humanoid and humanoid.DisplayName ~= "" then humanoid.DisplayName
			else attacker.Name,
		Skill = skill,
		Damage = math.round(amount * 10) / 10,
		Effect = effect,
		At = now,
	})
	while #entries > 4 do
		table.remove(entries, 1)
	end
	Damage[target] = entries
end

function Team.Recap(target: Model)
	local player = Players:GetPlayerFromCharacter(target)
	if player then
		Server.Combat.DeathRecap.Fire(player, Damage[target] or {})
	end
	Damage[target] = nil
end

function Team.Clear(target: Model)
	Damage[target] = nil
end

function Team.Ping(player: Player, kind: string, requested: Vector3): boolean
	local now = Workspace:GetServerTimeNow()
	if not KINDS[kind] or (Requests[player] or 0) > now then
		return false
	end
	Requests[player] = now + 1.5
	local state = ReplicatedStorage:FindFirstChild("CaptureState")
	local phase = state and state:GetAttribute("Phase")
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local team = player:GetAttribute("CaptureTeam")
	if
		player:GetAttribute("CaptureStatus") ~= "Playing"
		or not state
		or (phase ~= "Active" and phase ~= "Overtime")
		or not character
		or character:GetAttribute("CaptureActive") ~= true
		or not root
		or not root:IsA("BasePart")
		or not humanoid
		or humanoid.Health <= 0
		or (team ~= "Azure" and team ~= "Coral")
		or character:GetAttribute("CaptureTeam") ~= team
		or player:GetAttribute("CaptureRound") ~= state:GetAttribute("Round")
		or typeof(requested) ~= "Vector3"
	then
		return false
	end
	for _, component in { requested.X, requested.Y, requested.Z } do
		if component ~= component or math.abs(component) >= 100000 then
			return false
		end
	end
	local arena = Workspace:FindFirstChild("CaptureArena")
	local point = arena and arena:FindFirstChild("Point")
	if not point or not point:IsA("BasePart") then
		return false
	end
	-- Objective pings always resolve to the authoritative point; regroup resolves to the sender.
	local position = if kind == "Regroup" then root.Position else point.Position
	if (requested - position).Magnitude > 8 then
		return false
	end
	local round = player:GetAttribute("CaptureRound")
	for _, member in Players:GetPlayers() do
		if
			member:GetAttribute("CaptureStatus") == "Playing"
			and member:GetAttribute("CaptureTeam") == team
			and member:GetAttribute("CaptureRound") == round
		then
			Server.Capture.Pinged.Fire(member, kind, position, player.DisplayName, now + 3)
		end
	end
	return true
end

function Team.Init()
	Server.Capture.Ping.On(Team.Ping)
	Players.PlayerRemoving:Connect(function(player)
		Requests[player] = nil
	end)
end

return Team

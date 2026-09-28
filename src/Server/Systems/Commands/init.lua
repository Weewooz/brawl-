--!strict
--[[
	Commands — Cmdr console for developers.

	Studio always allowed; live requires configured group rank.
	Client opens with F2 (Controllers.Systems.Commands).

	Custom commands live in Client/ (defs) and Server/ (runs).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TeleportService = game:GetService("TeleportService")

local Cmdr = require(ServerScriptService.ServerPackages.Cmdr)

local RESTART = "Restart"
local Restart = {
	Gather = 4, -- Seconds for a restart reserved server to collect players
	Kick = 10, -- Seconds after public hop before kicking leftovers
}

export type System = {
	Init: (self: System) -> (),
	Start: (self: System) -> (),
}

-- Replace with your group / allowlist before shipping live commands
local CommandPermissionGroup = {
	Id = 0, -- Roblox group id
	Rank = 255,
}
local ALWAYS_ALLOWED_USER_ID = 0 -- Extra UserId always allowed (0 = none)

local System = {} :: System

local function Allowed(player: Player): boolean
	if ALWAYS_ALLOWED_USER_ID ~= 0 and player.UserId == ALWAYS_ALLOWED_USER_ID then
		return true
	end

	if RunService:IsStudio() then
		return true
	end

	if CommandPermissionGroup.Id == 0 then
		return false
	end

	local success, rank = pcall(function()
		return player:GetRankInGroup(CommandPermissionGroup.Id)
	end)
	return success and rank >= CommandPermissionGroup.Rank
end

Cmdr:RegisterHook("BeforeRun", function(context): string?
	if not Allowed(context.Executor) then
		return "You don't have permission to run this command."
	end
	return nil
end)

local function Register()
	local client = script:WaitForChild("Client")
	local server = script:WaitForChild("Server")

	for _, definition in client:GetChildren() do
		if not definition:IsA("ModuleScript") then
			continue
		end

		local sibling = server:FindFirstChild(definition.Name)
		local run = if sibling and sibling:IsA("ModuleScript") then sibling else nil
		Cmdr:RegisterCommand(definition, run)
	end
end

local function IsRestart(player: Player): boolean
	local data = player:GetJoinData().TeleportData
	return type(data) == "table" and data.Kind == RESTART
end

local function HopPublic(players: { Player })
	if #players == 0 then
		return
	end

	local options = Instance.new("TeleportOptions")
	options.ShouldReserveServer = false
	options:SetTeleportData({ Kind = "Restarted" })

	local ok, err = pcall(function()
		TeleportService:TeleportAsync(game.PlaceId, players, options)
	end)
	if not ok then
		warn(`[RestartServer] Public hop failed: {err}`)
	end
end

local function FlushRestart()
	if game.PrivateServerId == "" or RunService:IsStudio() then
		return
	end

	local hopped = false
	local generation = 0

	local function Flush()
		local batch = {}
		for _, player in Players:GetPlayers() do
			if IsRestart(player) then
				table.insert(batch, player)
			end
		end
		if #batch == 0 then
			return
		end

		hopped = true
		HopPublic(batch)

		task.delay(Restart.Kick, function()
			for _, player in Players:GetPlayers() do
				player:Kick("Server restarting. Rejoin the game.")
			end
		end)
	end

	local function Consider(player: Player)
		if not IsRestart(player) then
			return
		end
		if hopped then
			HopPublic({ player })
			return
		end

		generation += 1
		local current = generation
		task.delay(Restart.Gather, function()
			if current ~= generation then
				return
			end
			Flush()
		end)
	end

	Players.PlayerAdded:Connect(Consider)
	for _, player in Players:GetPlayers() do
		Consider(player)
	end
end

function System:Init()
	Cmdr:RegisterDefaultCommands()
	Cmdr:RegisterTypesIn(script:WaitForChild("Types"))
	Register()
end

function System:Start()
	FlushRestart()
end

return System

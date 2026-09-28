--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TeleportService = game:GetService("TeleportService")

local Notifications = require(ServerScriptService.Systems.Notifications)

local KIND = "Restart"
local Delay = {
	Warn = 3, -- Seconds players see the restart warning
	Kick = 10, -- Seconds after teleport before kicking leftovers
	Max = 30,
}

local function Migrate(players: { Player })
	if #players == 0 then
		return
	end

	local options = Instance.new("TeleportOptions")
	options.ShouldReserveServer = true
	options:SetTeleportData({ Kind = KIND })

	local ok, err = pcall(function()
		TeleportService:TeleportAsync(game.PlaceId, players, options)
	end)
	if not ok then
		warn(`[RestartServer] Teleport failed: {err}`)
		return
	end

	task.delay(Delay.Kick, function()
		for _, player in Players:GetPlayers() do
			player:Kick("Server restarting. Rejoin the game.")
		end
	end)
end

return function(_context, delay: number?)
	if RunService:IsStudio() then
		return "Cannot teleport to a new server from Studio."
	end

	local countdown = math.clamp(delay or Delay.Warn, 0, Delay.Max)
	local players = Players:GetPlayers()
	if #players == 0 then
		return "No players to teleport."
	end

	Notifications:ShowAll("Server is restarting. Teleporting to a new server...", {
		Tone = "Warning",
		Duration = math.max(countdown, 4),
	})

	task.delay(countdown, function()
		Migrate(Players:GetPlayers())
	end)

	return `Restarting. Teleporting {#players} player(s) in {countdown} seconds.`
end

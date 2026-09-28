--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = require(ReplicatedStorage.Shared.Network.Server)

export type System = {
	Cache: { [Player]: number },
	Init: (self: System) -> (),
	Start: (self: System) -> (),
	Get: (self: System, player: Player) -> number?,
}

local System = {} :: System
System.Cache = {}

function System:Init()
	Players.PlayerRemoving:Connect(function(player)
		System.Cache[player] = nil
	end)

	Server.Latency.Pong.On(function(player, sent)
		if typeof(sent) ~= "number" then
			return
		end

		System.Cache[player] = math.floor(player:GetNetworkPing() * 1000)
		Server.Latency.Ping.Fire(player, sent)
	end)
end

function System:Start() end

function System:Get(player: Player): number?
	return self.Cache[player]
end

return System

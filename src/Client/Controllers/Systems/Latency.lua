--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = require(ReplicatedStorage.Shared.Network.Client)

local INTERVAL = 1 -- Seconds between ping samples

export type System = {
	Init: (self: System) -> (),
	Start: (self: System) -> (),
}

local System = {} :: System

function System:Init() end

function System:Start()
	while true do
		Client.Latency.Pong.Fire(os.clock())
		task.wait(INTERVAL)
	end
end

return System

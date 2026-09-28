--!strict
-- Automatically reconnects the player to the game after they're detected as idling for too long
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Client = require(ReplicatedStorage.Shared.Network.Client)

type Character = Model & { Humanoid: Humanoid, HumanoidRootPart: BasePart }
type ReconnectData = { [string]: any }

export type System = {
	Init: (self: System) -> (),
	Start: (self: System) -> (),
	AddReconnectingCallback: (self: System, callback: (reconnectData: ReconnectData) -> ()) -> (),
}

local System = {} :: System
local Player = Players.LocalPlayer

local SECONDS_IN_MINUTE = 60
local RECONNECT_TIMER = 18 * SECONDS_IN_MINUTE
local DEBUG_ENABLED = false
local DEBUG_RECONNECT_TIMER = 10

local ReconnectingCallbacks: { (reconnectData: ReconnectData) -> () } = {}

local function LoadReconnectState(reconnectData: ReconnectData)
	local character = Player.Character :: Character?
	local camera = workspace.CurrentCamera :: Camera
	if character and character.PrimaryPart and character.Humanoid.Health > 0 and reconnectData.CharacterPosition then
		character.HumanoidRootPart.CFrame = CFrame.new(reconnectData.CharacterPosition)
		camera.CFrame = reconnectData.CameraCFrame
	end
end

local function RequestReconnect()
	local reconnectData: ReconnectData = {}
	for _, callback in ReconnectingCallbacks do
		callback(reconnectData)
	end
	Client.Reconnection.Request.Fire((workspace.CurrentCamera :: Camera).CFrame, reconnectData)
end

local function OnReconnected(reconnectData: ReconnectData)
	local character = Player.Character or Player.CharacterAdded:Wait()
	character:WaitForChild("Humanoid")

	task.wait(0.25)
	LoadReconnectState(reconnectData)
end

function System:Init()
	Player.Idled:Connect(function(time)
		if not RunService:IsStudio() and time > RECONNECT_TIMER then
			RequestReconnect()
		end
	end)

	if DEBUG_ENABLED then
		warn(`DEBUG: Force reconnecting in {DEBUG_RECONNECT_TIMER} seconds...`)
		task.delay(DEBUG_RECONNECT_TIMER, RequestReconnect)
	end

	Client.Reconnection.Reconnected.On(OnReconnected)
end

function System:Start() end

function System:AddReconnectingCallback(callback: (reconnectData: ReconnectData) -> ())
	table.insert(ReconnectingCallbacks, callback)
end

return System

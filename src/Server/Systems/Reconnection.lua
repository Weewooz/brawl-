--!strict
-- Automatically reconnects the player to the game after they're detected as idling for too long
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local Server = require(ReplicatedStorage.Shared.Network.Server)

type ReconnectData = { [string]: any }

export type System = {
	Init: (self: System) -> (),
	Start: (self: System) -> (),
	AddReconnectingCallback: (self: System, callback: (player: Player, reconnectData: ReconnectData) -> ()) -> (),
}

local System = {} :: System
local ReconnectingCallbacks: { (player: Player, reconnectData: ReconnectData) -> () } = {}

local function SerializeCFrame(cframe: CFrame)
	return { cframe:GetComponents() }
end

local function UnserializeCFrame(serializedCFrame: { number })
	return CFrame.new(unpack(serializedCFrame))
end

local function SanitizePayload(cameraCFrame: CFrame, options: { [string]: any }): ({ number }, { [string]: any })
	local sanitizedOptions = {}
	if typeof(cameraCFrame) ~= "CFrame" then
		cameraCFrame = CFrame.new()
	end
	return SerializeCFrame(cameraCFrame), sanitizedOptions
end

local function SendReconnectData(player: Player)
	local teleportData = player:GetJoinData().TeleportData :: ReconnectData?
	if teleportData and teleportData.Reconnecting then
		local reconnectData: ReconnectData = {
			Options = teleportData.Options,
			CharacterPosition = Vector3.new(unpack(teleportData.CharacterPosition)),
			CameraCFrame = UnserializeCFrame(teleportData.CameraCFrame),
		}
		for key, value in teleportData do
			if not reconnectData[key] then
				reconnectData[key] = value
			end
		end

		Server.Reconnection.Reconnected.Fire(player, reconnectData)
	end
end

local function Reconnect(player: Player, cameraCFrame: CFrame, reconnectData: ReconnectData)
	local lastReconnectTime = (player:GetAttribute("ReconnectAttemptTime") or 0) :: number
	if (workspace:GetServerTimeNow() - lastReconnectTime) <= 15 then
		return
	end

	player:SetAttribute("ReconnectAttemptTime", workspace:GetServerTimeNow())

	local characterPosition = player.Character and player.Character:GetPivot().Position or nil
	local teleportOptions = Instance.new("TeleportOptions")
	local serializedCFrame, options = SanitizePayload(cameraCFrame, {})

	reconnectData = reconnectData or {}
	for _, callback in ReconnectingCallbacks do
		callback(player, reconnectData)
	end

	reconnectData.Reconnecting = true
	reconnectData.Options = options
	reconnectData.CharacterPosition = characterPosition
		and {
			characterPosition.X,
			characterPosition.Y,
			characterPosition.Z,
		}
	reconnectData.CameraCFrame = serializedCFrame

	teleportOptions:SetTeleportData(reconnectData)
	teleportOptions.ShouldReserveServer = true

	TeleportService:TeleportAsync(game.PlaceId, { player }, teleportOptions)
end

local function OnPlayerAdded(player: Player)
	local teleportData = player:GetJoinData().TeleportData :: ReconnectData?
	if not teleportData or not teleportData.Reconnecting then
		return
	end

	if game.PrivateServerId ~= "" then
		local teleportOptions = Instance.new("TeleportOptions")
		teleportOptions:SetTeleportData(teleportData)
		teleportOptions.ShouldReserveServer = false

		TeleportService:TeleportAsync(game.PlaceId, { player }, teleportOptions)
	else
		SendReconnectData(player)
	end
end

function System:Init()
	Server.Reconnection.Request.On(Reconnect)
	Players.PlayerAdded:Connect(OnPlayerAdded)
end

function System:Start()
	for _, player in Players:GetPlayers() do
		task.spawn(OnPlayerAdded, player)
	end
end

function System:AddReconnectingCallback(callback: (player: Player, reconnectData: ReconnectData) -> ())
	table.insert(ReconnectingCallbacks, callback)
end

return System

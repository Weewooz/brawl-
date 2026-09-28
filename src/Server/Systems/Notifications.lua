--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = require(ReplicatedStorage.Shared.Network.Server)

export type Tone = "Normal" | "Warning" | "Casual"
export type NotificationOptions = {
	Tone: Tone?,
	Duration: number?,
}

export type System = {
	Init: (self: System) -> (),
	Start: (self: System) -> (),
	Show: (self: System, player: Player, message: string, options: NotificationOptions?) -> (),
	ShowAll: (self: System, message: string, options: NotificationOptions?) -> (),
}

local DEFAULT_DURATION = 4
local MINIMUM_DURATION = 1
local MAXIMUM_DURATION = 15
local TONES: { [Tone]: number } = {
	Normal = 0,
	Warning = 1,
	Casual = 2,
}

local System = {} :: System

local function GetArguments(message: string, options: NotificationOptions?): (string, number, number)
	local notificationOptions: NotificationOptions = options or {}
	local tone: Tone = notificationOptions.Tone or "Normal"
	local duration = math.clamp(notificationOptions.Duration or DEFAULT_DURATION, MINIMUM_DURATION, MAXIMUM_DURATION)
	return message, TONES[tone], duration
end

function System:Show(player: Player, message: string, options: NotificationOptions?)
	if message == "" then
		return
	end

	Server.Notifications.Show.Fire(player, GetArguments(message, options))
end

function System:ShowAll(message: string, options: NotificationOptions?)
	if message == "" then
		return
	end

	Server.Notifications.Show.FireAll(GetArguments(message, options))
end

function System:Init() end

function System:Start() end

return System

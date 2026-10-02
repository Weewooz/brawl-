--!strict
local Players = game:GetService("Players")

export type System = {
	Init: (self: System) -> (),
	Start: (self: System) -> (),
}

local System = {} :: System
local Player = Players.LocalPlayer

local ATTRIBUTES = {
	"DungeonState",
	"DungeonZone",
	"DungeonWave",
	"DungeonDifficulty",
	"DungeonPartySize",
	"DungeonMessage",
}

local Gui: ScreenGui?
local Status: TextLabel?
local Details: TextLabel?
local Message: TextLabel?

local function ReadString(name: string): string?
	local value = Player:GetAttribute(name)
	return if typeof(value) == "string" then value else nil
end

local function ReadNumber(name: string): number?
	local value = Player:GetAttribute(name)
	return if typeof(value) == "number" then value else nil
end

local function Sync()
	local gui = Gui
	local status = Status
	local details = Details
	local messageLabel = Message
	if not gui or not status or not details or not messageLabel then
		return
	end

	local state = ReadString("DungeonState")
	gui.Enabled = state == "Active" or state == "Downed" or state == "Eliminated" or state == "Notice"
	if not gui.Enabled then
		return
	end

	local zone = ReadNumber("DungeonZone")
	local wave = ReadNumber("DungeonWave")
	local difficulty = ReadString("DungeonDifficulty") or "Normal"
	local partySize = ReadNumber("DungeonPartySize") or 1
	local message = ReadString("DungeonMessage")

	status.Text = if state == "Notice"
		then "DUNGEON"
		elseif state == "Downed" then "DOWNED - WAIT FOR REVIVE"
		elseif state == "Eliminated" then "ELIMINATED"
		else "DUNGEON RUN"
	details.Text = if state == "Notice"
		then ""
		else string.format(
			"%s  |  Zone %s / 3  |  Wave %s  |  Party %d",
			difficulty,
			if zone then tostring(zone) else "-",
			if wave then tostring(wave) else "-",
			partySize
		)
	messageLabel.Text = if message and message ~= "" then message else ""
	messageLabel.Visible = messageLabel.Text ~= ""
end

function System:Init() end

function System:Start()
	local playerGui = Player:WaitForChild("PlayerGui") :: PlayerGui
	local gui = playerGui:WaitForChild("DungeonStatus") :: ScreenGui
	local panel = gui:WaitForChild("Panel")
	Status = panel:WaitForChild("Status") :: TextLabel
	Details = panel:WaitForChild("Details") :: TextLabel
	Message = panel:WaitForChild("Message") :: TextLabel
	Gui = gui

	for _, name in ATTRIBUTES do
		Player:GetAttributeChangedSignal(name):Connect(Sync)
	end
	Sync()
end

return System

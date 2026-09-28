--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Signal = require(ReplicatedStorage.Packages.Signal)

export type System = {
	Init: (self: System) -> (),
	Start: (self: System) -> (),

	Cooldown: (self: System, slot: number, duration: number) -> (),
	ReadyAt: (self: System, slot: number) -> number,
	Duration: (self: System, slot: number) -> number,

	Changed: Signal.Signal<nil>,
	Activated: Signal.Signal<number>,
}

local System = {} :: System
System.Changed = Signal.new()
System.Activated = Signal.new()

local Ready: { [number]: number } = {} -- Slot -> server time when usable again
local Length: { [number]: number } = {} -- Slot -> last cooldown length (for overlay ratio)

function System:ReadyAt(slot: number): number
	return Ready[slot] or 0
end

function System:Duration(slot: number): number
	return Length[slot] or 0
end

-- Other systems call this to drive Hotbar cooldown visuals (and shake).
-- Never shortens an active overlay — weapon swaps must not restart a longer fire cooldown.
function System:Cooldown(slot: number, duration: number)
	local span = math.max(0, duration)
	local now = Workspace:GetServerTimeNow()
	local ready = now + span
	local current = Ready[slot] or 0
	if ready <= current then
		return
	end

	Ready[slot] = ready
	if current <= now or span > (Length[slot] or 0) then
		Length[slot] = span
	end

	if span > 0 then
		self.Activated:Fire(slot)
	end
end

function System:Init() end

function System:Start() end

return System

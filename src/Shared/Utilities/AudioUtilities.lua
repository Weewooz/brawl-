--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AudioUtilities = {}
local Pool = ReplicatedStorage.Assets:WaitForChild("CombatAudioPool")

type Slot = {
	Part: BasePart,
	Player: AudioPlayer,
	Home: Instance,
	Busy: boolean,
	Gain: number,
}

local Slots: { [string]: { Slot } } = {}
local NextIndex: { [string]: number } = {}

for _, group in Pool:GetChildren() do
	local entries: { Slot } = {}
	for _, part in group:GetChildren() do
		if not part:IsA("BasePart") then
			continue
		end
		local emitter = part:FindFirstChild("Emitter")
		local player = part:FindFirstChild("Player")
		local wire = part:FindFirstChild("Wire")
		if
			not emitter
			or not emitter:IsA("AudioEmitter")
			or not player
			or not player:IsA("AudioPlayer")
			or not wire
			or not wire:IsA("Wire")
		then
			warn("[AudioUtilities] Incomplete audio pool slot " .. part:GetFullName())
			continue
		end
		wire.SourceInstance = player
		wire.TargetInstance = emitter
		emitter:SetDistanceAttenuation({ [0] = 1, [12] = 1, [32] = 0.5, [64] = 0 })
		local slot: Slot = { Part = part, Player = player, Home = group, Busy = false, Gain = player.Volume }
		player.Ended:Connect(function()
			if player.IsPlaying then
				return
			end
			slot.Busy = false
			part.Parent = slot.Home
		end)
		table.insert(entries, slot)
	end
	table.sort(entries, function(left, right)
		return (tonumber(left.Part.Name) or math.huge) < (tonumber(right.Part.Name) or math.huge)
	end)
	Slots[group.Name] = entries
end

function AudioUtilities.Stop(name: string)
	local entries = Slots[name]
	if not entries then
		return
	end
	for _, slot in entries do
		if slot.Busy then
			slot.Player:Stop()
			slot.Busy = false
			slot.Part.Parent = slot.Home
		end
	end
end

function AudioUtilities.PlayAtPosition(name: string, position: Vector3, volume: number): boolean
	local entries = Slots[name]
	if not entries then
		return false
	end
	local count = #entries
	if count == 0 then
		return false
	end
	local start = (NextIndex[name] or 0) % count + 1
	for offset = 0, count - 1 do
		local index = (start + offset - 1) % count + 1
		local slot = entries[index]
		if not slot.Busy and slot.Player.IsReady then
			NextIndex[name] = index
			slot.Busy = true
			slot.Part.CFrame = CFrame.new(position)
			slot.Part.Parent = workspace
			slot.Player.Volume = volume * slot.Gain
			slot.Player.TimePosition = slot.Player.PlaybackRegion.Min
			slot.Player:Play()
			return true
		end
	end
	return false
end

function AudioUtilities.PlayAtPart(name: string, part: BasePart, volume: number): boolean
	return AudioUtilities.PlayAtPosition(name, part.Position, volume)
end

return AudioUtilities

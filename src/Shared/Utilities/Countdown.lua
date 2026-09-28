--!strict

local Countdown = {}

local TICK_COUNT = 14
local INTERVAL_DECAY = 0.9
local LAST_TICK_FRACTION = 0.95

function Countdown.GetTickTimes(duration: number): { number }
	if duration <= 0 then
		return {}
	end

	local weights: { number } = {}
	local total = 0
	local interval = 1
	for index = 1, TICK_COUNT do
		weights[index] = interval
		total += interval
		interval *= INTERVAL_DECAY
	end

	local tickTimes: { number } = {}
	local elapsed = 0
	local scale = duration * LAST_TICK_FRACTION / total
	for index, weight in weights do
		elapsed += weight * scale
		tickTimes[index] = elapsed
	end

	return tickTimes
end

return Countdown

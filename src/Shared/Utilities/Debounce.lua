--!strict

local Debounce = {}

export type TimestampSource = "ServerTimeNow" | "Clock"

export type ActiveDebounces = { [string]: number }

local TimestampSourceFunctions = {
	ServerTimeNow = function(): number
		return workspace:GetServerTimeNow()
	end,

	Clock = function(): number
		return os.clock()
	end,
}

local DEFAULT_DEBOUNCE_TIME = 0.25
local DEFAULT_TIMESTAMP_FUNCTION = TimestampSourceFunctions.Clock

local GlobalActiveDebounces: ActiveDebounces = {}

--==========================-- Private Functions --==========================--

-- Returns the current timestamp. Optionally takes the method of which to derive the timestamp from
local function GetTimestamp(source: TimestampSource?): number
	local timestampFunction = TimestampSourceFunctions[source] or DEFAULT_TIMESTAMP_FUNCTION

	return timestampFunction()
end

-- Returns the timestamp of the given debounce, or a new one if it doesn't exist
local function EnsureDebounce(debounceId: string, requestedEndTimestamp: number?, activeDebounces: ActiveDebounces?, timestampSource: TimestampSource?): number
	local debounceTable = activeDebounces or GlobalActiveDebounces
	local debounceEndTimestamp = debounceTable[debounceId]

	if not debounceEndTimestamp then
		debounceEndTimestamp = requestedEndTimestamp or GetTimestamp(timestampSource)
		debounceTable[debounceId] = debounceEndTimestamp
	end

	return debounceEndTimestamp
end

--==========================-- Public Functions --==========================--

-- Returns the debounce end timestamp, or a new one if it doesn't exist
function Debounce.Get(debounceId: string): number
	return EnsureDebounce(debounceId)
end

-- Returns the entire table of global debounces
function Debounce.GetAll(): { [string]: number }
	return GlobalActiveDebounces
end

-- Returns true if the debounce is defined, false if not
function Debounce.Exists(debounceId: string, activeDebounces: ActiveDebounces?): boolean
	local debounceTable = activeDebounces or GlobalActiveDebounces

	local debounceEndTimestamp = debounceTable[debounceId]

	return debounceEndTimestamp and true or false
end

-- Returns true if the debounce end timestamp has not yet been passed
function Debounce.IsActive(debounceId: string, activeDebounces: ActiveDebounces?, timestampSource: TimestampSource?): boolean
	local debounceTable = activeDebounces or GlobalActiveDebounces

	local debounceEndTimestamp = debounceTable[debounceId]

	if debounceEndTimestamp then
		return debounceEndTimestamp > GetTimestamp(timestampSource)
	end

	return false
end

-- Sets the debounce timestamp to the given time and returns the end timestamp
function Debounce.Set(debounceId: string, addDebounceTime: number, activeDebounces: ActiveDebounces?, timestampSource: TimestampSource?): number
	local debounceTable = activeDebounces or GlobalActiveDebounces
	
	local newEndTimstamp = GetTimestamp(timestampSource) + addDebounceTime
	debounceTable[debounceId] = newEndTimstamp

	return newEndTimstamp
end

-- Returns true if the debounce is not active. If not, its will set a new debounce using the current time added to the given time
function Debounce.Use(debounceId: string, addDebounceTime: number?, timestampSource: TimestampSource?): boolean
	if Debounce.IsActive(debounceId, timestampSource) then
		return false
	end

	Debounce.Set(debounceId, addDebounceTime or DEFAULT_DEBOUNCE_TIME, timestampSource)

	return true
end

-- Clears the debounce from memory
function Debounce.Clear(debounceId: string, activeDebounces: ActiveDebounces?)
	local debounceTable = activeDebounces or GlobalActiveDebounces
	
	debounceTable[debounceId] = nil
end

return Debounce

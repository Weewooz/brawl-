--!strict
-- Numba ModuleScript
-- Handles numbers larger than the int64 limit (~9.2 Quintillion)
-- Stored in ReplicatedStorage

export type Number = {
	Value: number,
	Exponent: number,
	Infinite: boolean?, -- Optional: true if this number represents infinity
}

local Numba = {}

-- Define the suffixes for easy formatting. You can extend this list as far as you need.
-- The index of the suffix in this table corresponds to the 'exponent'.
local NUMBER_SUFFIXES = {
	"",
	"K",
	"M",
	"B",
	"T",
	"Q",
	"Qu",
	"S",
	"Se",
	"O",
	"N",
	"D",
	"U",
	"Do",
	"Tr",
	"Qa",
	"Qi",
	"Sx",
	"Sp",
	"Oc",
	"No",
	"V",
	"Uv",
	"Dv",
	"Tv",
	"Qv",
	"Qw",
	"Sy",
	"Sz",
	"Ov",
	"Nw",
}

-- Create a reverse-lookup table for fast suffix-to-exponent conversion
local SUFFIX_LOOKUP = {}
for i, suffix in ipairs(NUMBER_SUFFIXES) do
	if suffix ~= "" then
		-- Store the exponent (i-1) using the uppercase suffix as the key
		SUFFIX_LOOKUP[suffix:upper()] = i - 1
	end
end

table.freeze(NUMBER_SUFFIXES)
table.freeze(SUFFIX_LOOKUP)

--// Internal Helper Function: Normalizes a number
local function Normalize(num: Number): Number
	--// Handle Infinity: Infinite numbers do not need normalization.
	if num.Infinite then
		return num
	end

	while num.Value >= 1000 and NUMBER_SUFFIXES[num.Exponent + 2] do
		num.Value = num.Value / 1000
		num.Exponent = num.Exponent + 1
	end

	while num.Value > 0 and num.Value < 1 and num.Exponent > 0 do
		num.Value = num.Value * 1000
		num.Exponent = num.Exponent - 1
	end
	return num
end

local function IsZero(num: Number): boolean
	return not num.Infinite and num.Value == 0 and num.Exponent == 0
end

--// Constructor: Creates a new Numba object
function Numba.new(value: number, exponent: number): Number
	local num: Number = {
		Value = value or 0,
		Exponent = exponent or 0,
		Infinite = false,
	}
	return Normalize(num)
end

--// Constants (frozen to prevent accidental mutation of shared references)
Numba.zero = table.freeze(Numba.new(0, 0))
Numba.huge = table.freeze({ Value = 1, Exponent = 999, Infinite = true })

--// Formatter: Converts a Numba object into a human-readable string (e.g., "1.53T")
function Numba.Format(num: Number): string
	--// Handle Infinity
	if num.Infinite then
		return "∞"
	end

	local suffix = NUMBER_SUFFIXES[num.Exponent + 1] or ""

	if num.Exponent == 0 then
		-- Value that smaller than 1k must be only decimal display

		return string.format("%d", num.Value)
	end

	if num.Value == math.floor(num.Value) then
		-- It's a whole number (e.g., 10.0), so format with no decimals.

		return string.format("%.0f%s", num.Value, suffix)
	else
		-- It has a decimal part (e.g., 10.34), so format with two decimals.
		return string.format("%.2f%s", num.Value, suffix)
	end
end

-- Converts a formatted string (e.g., "1.5K", "22M") back into a Numba object.
function Numba.Breakdown(str: string): Number
	if not str or typeof(str) ~= "string" then
		warn("Numba.FromString Error: Input must be a string.")
		return Numba.zero
	end

	-- Handle Infinity
	if str == "∞" then
		return Numba.huge
	end

	-- Try to convert directly if it's just a number with no suffix
	local asNumber = tonumber(str)
	if asNumber then
		return Numba.Process(asNumber) -- Use our existing function for this
	end

	-- Use string patterns to separate the number part and the suffix part
	local numberPartStr = str:match("^%-?[0-9.,]+")
	local suffixPartStr = str:match("%a+$")

	if not numberPartStr then
		warn("Numba.FromString Error: Could not parse number from string '" .. str .. "'")
		return Numba.zero
	end

	local value = tonumber(numberPartStr)
	local exponent = 0

	if value == nil then
		warn("Numba.FromString Error: Invalid number format in '" .. str .. "'")
		return Numba.zero
	end

	if suffixPartStr then
		-- Look up the exponent in our fast lookup table
		exponent = SUFFIX_LOOKUP[suffixPartStr:upper()]
		if not exponent then
			warn("Numba.FromString Error: Unknown suffix '" .. suffixPartStr .. "' in string '" .. str .. "'")
			return Numba.zero
		end
	end

	return Numba.new(value, exponent)
end

--// Conversion Functions
function Numba.Convert(num: Number): number
	--// Handle Infinity
	if num.Infinite then
		return math.huge
	end

	if num.Exponent >= 6 then
		warn(
			"Numba Warning: Attempted to convert a Numba ("
				.. Numba.Format(num)
				.. ") to a standard number, but it may be too large and result in precision loss or overflow."
		)
	end

	return num.Value * (1000 ^ num.Exponent)
end

function Numba.ConvertToAdvancedNumber(num: Number): number
	-- This return a better format of a Numba, instead of returning a regular number
	if num.Infinite then
		return math.huge
	end

	local _base = num.Exponent * 1000
	return _base + num.Value
end

function Numba.ProcessFromAdvancedNumber(num: number): Number
	if num == math.huge then
		return Numba.huge
	end
	local exponent = math.floor(num / 1000)
	local value = num % 1000
	return { Value = value, Exponent = exponent, Infinite = false }
end

function Numba.Process(num: number): Number
	if num == math.huge then
		return Numba.huge
	end
	return Numba.new(num, 0)
end

--// Math Operations
function Numba.Add(num1: Number, num2: Number): Number
	--// Handle Infinity
	if num1.Infinite or num2.Infinite then
		return Numba.huge
	end

	local result: Number = { Value = 0, Exponent = 0, Infinite = false }
	if num1.Exponent > num2.Exponent then
		result.Exponent = num1.Exponent
		result.Value = num1.Value + (num2.Value / (1000 ^ (num1.Exponent - num2.Exponent)))
	elseif num2.Exponent > num1.Exponent then
		result.Exponent = num2.Exponent
		result.Value = num2.Value + (num1.Value / (1000 ^ (num2.Exponent - num1.Exponent)))
	else
		result.Exponent = num1.Exponent
		result.Value = num1.Value + num2.Value
	end
	return Normalize(result)
end

function Numba.Subtract(num1: Number, num2: Number): Number
	--// Handle Infinity
	if num1.Infinite and num2.Infinite then
		return Numba.zero
	end -- ∞ - ∞ = 0
	if num1.Infinite then
		return Numba.huge
	end -- ∞ - finite = ∞
	if num2.Infinite then
		return Numba.zero
	end -- finite - ∞ = 0

	local result: Number = { Value = 0, Exponent = 0, Infinite = false }
	if num1.Exponent > num2.Exponent then
		result.Exponent = num1.Exponent
		result.Value = num1.Value - (num2.Value / (1000 ^ (num1.Exponent - num2.Exponent)))
	elseif num2.Exponent > num1.Exponent then
		result.Exponent = num2.Exponent
		result.Value = (num1.Value / (1000 ^ (num2.Exponent - num1.Exponent))) - num2.Value
	else
		result.Exponent = num1.Exponent
		result.Value = num1.Value - num2.Value
	end

	if result.Value < 0 then
		return Numba.zero
	end
	return Normalize(result)
end

function Numba.Multiply(num: Number, scalar: number): Number
	if num.Infinite then
		return if scalar > 0 then Numba.huge else Numba.zero
	end
	return Normalize({ Value = num.Value * scalar, Exponent = num.Exponent, Infinite = false })
end

function Numba.Divide(num1: Number, num2: Number): Number
	--// Handle Infinity & Division by Zero
	if IsZero(num2) then
		return if IsZero(num1) then Numba.zero else Numba.huge -- 0/0 = 0, finite/0 = ∞
	end
	if num1.Infinite and num2.Infinite then
		return Numba.new(1, 0)
	end -- ∞ / ∞ = 1
	if num1.Infinite then
		return Numba.huge
	end -- ∞ / finite = ∞
	if num2.Infinite then
		return Numba.zero
	end -- finite / ∞ = 0

	local result: Number = {
		Value = num1.Value / num2.Value,
		Exponent = num1.Exponent - num2.Exponent,
		Infinite = false,
	}
	return Normalize(result)
end

-- Raises a Numba to the power of a standard number (scalar).
function Numba.Power(base: Number, power: number): Number
	--// Handle Infinity & Edge Cases
	if base.Infinite then
		if power > 0 then
			return Numba.huge
		elseif power == 0 then
			return Numba.new(1, 0) -- Indeterminate, conventionally 1
		else
			return Numba.zero -- 1 / ∞ = 0
		end
	end

	if power == 0 then
		return Numba.new(1, 0)
	elseif power == 1 then
		return base
	elseif base.Value == 0 then
		return Numba.zero
	end

	-- To raise (v * 1000^e) to the power of p,
	-- we calculate (v^p) * 1000^(e * p).
	local result: Number = {
		Value = base.Value ^ power,
		Exponent = base.Exponent * power,
		Infinite = false,
	}

	return Normalize(result)
end

--// Comparison
function Numba.Compare(num1: Number, num2: Number): number
	--// Handle Infinity
	if num1.Infinite and num2.Infinite then
		return 0
	end
	if num1.Infinite then
		return 1
	end
	if num2.Infinite then
		return -1
	end

	if num1.Exponent > num2.Exponent then
		return 1
	end
	if num2.Exponent > num1.Exponent then
		return -1
	end

	if num1.Value > num2.Value then
		return 1
	end
	if num2.Value > num1.Value then
		return -1
	end

	return 0
end

--// Utility Functions
function Numba.Max(...: Number): Number
	local args = { ... }
	if #args == 0 then
		return Numba.zero
	end

	local currentMax = args[1]
	for i = 2, #args do
		if Numba.Compare(args[i], currentMax) == 1 then
			currentMax = args[i]
		end
	end
	return currentMax
end

function Numba.Min(...: Number): Number
	local args = { ... }
	if #args == 0 then
		return Numba.zero
	end

	local currentMin = args[1]
	for i = 2, #args do
		if Numba.Compare(args[i], currentMin) == -1 then
			currentMin = args[i]
		end
	end
	return currentMin
end

-- Linearly interpolates between two Numbas.
-- @param a The starting Numba (when t=0)
-- @param b The ending Numba (when t=1)
-- @param t The interpolation alpha (a number, usually between 0 and 1)
function Numba.Lerp(a: Number, b: Number, t: number): Number
	--// Handle Infinity
	if a.Infinite or b.Infinite then
		-- A proper lerp with infinity is complex; for game purposes, we can simplify.
		-- If t is 0.5, it's ambiguous. We can return either 'a' or 'b' if one is infinite.
		-- Returning 'b' if t > 0 and 'b' is huge is a common approach.
		return if t >= 0.5 then b else a
	end

	-- Determine the common exponent to work with (the larger of the two)
	local targetExponent = math.max(a.Exponent, b.Exponent)

	-- Convert both numbers' values to this common exponent
	local valueA = a.Value * (1000 ^ (a.Exponent - targetExponent))
	local valueB = b.Value * (1000 ^ (b.Exponent - targetExponent))

	-- Now perform the standard lerp on the normalized values
	local lerpedValue = valueA + (valueB - valueA) * t

	-- Create a new Numba from the result and normalize it
	local result: Number = {
		Value = lerpedValue,
		Exponent = targetExponent,
		Infinite = false,
	}

	return Normalize(result)
end

return Numba

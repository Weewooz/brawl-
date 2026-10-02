--!strict

export type Charge = {
	LastId: number?,
	Id: number?,
	StartedAt: number?,
}

local YumiRules = {}
local MAX_ID = 4294967295

function YumiRules.Finite(value: number): boolean
	return typeof(value) == "number" and value == value and math.abs(value) < math.huge
end

function YumiRules.ValidId(value: number): boolean
	return YumiRules.Finite(value) and value >= 0 and value <= MAX_ID and value % 1 == 0
end

function YumiRules.Normalize(x: number, y: number, z: number, confused: boolean?): (number?, number?)
	if not YumiRules.Finite(x) or not YumiRules.Finite(y) or not YumiRules.Finite(z) then
		return nil, nil
	end
	local scale = math.max(math.abs(x), math.abs(z))
	if scale < 0.001 then
		return nil, nil
	end
	local flatX, flatZ = x / scale, z / scale
	local magnitude = math.sqrt(flatX * flatX + flatZ * flatZ)
	local sign = if confused then -1 else 1
	return sign * flatX / magnitude, sign * flatZ / magnitude
end

function YumiRules.Begin(state: Charge, id: number, now: number): boolean
	if not YumiRules.ValidId(id) or not YumiRules.Finite(now) or state.Id ~= nil then
		return false
	end
	if state.LastId ~= nil and id <= state.LastId then
		return false
	end
	state.LastId = id
	state.Id = id
	state.StartedAt = now
	return true
end

function YumiRules.Cancel(state: Charge, id: number?): boolean
	if id ~= nil and (not YumiRules.ValidId(id) or state.Id ~= id) then
		return false
	end
	state.Id = nil
	state.StartedAt = nil
	return true
end

function YumiRules.Damage(now: number, startedAt: number, duration: number, minimum: number, maximum: number): number?
	if
		not YumiRules.Finite(now)
		or not YumiRules.Finite(startedAt)
		or now < startedAt
		or not YumiRules.Finite(duration)
		or duration <= 0
		or not YumiRules.Finite(minimum)
		or not YumiRules.Finite(maximum)
		or minimum < 0
		or maximum < minimum
	then
		return nil
	end
	return minimum + (maximum - minimum) * math.clamp((now - startedAt) / duration, 0, 1)
end

function YumiRules.Release(
	state: Charge,
	id: number,
	now: number,
	duration: number,
	minimum: number,
	maximum: number
): number?
	if not YumiRules.ValidId(id) or state.Id ~= id or state.StartedAt == nil then
		return nil
	end
	local damage = YumiRules.Damage(now, state.StartedAt, duration, minimum, maximum)
	if damage == nil then
		return nil
	end
	YumiRules.Cancel(state)
	return damage
end

return table.freeze(YumiRules)

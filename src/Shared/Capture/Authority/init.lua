--!strict

export type Member = {
	Active: boolean?,
	Team: string?,
	ProtectedUntil: number?,
}

local Authority = {}

local function Managed(member: Member): boolean
	return member.Active ~= nil or member.Team ~= nil or member.ProtectedUntil ~= nil
end

local function Finite(value: number): boolean
	return typeof(value) == "number" and value == value and math.abs(value) < math.huge
end

function Authority.Read(character: Model): Member
	return {
		Active = character:GetAttribute("CaptureActive"),
		Team = character:GetAttribute("CaptureTeam"),
		ProtectedUntil = character:GetAttribute("CaptureProtectedUntil"),
	}
end

function Authority.CanAttack(member: Member, now: number): boolean
	if not Finite(now) then
		return false
	end
	if not Managed(member) then
		return true
	end
	local protection = member.ProtectedUntil or 0
	return member.Active == true
		and (member.Team == "Azure" or member.Team == "Coral")
		and Finite(protection)
		and protection <= now
end

function Authority.CanHit(attacker: Member, target: Member, now: number): boolean
	if not Managed(attacker) and not Managed(target) then
		return Finite(now)
	end
	return attacker.Active == true
		and target.Active == true
		and attacker.Team ~= target.Team
		and Authority.CanAttack(attacker, now)
		and Authority.CanAttack(target, now)
end

return table.freeze(Authority)

--!strict

export type Team = "Azure" | "Coral"
export type State = {
	Phase: string,
	AzureScore: number,
	CoralScore: number,
	Owner: string,
	CaptureTeam: string,
	CaptureProgress: number,
	Contested: boolean,
	EndsAt: number,
	Winner: string,
	Control: number,
	AzureFraction: number,
	CoralFraction: number,
}

local Rules = {}
Rules.Capacity = 5
Rules.Radius = 12
Rules.Height = 7
Rules.CaptureSeconds = 3
Rules.TargetScore = 100
Rules.RoundSeconds = 180
Rules.OvertimeSeconds = 60
Rules.CountdownSeconds = 8
Rules.ResultsSeconds = 10
Rules.RespawnSeconds = 5
Rules.ProtectionSeconds = 2

function Rules.New(now: number): State
	return {
		Phase = "Active",
		AzureScore = 0,
		CoralScore = 0,
		Owner = "",
		CaptureTeam = "",
		CaptureProgress = 0,
		Contested = false,
		EndsAt = now + Rules.RoundSeconds,
		Winner = "",
		Control = 0,
		AzureFraction = 0,
		CoralFraction = 0,
	}
end

function Rules.Winner(state: State): string
	return if state.AzureScore > state.CoralScore
		then "Azure"
		else if state.CoralScore > state.AzureScore then "Coral" else "Draw"
end

function Rules.Step(state: State, dt: number, now: number, azure: number, coral: number)
	if state.Phase ~= "Active" and state.Phase ~= "Overtime" then
		return
	end
	state.Contested = azure > 0 and coral > 0
	local direction = if state.Contested then 0 else if azure > 0 then 1 else if coral > 0 then -1 else 0
	local previous = state.Control
	local previousOwner = state.Owner
	if direction ~= 0 then
		state.Control = math.clamp(previous + direction * dt / Rules.CaptureSeconds, -1, 1)
		if (state.Owner == "Azure" and state.Control <= 0) or (state.Owner == "Coral" and state.Control >= 0) then
			state.Owner = ""
		end
		if state.Control >= 1 - 1e-6 then
			state.Control = 1
			state.Owner = "Azure"
		elseif state.Control <= -1 + 1e-6 then
			state.Control = -1
			state.Owner = "Coral"
		end
	end
	state.CaptureTeam = if state.Control > 0 then "Azure" else if state.Control < 0 then "Coral" else ""
	state.CaptureProgress = math.abs(state.Control)
	if not state.Contested then
		-- Only the part of this step after a full capture earns points.
		if state.Owner == "Azure" and coral == 0 then
			local scoring = if previousOwner ~= "Azure"
				then math.max(0, dt - (1 - previous) * Rules.CaptureSeconds)
				else dt
			state.AzureFraction += scoring
			local points = math.floor(state.AzureFraction + 1e-6)
			state.AzureFraction -= points
			state.AzureScore = math.min(Rules.TargetScore, state.AzureScore + points)
		elseif state.Owner == "Coral" and azure == 0 then
			local scoring = if previousOwner ~= "Coral"
				then math.max(0, dt - (1 + previous) * Rules.CaptureSeconds)
				else dt
			state.CoralFraction += scoring
			local points = math.floor(state.CoralFraction + 1e-6)
			state.CoralFraction -= points
			state.CoralScore = math.min(Rules.TargetScore, state.CoralScore + points)
		end
	end
	if state.AzureScore >= Rules.TargetScore or state.CoralScore >= Rules.TargetScore then
		state.Phase = "Results"
		state.Winner = Rules.Winner(state)
		return
	end
	local leader = Rules.Winner(state)
	local trailingPresent = (leader == "Azure" and coral > 0) or (leader == "Coral" and azure > 0)
	local trailingOwns = (leader == "Azure" and state.Owner == "Coral")
		or (leader == "Coral" and state.Owner == "Azure")
	if state.Phase == "Overtime" then
		if now >= state.EndsAt or (leader ~= "Draw" and not trailingPresent and not trailingOwns) then
			state.Phase = "Results"
			state.Winner = leader
		end
	elseif now >= state.EndsAt then
		if leader == "Draw" or trailingPresent or trailingOwns then
			state.Phase = "Overtime"
			state.EndsAt = now + Rules.OvertimeSeconds
		else
			state.Phase = "Results"
			state.Winner = leader
		end
	end
end

return table.freeze(Rules)

--!strict

return function(Rules: typeof(require(script.Parent)))
	local function near(actual: number, expected: number)
		assert(math.abs(actual - expected) < 1e-5, tostring(actual) .. " ~= " .. tostring(expected))
	end
	local state = Rules.New(0)
	Rules.Step(state, 1.5, 1.5, 1, 0)
	assert(state.Owner == "" and state.AzureScore == 0)
	near(state.CaptureProgress, 0.5)
	Rules.Step(state, 1, 2.5, 1, 1)
	assert(state.Contested and state.AzureScore == 0)
	near(state.CaptureProgress, 0.5)
	Rules.Step(state, 1.5, 4, 1, 0)
	assert(state.Owner == "Azure" and state.AzureScore == 0)
	Rules.Step(state, 1, 5, 0, 0)
	assert(state.AzureScore == 1, "Owned vacant points must score")
	Rules.Step(state, 1, 6, 1, 1)
	assert(state.AzureScore == 1, "Contested points must not score")
	Rules.Step(state, 1.5, 7.5, 0, 1)
	assert(state.Owner == "Azure" and state.AzureScore == 1)
	Rules.Step(state, 1, 8.5, 0, 0)
	assert(state.AzureScore == 2, "An uncontested owner scores even during partial neutralization")
	Rules.Step(state, 1.5, 10, 0, 1)
	assert(state.Owner == "" and state.CoralScore == 0)
	near(state.CaptureProgress, 0)
	Rules.Step(state, 3, 13, 0, 1)
	assert(state.Owner == "Coral" and state.CoralScore == 0)
	Rules.Step(state, 2, 15, 0, 0)
	assert(state.CoralScore == 2)

	local small = Rules.New(0)
	for index = 1, 40 do
		Rules.Step(small, 0.1, index * 0.1, 1, 0)
	end
	local large = Rules.New(0)
	Rules.Step(large, 4, 4, 1, 0)
	assert(
		small.AzureScore == large.AzureScore and small.Owner == large.Owner,
		"Capture must be independent of step size"
	)
	assert(small.AzureScore == 1)

	local target = Rules.New(0)
	target.AzureScore = 99
	target.Owner = "Azure"
	target.Control = 1
	Rules.Step(target, 1, 1, 0, 0)
	assert(target.Phase == "Results" and target.Winner == "Azure")
	Rules.Step(target, 10, 11, 0, 1)
	assert(target.AzureScore == 100 and target.Control == 1, "Results must freeze gameplay")

	local deadline = Rules.New(0)
	deadline.AzureScore = 20
	Rules.Step(deadline, 0, Rules.RoundSeconds, 0, 0)
	assert(deadline.Phase == "Results" and deadline.Winner == "Azure")
	local overtime = Rules.New(0)
	overtime.AzureScore = 20
	Rules.Step(overtime, 0, Rules.RoundSeconds, 1, 1)
	assert(overtime.Phase == "Overtime")
	Rules.Step(overtime, 0, Rules.RoundSeconds + 1, 1, 0)
	assert(overtime.Phase == "Results" and overtime.Winner == "Azure", "Clearing the trailing team must end overtime")
	local owned = Rules.New(0)
	owned.AzureScore = 20
	owned.Owner = "Coral"
	owned.Control = -1
	Rules.Step(owned, 0, Rules.RoundSeconds, 0, 0)
	assert(owned.Phase == "Overtime", "Trailing ownership must trigger overtime")
	local draw = Rules.New(0)
	Rules.Step(draw, 0, Rules.RoundSeconds, 0, 0)
	assert(draw.Phase == "Overtime")
	Rules.Step(draw, 0, Rules.RoundSeconds + Rules.OvertimeSeconds, 0, 0)
	assert(draw.Phase == "Results" and draw.Winner == "Draw", "Overtime must have a hard bound")
	return "Capture rules: capture, contest, neutralize, passive score, step invariance, win, freeze, deadline, overtime, draw passed"
end

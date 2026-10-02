--!strict

return function(Rules: typeof(require(script.Parent)))
	local state = { LastId = nil, Id = nil, StartedAt = nil } :: { LastId: number?, Id: number?, StartedAt: number? }
	assert(Rules.Begin(state, 1, 10), "First draw must start")
	assert(not Rules.Begin(state, 2, 10.5), "Repeated begin cannot reset or replace a charge")
	assert(state.StartedAt == 10 and state.LastId == 1, "Rejected begin preserves server timing and sequence")
	assert(Rules.Release(state, 2, 10.5, 1, 10, 28) == nil, "Mismatched release cannot consume a draw")
	assert(Rules.Release(state, 1, 10.5, 1, 10, 28) == 19, "Half server charge interpolates damage")
	assert(Rules.Release(state, 1, 11, 1, 10, 28) == nil, "Release replay cannot fire again")
	assert(not Rules.Begin(state, 1, 12) and not Rules.Begin(state, 0, 12), "Replayed and older begins are rejected")
	assert(Rules.Begin(state, 2, 12), "New sequence may start after release")
	assert(not Rules.Cancel(state, 1) and state.Id == 2, "Old cancel cannot interrupt a new charge")
	assert(Rules.Cancel(state, 2) and not Rules.Begin(state, 2, 13), "Cancelled draws cannot be replayed")
	assert(Rules.Begin(state, 3, 14), "Later draw remains available after cancellation")
	assert(Rules.Release(state, 3, 100, 1, 10, 28) == 28, "Long holds clamp to maximum damage")
	assert(Rules.Damage(10, 10, 1, 10, 28) == 10, "Immediate release uses minimum damage")
	assert(Rules.Damage(9, 10, 1, 10, 28) == nil, "Clock inversion is rejected")
	assert(Rules.ValidId(0) and Rules.ValidId(4294967295), "Unsigned sequence endpoints are valid")
	for _, invalid in { -1, 0.5, 4294967296, math.huge, -math.huge, 0 / 0 } do
		assert(not Rules.ValidId(invalid), "Invalid sequence fails closed")
		assert(Rules.Normalize(invalid, math.huge, 1) == nil, "Nonfinite aim fails closed")
	end
	assert(Rules.Normalize(0, 1, 0) == nil, "Vertical-only aim is rejected")
	local x, z = Rules.Normalize(3, 20, 4)
	assert(
		x ~= nil and z ~= nil and math.abs(x - 0.6) < 1e-6 and math.abs(z - 0.8) < 1e-6,
		"Aim is flattened and normalized"
	)
	assert(Rules.Normalize(1e300, 0, 1e300) ~= nil, "Finite large aim avoids magnitude overflow")
	local confusedX, confusedZ = Rules.Normalize(3, 20, 4, true)
	assert(
		confusedX ~= nil and confusedZ ~= nil and math.abs(confusedX + 0.6) < 1e-6 and math.abs(confusedZ + 0.8) < 1e-6,
		"Authoritative confusion reverses normalized aim without changing magnitude"
	)
	assert(Rules.Normalize(0, 1, 0, true) == nil, "Confusion cannot turn invalid vertical aim into a valid shot")
	for _, invalid in { math.huge, -math.huge, 0 / 0 } do
		assert(Rules.Damage(invalid, 0, 1, 10, 28) == nil, "Nonfinite clocks are rejected")
		assert(Rules.Damage(1, 0, invalid, 10, 28) == nil, "Nonfinite duration is rejected")
		assert(Rules.Damage(1, 0, 1, invalid, 28) == nil, "Nonfinite damage is rejected")
	end
	assert(
		Rules.Damage(1, 0, 0, 10, 28) == nil and Rules.Damage(1, 0, 1, 28, 10) == nil,
		"Invalid charge configuration fails closed"
	)
	return "Yumi rules: sequence replay, cancellation ordering, server charge timing, damage clamping, unsigned IDs, finite flattened aim and confusion reversal passed"
end

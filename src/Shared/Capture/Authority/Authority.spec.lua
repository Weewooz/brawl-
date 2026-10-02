--!strict

return function(Authority: typeof(require(script.Parent)))
	local azure = { Active = true, Team = "Azure", ProtectedUntil = 0 }
	local coral = { Active = true, Team = "Coral", ProtectedUntil = 0 }
	local lobby = { Active = false }
	local queued = { Active = false, Team = "Azure", ProtectedUntil = 0 }
	local protected = { Active = true, Team = "Coral", ProtectedUntil = 102 }
	assert(Authority.CanHit(azure, coral, 100), "Active opponents must damage each other")
	assert(not Authority.CanHit(azure, azure, 100), "Friendly fire must be rejected")
	assert(
		not Authority.CanAttack(lobby, 100) and not Authority.CanAttack(queued, 100),
		"Inactive participants cannot attack"
	)
	assert(
		not Authority.CanHit(azure, lobby, 100) and not Authority.CanHit(lobby, azure, 100),
		"Lobby players must be isolated"
	)
	assert(
		not Authority.CanHit(azure, protected, 100) and not Authority.CanHit(protected, azure, 100),
		"Protection prevents outgoing and incoming hits"
	)
	assert(Authority.CanHit(azure, protected, 102), "Protection expires exactly at its deadline")
	assert(
		not Authority.CanHit(azure, {}, 100) and not Authority.CanHit({}, coral, 100),
		"Unmanaged NPCs cannot interfere in a capture match"
	)
	assert(Authority.CanHit({}, {}, 100), "Unmanaged combat must retain its existing behavior")
	assert(not Authority.CanAttack({ Active = true, Team = "Unknown" }, 100), "Invalid teams fail closed")
	assert(
		not Authority.CanAttack({ Active = true, Team = "Azure", ProtectedUntil = 0 / 0 }, 100),
		"NaN protection fails closed"
	)
	assert(
		not Authority.CanAttack({ Active = true, Team = "Azure", ProtectedUntil = math.huge }, 100),
		"Infinite protection fails closed"
	)
	assert(not Authority.CanHit(azure, coral, math.huge), "Nonfinite server time fails closed")
	return "Capture authority: enemy, friendly, lobby, queued/results, protection, deadline, NPC isolation, invalid team and nonfinite values passed"
end

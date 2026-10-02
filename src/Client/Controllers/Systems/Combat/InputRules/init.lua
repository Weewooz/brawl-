--!strict

local Rules = {}

function Rules.Window(now: number, blocked: boolean, recovery: number, cooldown: number, buffer: number): string
	if blocked or now ~= now or recovery ~= recovery or cooldown ~= cooldown then
		return "Reject"
	end
	local waitFor = math.max(recovery, cooldown)
	if waitFor <= 0 then
		return "Cast"
	end
	return if waitFor <= buffer then "Buffer" else "Reject"
end

function Rules.Cancelled(
	position: Vector2,
	origin: Vector2,
	buttonWidth: number,
	cancelPosition: Vector2,
	cancelSize: Vector2
): boolean
	return (position - origin).Magnitude > math.max(140, buttonWidth * 2.5)
		or (
			position.X >= cancelPosition.X
			and position.Y >= cancelPosition.Y
			and position.X <= cancelPosition.X + cancelSize.X
			and position.Y <= cancelPosition.Y + cancelSize.Y
		)
end

return table.freeze(Rules)

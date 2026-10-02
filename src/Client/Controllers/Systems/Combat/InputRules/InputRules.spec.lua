--!strict

return function(Rules: typeof(require(script.Parent)))
	assert(Rules.Window(10, false, 0.12, 0, 0.15) == "Buffer", "Final recovery accepts one buffered skill")
	assert(Rules.Window(10, false, 0, 0.12, 0.15) == "Buffer", "Cooldown may end within the input window")
	assert(Rules.Window(10, false, 0.2, 0, 0.15) == "Reject", "Earlier requests cannot become delayed casts")
	assert(Rules.Window(10, true, 0.1, 0, 0.15) == "Reject", "Guard and interruption invalidate buffered input")
	assert(Rules.Window(10, false, 0, 0, 0.15) == "Cast")
	assert(Rules.Window(10, false, 0 / 0, 0, 0.15) == "Reject")
	local origin = Vector2.new(300, 300)
	local cancelPosition, cancelSize = Vector2.new(20, 20), Vector2.new(100, 50)
	assert(
		not Rules.Cancelled(Vector2.new(370, 300), origin, 60, cancelPosition, cancelSize),
		"Dragging past the button still aims"
	)
	assert(Rules.Cancelled(Vector2.new(460, 300), origin, 60, cancelPosition, cancelSize), "Far drag cancels")
	assert(Rules.Cancelled(Vector2.new(70, 40), origin, 60, cancelPosition, cancelSize), "Cancel zone accepts release")
end

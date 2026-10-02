--!strict

local function Signal(): any
	local listeners: { { Connection: any, Callback: (...any) -> () } } = {}
	local signal = {}
	function signal:Connect(callback: (...any) -> ())
		local connection = { Connected = true }
		function connection:Disconnect()
			self.Connected = false
		end
		table.insert(listeners, { Connection = connection, Callback = callback })
		return connection
	end
	function signal:Fire(...)
		for _, listener in table.clone(listeners) do
			if listener.Connection.Connected then
				listener.Callback(...)
			end
		end
	end
	return signal
end

local function Touch(x: number, y: number): any
	local changed = Signal()
	local input = {
		Position = Vector3.new(x, y, 0),
		UserInputType = Enum.UserInputType.Touch,
		UserInputState = Enum.UserInputState.Begin,
	}
	function input:GetPropertyChangedSignal(name: string)
		assert(name == "UserInputState")
		return changed
	end
	function input:Finish(cancelled: boolean)
		self.UserInputState = if cancelled then Enum.UserInputState.Cancel else Enum.UserInputState.End
		changed:Fire()
	end
	return input
end

return function(Controller: typeof(require(script.Parent)))
	local attacks, releases, cancelledDraws, pendingCleared = 0, 0, 0, 0
	local blocked, sprinting, allowed = false, false, true
	local guiOverlap = false
	local requests: { { Name: string, Direction: Vector3?, Touch: boolean? } } = {}
	local runtime = {
		Input = {
			GetMouseLocation = function()
				return Vector2.new(300, 300)
			end,
		},
		Gui = {
			GetGuiInset = function()
				return Vector2.zero
			end,
		},
		PlayerGui = {
			GetGuiObjectsAtPosition = function()
				return if guiOverlap
					then { {
						Active = true,
						IsA = function()
							return true
						end,
					} }
					else {}
			end,
		},
	} :: any
	local controller = Controller.new({
		Attack = function()
			attacks += 1
		end,
		ReleaseDraw = function(cancelled)
			releases += 1
			if cancelled then
				cancelledDraws += 1
			end
		end,
		CancelDraw = function()
			cancelledDraws += 1
		end,
		RequestSkill = function(name, direction, touch)
			table.insert(requests, { Name = name, Direction = direction, Touch = touch })
		end,
		SetBlocking = function(enabled)
			blocked = enabled
		end,
		SetSprinting = function(enabled)
			sprinting = enabled
		end,
		CanBeginControl = function()
			return allowed
		end,
		CanBeginSkillAim = function()
			return allowed and not blocked
		end,
		Ranged = function()
			return false
		end,
		Facing = function()
			return Vector3.zAxis
		end,
		ScreenDirection = function(delta)
			return if delta.Magnitude > 12 then Vector3.xAxis else nil
		end,
		MovementDirection = function()
			return nil
		end,
		MouseDirection = function()
			return Vector3.xAxis, nil
		end,
		ClearPendingSkill = function()
			pendingCleared += 1
		end,
		ClearPreview = function() end,
		ResetRequests = function()
			blocked = false
			sprinting = false
		end,
	}, runtime)

	local attack = Touch(300, 300)
	controller:BeginAim(attack, "Attack")
	controller:BeginAim(attack, "Block")
	assert(attacks == 1 and not blocked, "One touch cannot enter a second control")
	attack.Position = Vector3.new(340, 300, 0)
	controller:Move(attack)
	assert(controller:GetAttackAim() == Vector3.xAxis)
	local connection = controller.TouchConnections[attack]
	attack:Finish(true)
	controller:EndAim(attack)
	assert(releases == 1 and cancelledDraws == 1, "Cancelled draw releases once despite duplicate end events")
	assert(
		not controller:IsAttackHeld() and not connection.Connected,
		"Cancelled touches disconnect and clear held attack"
	)

	local dash = Touch(300, 300)
	controller:BeginAim(dash, "Dash")
	dash:Finish(true)
	assert(#requests == 0, "Cancelled dash cannot become a cast")
	dash = Touch(300, 300)
	controller:BeginAim(dash, "Dash")
	dash.Position = Vector3.new(340, 300, 0)
	dash:Finish(false)
	controller:EndAim(dash)
	assert(
		#requests == 1 and requests[1].Name == "Dash" and requests[1].Direction == Vector3.xAxis,
		"Drag release dispatches exactly once"
	)

	controller.Buttons.RisingCrash = { AbsoluteSize = Vector2.new(60, 60) } :: any
	controller.Cancel = {
		AbsolutePosition = Vector2.new(20, 20),
		AbsoluteSize = Vector2.new(100, 50),
		FindFirstAncestorOfClass = function()
			return nil
		end,
	} :: any
	local skill = Touch(300, 300)
	controller:BeginSkillAim(skill, "RisingCrash")
	skill.Position = Vector3.new(70, 40, 0)
	skill:Finish(false)
	assert(#requests == 1 and controller.Aiming == nil, "Cancel-zone release clears preview without requesting a skill")
	skill = Touch(300, 300)
	controller:BeginSkillAim(skill, "RisingCrash")
	skill.Position = Vector3.new(340, 300, 0)
	skill:Finish(false)
	assert(#requests == 2 and requests[2].Touch == true, "Skill release carries the touch aim into buffering")
	assert(pendingCleared == 2, "Starting each preview clears the preceding buffered skill")

	local guard = Touch(300, 300)
	controller:BeginAim(guard, "Block")
	assert(blocked and controller:GetGuardAim() == Vector3.zAxis)
	controller:Press("Sprint")
	controller:Press("Attack")
	assert(sprinting and controller:IsAttackHeld())
	controller.Focused = false
	controller:Reset()
	guard:Finish(false)
	controller:Release("Attack")
	assert(
		not blocked and not sprinting and not controller:IsAttackHeld(),
		"Focus reset clears native holds and touch guard"
	)
	assert(releases == 1, "A stale native release after reset cannot fire an arrow")
	controller:Press("Attack")
	assert(attacks == 2, "Unfocused native presses are ignored")
	controller.Focused = true
	guiOverlap = true
	controller:Press("Attack")
	assert(attacks == 2, "Hardware mouse attack is suppressed over active GUI")
	controller:Press("Attack", true)
	controller:Press("Attack")
	assert(attacks == 3, "GUI and native mouse presses cannot double-dispatch")
	controller:Release("Attack")
	controller:Release("Attack")
	assert(releases == 1, "Native release waits for mouse cancellation information")
	local mouse = Touch(300, 300)
	mouse.UserInputType = Enum.UserInputType.MouseButton1
	mouse.UserInputState = Enum.UserInputState.End
	controller:EndAim(mouse)
	controller:EndAim(mouse)
	assert(releases == 2, "Mouse releases are idempotent")
	allowed = false
	controller:Press("Dash")
	assert(#requests == 2, "Menu/text focus gates reject native actions")
	return "Input action and touch gesture checks passed"
end

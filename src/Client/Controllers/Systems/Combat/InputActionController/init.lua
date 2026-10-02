--!strict

local InputRules = require(script.Parent.InputRules)
local SKILL_PRIORITY = 3000

export type SkillAim = {
	Input: InputObject,
	Name: string,
	Origin: Vector2,
	Position: Vector2,
	Direction: Vector3?,
	Cancelled: boolean,
	Valid: boolean,
}

export type Callbacks = {
	Attack: () -> (),
	ReleaseDraw: (cancelled: boolean) -> (),
	CancelDraw: () -> (),
	RequestSkill: (name: string, direction: Vector3?, touch: boolean?) -> (),
	SetBlocking: (enabled: boolean) -> (),
	SetSprinting: (enabled: boolean) -> (),
	CanBeginControl: () -> boolean,
	CanBeginSkillAim: () -> boolean,
	Ranged: () -> boolean,
	Facing: () -> Vector3,
	ScreenDirection: (delta: Vector2) -> Vector3?,
	MovementDirection: () -> Vector3?,
	MouseDirection: () -> (Vector3?, Vector3?),
	ClearPendingSkill: () -> (),
	ClearPreview: () -> (),
	ResetRequests: () -> (),
}

export type Runtime = {
	Input: UserInputService,
	Gui: GuiService,
	PlayerGui: PlayerGui,
	Parent: Instance,
}

type Touch = { Input: InputObject, Origin: Vector2, Direction: Vector3? }

type Fields = {
	Callbacks: Callbacks,
	Runtime: Runtime,
	Buttons: { [string]: TextButton },
	Knobs: { [string]: Frame },
	Cancel: Frame?,
	CancelLabel: TextLabel?,
	Aiming: SkillAim?,
	Touches: { [string]: Touch },
	TouchConnections: { [InputObject]: RBXScriptConnection },
	Connections: { RBXScriptConnection },
	Contexts: { InputContext },
	Actions: { [string]: InputAction },
	Held: { [string]: boolean },
	MouseAttack: boolean,
	Focused: boolean,
	Started: boolean,
}

type Methods = {
	new: (callbacks: Callbacks, runtime: Runtime) -> Controller,
	Bind: (self: Controller, buttons: { [string]: TextButton }, cancel: Frame) -> (),
	Start: (self: Controller) -> (),
	Sync: (self: Controller) -> (),
	Reset: (self: Controller) -> (),
	Destroy: (self: Controller) -> (),
	ClearSkillAim: (self: Controller) -> (),
	MoveSkillAim: (self: Controller, position: Vector2) -> (),
	BeginAim: (self: Controller, input: InputObject, kind: string) -> (),
	BeginSkillAim: (self: Controller, input: InputObject, name: string) -> (),
	EndAim: (self: Controller, input: InputObject) -> (),
	Move: (self: Controller, input: InputObject) -> (),
	Watch: (self: Controller, input: InputObject) -> (),
	IsAttackHeld: (self: Controller) -> boolean,
	IsTouchAttacking: (self: Controller) -> boolean,
	GetAttackAim: (self: Controller) -> Vector3?,
	GetGuardAim: (self: Controller) -> Vector3?,
	Press: (self: Controller, name: string, button: boolean?) -> (),
	Release: (self: Controller, name: string) -> (),
}

local InputActionController = {} :: Methods
local Metatable = { __index = InputActionController }
export type Controller = typeof(setmetatable({} :: Fields, Metatable))

local function MoveKnob(knob: Frame?, button: TextButton?, origin: Vector2, position: Vector2)
	if not knob or not button then
		return
	end
	local delta = position - origin
	local radius = button.AbsoluteSize.X * 0.35
	if delta.Magnitude > radius then
		delta = delta.Unit * radius
	end
	knob.Position = UDim2.new(0.5, delta.X, 0.5, delta.Y)
end

function InputActionController.new(callbacks: Callbacks, runtime: Runtime): Controller
	local self: Controller = setmetatable(
		{
			Callbacks = callbacks,
			Runtime = runtime,
			Buttons = {},
			Knobs = {},
			Cancel = nil,
			CancelLabel = nil,
			Aiming = nil,
			Touches = {},
			TouchConnections = {},
			Connections = {},
			Contexts = {},
			Actions = {},
			Held = {},
			MouseAttack = false,
			Focused = true,
			Started = false,
		} :: Fields,
		Metatable
	)
	return self
end

function InputActionController:IsAttackHeld(): boolean
	return self.Held.Attack == true or self:IsTouchAttacking()
end

function InputActionController:IsTouchAttacking(): boolean
	return self.Touches.Attack ~= nil
end

function InputActionController:GetAttackAim(): Vector3?
	local touch = self.Touches.Attack
	return if touch then touch.Direction else nil
end

function InputActionController:GetGuardAim(): Vector3?
	local touch = self.Touches.Block
	return if touch then touch.Direction else nil
end

function InputActionController:ClearSkillAim()
	local aiming = self.Aiming
	if aiming then
		local connection = self.TouchConnections[aiming.Input]
		if connection then
			connection:Disconnect()
			self.TouchConnections[aiming.Input] = nil
		end
	end
	self.Aiming = nil
	self.Callbacks.ClearPreview()
	if self.Cancel then
		self.Cancel.Visible = false
	end
	for _, name in { "RisingCrash", "GroundShock", "Charge" } do
		local knob = self.Knobs[name]
		if knob then
			knob.Visible = false
			knob.Position = UDim2.fromScale(0.5, 0.5)
		end
	end
end

function InputActionController:Reset()
	self.Callbacks.CancelDraw()
	self:ClearSkillAim()
	for _, connection in self.TouchConnections do
		connection:Disconnect()
	end
	table.clear(self.TouchConnections)
	table.clear(self.Touches)
	table.clear(self.Held)
	self.MouseAttack = false
	self.Callbacks.ClearPendingSkill()
	self.Callbacks.ResetRequests()
	for _, knob in self.Knobs do
		knob.Visible = false
		knob.Position = UDim2.fromScale(0.5, 0.5)
	end
end

function InputActionController:MoveSkillAim(position: Vector2)
	local aiming = self.Aiming
	if not aiming then
		return
	end
	aiming.Position = position
	local button = self.Buttons[aiming.Name]
	MoveKnob(self.Knobs[aiming.Name], button, aiming.Origin, position)
	if self.Callbacks.Ranged() or aiming.Name ~= "Charge" then
		aiming.Direction = if aiming.Input.UserInputType == Enum.UserInputType.MouseButton1
			then self.Callbacks.MouseDirection()
			else self.Callbacks.ScreenDirection(position - aiming.Origin)
	end
	local cancel = self.Cancel
	if cancel and button then
		local inset = self.Runtime.Gui:GetGuiInset()
		local gui = cancel:FindFirstAncestorOfClass("ScreenGui")
		local ignoresInset = gui and (gui :: ScreenGui).IgnoreGuiInset
		aiming.Cancelled = InputRules.Cancelled(
			if ignoresInset then position else position - inset,
			if ignoresInset then aiming.Origin else aiming.Origin - inset,
			button.AbsoluteSize.X,
			cancel.AbsolutePosition,
			cancel.AbsoluteSize
		)
		cancel.BackgroundColor3 = if aiming.Cancelled then Color3.fromRGB(104, 46, 40) else Color3.fromRGB(43, 31, 25)
	end
	if self.CancelLabel then
		self.CancelLabel.Text = if aiming.Cancelled then "RELEASE TO CANCEL" else "DRAG HERE TO CANCEL"
	end
end

function InputActionController:Watch(input: InputObject)
	self.TouchConnections[input] = input:GetPropertyChangedSignal("UserInputState"):Connect(function()
		if input.UserInputState == Enum.UserInputState.End or input.UserInputState == Enum.UserInputState.Cancel then
			self:EndAim(input)
		end
	end)
end

function InputActionController:BeginAim(input: InputObject, kind: string)
	-- GUI InputBegan also fires when a held touch crosses into another button.
	if input.UserInputState ~= Enum.UserInputState.Begin or self.TouchConnections[input] then
		return
	end
	if not self.Focused or not self.Callbacks.CanBeginControl() then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if kind == "Attack" or kind == "Block" then
			self:Press(kind, true)
			self:Watch(input)
		end
		return
	elseif input.UserInputType ~= Enum.UserInputType.Touch or self.Touches[kind] then
		return
	end
	local touch: Touch = {
		Input = input,
		Origin = Vector2.new(input.Position.X, input.Position.Y),
		Direction = if kind == "Block" then self.Callbacks.Facing() else nil,
	}
	self.Touches[kind] = touch
	local knob = self.Knobs[kind]
	if knob then
		knob.Visible = true
	end
	if kind == "Attack" then
		self.Callbacks.Attack()
	elseif kind == "Block" then
		self.Callbacks.SetBlocking(true)
	end
	self:Watch(input)
end

function InputActionController:BeginSkillAim(input: InputObject, name: string)
	if self.Aiming or self.TouchConnections[input] or input.UserInputState ~= Enum.UserInputState.Begin then
		return
	end
	if not self.Focused or not self.Callbacks.CanBeginSkillAim() then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end
	self.Callbacks.CancelDraw()
	local origin = if input.UserInputType == Enum.UserInputType.MouseButton1
		then self.Runtime.Input:GetMouseLocation()
		else Vector2.new(input.Position.X, input.Position.Y)
	self.Aiming = {
		Input = input,
		Name = name,
		Origin = origin,
		Position = origin,
		Direction = nil,
		Cancelled = false,
		Valid = true,
	}
	self.Callbacks.ClearPendingSkill()
	local knob = self.Knobs[name]
	if knob then
		knob.Visible = true
	end
	if self.Cancel then
		self.Cancel.Visible = true
	end
	self:MoveSkillAim(origin)
	self:Watch(input)
end

function InputActionController:EndAim(input: InputObject)
	local connection = self.TouchConnections[input]
	if connection then
		connection:Disconnect()
		self.TouchConnections[input] = nil
	end
	local position = Vector2.new(input.Position.X, input.Position.Y)
	local cancelled = input.UserInputState == Enum.UserInputState.Cancel
	local aiming = self.Aiming
	if aiming and input == aiming.Input then
		self:MoveSkillAim(
			if input.UserInputType == Enum.UserInputType.MouseButton1
				then self.Runtime.Input:GetMouseLocation()
				else position
		)
		self:ClearSkillAim()
		if
			not cancelled
			and not aiming.Cancelled
			and (self.Callbacks.Ranged() or aiming.Name ~= "Charge" or aiming.Valid)
		then
			self.Callbacks.RequestSkill(aiming.Name, aiming.Direction, input.UserInputType == Enum.UserInputType.Touch)
		end
	end
	for kind, touch in self.Touches do
		if touch.Input ~= input then
			continue
		end
		if kind == "Attack" then
			self.Callbacks.ReleaseDraw(cancelled)
		elseif kind == "Dash" and not cancelled then
			self.Callbacks.RequestSkill(
				"Dash",
				self.Callbacks.ScreenDirection(position - touch.Origin)
					or self.Callbacks.MovementDirection()
					or self.Callbacks.Facing()
			)
		elseif kind == "Block" then
			self.Callbacks.SetBlocking(false)
		end
		self.Touches[kind] = nil
		local knob = self.Knobs[kind]
		if knob then
			knob.Visible = false
		end
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if self.MouseAttack then
			self.MouseAttack = false
			self.Callbacks.ReleaseDraw(cancelled)
		end
		self:Release("Attack")
		self:Release("ButtonBlock")
	end
end

function InputActionController:Move(input: InputObject)
	local position = Vector2.new(input.Position.X, input.Position.Y)
	local aiming = self.Aiming
	if
		aiming
		and (
			input == aiming.Input
			or (
				aiming.Input.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseMovement
			)
		)
	then
		self:MoveSkillAim(
			if input.UserInputType == Enum.UserInputType.MouseMovement
				then self.Runtime.Input:GetMouseLocation()
				else position
		)
	end
	for kind, touch in self.Touches do
		if touch.Input == input then
			MoveKnob(self.Knobs[kind], self.Buttons[kind], touch.Origin, position)
			if kind == "Attack" or kind == "Block" then
				touch.Direction = self.Callbacks.ScreenDirection(position - touch.Origin) or touch.Direction
			end
		end
	end
end

local function OverButton(runtime: Runtime): boolean
	local position = runtime.Input:GetMouseLocation()
	for _, object in runtime.PlayerGui:GetGuiObjectsAtPosition(position.X, position.Y) do
		if object:IsA("GuiButton") or object.Active then
			return true
		end
	end
	return false
end

function InputActionController:Press(name: string, button: boolean?)
	if not self.Focused or not self.Callbacks.CanBeginControl() then
		return
	end
	if name == "Attack" and not button and OverButton(self.Runtime) then
		return
	end
	local key = if button and name == "Block" then "ButtonBlock" else name
	if self.Held[key] then
		return
	end
	self.Held[key] = true
	if name == "Attack" then
		self.MouseAttack = true
		self.Callbacks.Attack()
	elseif name == "Sprint" then
		self.Callbacks.SetSprinting(true)
	elseif name == "Block" then
		self.Callbacks.SetBlocking(true)
	else
		self.Callbacks.RequestSkill(name, nil, nil)
	end
end

function InputActionController:Release(name: string)
	if not self.Held[name] then
		return
	end
	self.Held[name] = nil
	-- Native Released has no cancellation state; InputEnded commits mouse draws.
	if name == "Sprint" then
		self.Callbacks.SetSprinting(false)
	elseif name == "Block" or name == "ButtonBlock" then
		self.Callbacks.SetBlocking(false)
	end
end

function InputActionController:Bind(buttons: { [string]: TextButton }, cancel: Frame)
	self.Buttons = buttons
	self.Cancel = cancel
	self.CancelLabel = cancel:WaitForChild("Label") :: TextLabel
	for _, name in { "Attack", "Dash", "Block", "RisingCrash", "GroundShock", "Charge" } do
		self.Knobs[name] = buttons[name]:WaitForChild("Aim") :: Frame
		table.insert(
			self.Connections,
			buttons[name].InputBegan:Connect(function(input)
				if name == "RisingCrash" or name == "GroundShock" or name == "Charge" then
					self:BeginSkillAim(input, name)
				else
					self:BeginAim(input, name)
				end
			end)
		)
	end
	-- Dash needs InputObject for touch drag; mouse activation remains a click.
	table.insert(
		self.Connections,
		buttons.Dash.Activated:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Touch then
				self.Callbacks.RequestSkill("Dash", nil, nil)
			end
		end)
	)
	-- Native Released cannot distinguish a completed UI click from pointer cancellation.
	table.insert(
		self.Connections,
		buttons.Spin.Activated:Connect(function()
			self.Callbacks.RequestSkill("Spin", nil, nil)
		end)
	)
end

local function AddAction(self: Controller, context: InputContext, name: string, key: Enum.KeyCode?, button: TextButton?)
	local action = Instance.new("InputAction")
	action.Name = name
	action.Type = Enum.InputActionType.Bool
	action.Enabled = true
	action.Parent = context
	self.Actions[name] = action
	if key then
		local binding = Instance.new("InputBinding")
		binding.Name = "KeyboardMouse"
		binding.KeyCode = key
		binding.Parent = action
	end
	if button then
		local binding = Instance.new("InputBinding")
		binding.Name = "Button"
		binding.UIButton = button
		binding.Parent = action
	end
	table.insert(
		self.Connections,
		action.Pressed:Connect(function()
			self:Press(name)
		end)
	)
	table.insert(
		self.Connections,
		action.Released:Connect(function()
			self:Release(name)
		end)
	)
end

function InputActionController:Sync()
	local enabled = self.Focused and self.Callbacks.CanBeginControl()
	for _, context in self.Contexts do
		context.Enabled = enabled
	end
end

function InputActionController:Start()
	if self.Started then
		return
	end
	self.Started = true
	local controls = Instance.new("InputContext")
	controls.Name = "CombatActions"
	controls.Enabled = false
	controls.Sink = false
	controls.Parent = self.Runtime.Parent
	local skills = Instance.new("InputContext")
	skills.Name = "CombatNumberSkills"
	skills.Enabled = false
	skills.Priority = SKILL_PRIORITY
	skills.Sink = true
	skills.Parent = self.Runtime.Parent
	self.Contexts = { controls, skills }
	AddAction(self, controls, "Attack", Enum.KeyCode.MouseLeftButton)
	AddAction(self, controls, "Dash", Enum.KeyCode.E)
	AddAction(self, controls, "Sprint", Enum.KeyCode.LeftShift, self.Buttons.Sprint)
	AddAction(self, controls, "Block", Enum.KeyCode.F)
	for index, name in { "RisingCrash", "Spin", "Charge", "GroundShock" } do
		AddAction(
			self,
			skills,
			name,
			({ Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four })[index],
			nil
		)
	end
	local input = self.Runtime.Input
	table.insert(
		self.Connections,
		input.InputEnded:Connect(function(object)
			self:EndAim(object)
		end)
	)
	table.insert(
		self.Connections,
		input.InputChanged:Connect(function(object)
			self:Move(object)
		end)
	)
	table.insert(
		self.Connections,
		input.WindowFocusReleased:Connect(function()
			self.Focused = false
			self:Reset()
			self:Sync()
		end)
	)
	table.insert(
		self.Connections,
		input.WindowFocused:Connect(function()
			self.Focused = true
			self:Sync()
		end)
	)
	table.insert(
		self.Connections,
		input.TextBoxFocused:Connect(function()
			self:Reset()
			self:Sync()
		end)
	)
	table.insert(
		self.Connections,
		input.TextBoxFocusReleased:Connect(function()
			self:Sync()
		end)
	)
	table.insert(
		self.Connections,
		self.Runtime.Gui.MenuOpened:Connect(function()
			self:Reset()
			self:Sync()
		end)
	)
	table.insert(
		self.Connections,
		self.Runtime.Gui.MenuClosed:Connect(function()
			self:Sync()
		end)
	)
	self:Sync()
end

function InputActionController:Destroy()
	self:Reset()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Connections)
	for _, context in self.Contexts do
		context:Destroy()
	end
	table.clear(self.Contexts)
	table.clear(self.Actions)
	self.Started = false
end

return InputActionController

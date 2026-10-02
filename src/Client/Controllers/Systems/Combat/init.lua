--!strict
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Client = require(ReplicatedStorage.Shared.Network.Client)
local Config = require(ReplicatedStorage.Shared.Combat.Config)
local Weapons = require(ReplicatedStorage.Shared.Combat.Weapons)
local SkillDefinitions = require(ReplicatedStorage.Shared.Combat.SkillDefinitions)
local Melee = require(ReplicatedStorage.Shared.Combat.Melee)
local Knockback = require(ReplicatedStorage.Shared.Utilities.Knockback)
local Audio = require(ReplicatedStorage.Shared.Utilities.AudioUtilities)
local Camera = require(script.Parent.Camera)
local Feedback = require(script.Feedback)
local CharacterAnimations = require(script.CharacterAnimations)
local SkillEffects = require(script.SkillEffects)
local Telegraphs = require(script.Telegraphs)
local StatusIndicators = require(script.StatusIndicators)
local Targeting = require(script.Targeting)
local AimPreview = require(script.AimPreview)
local ControlVisuals = require(script.Controls)
local InputRules = require(script.InputRules)
local InputActionController = require(script.InputActionController)
local RemoteCues = require(script.RemoteCues)
local BowVisuals = require(script.BowVisuals)
local MouseAim = require(script.MouseAim)
local Request = require(script.Parent.Input.Request)

local Player = Players.LocalPlayer
local LOCK = "CombatStatus"
local MOVE_STEP = "BrawlConfusedMovement"
local AIM_STEP = "BrawlAim"
local DRAG_DEADZONE = 12
local INPUT_BUFFER = 0.15
local ATTACK_NAMES = { "Slash", "Reverse" }
local M1_ATTACK = 1

export type System = {
	Init: (self: System) -> (),
	Start: (self: System) -> (),
	Attack: (self: System, direction: Vector3?) -> (),
	RisingCrash: (self: System, direction: Vector3?) -> (),
	GroundShock: (self: System, direction: Vector3?) -> (),
	Dash: (self: System, direction: Vector3?) -> (),
	Spin: (self: System) -> (),
	Charge: (self: System) -> (),
	ChargeTarget: (self: System, target: Instance?) -> (),
	RequestSkill: (self: System, slot: string, direction: Vector3?, target: Instance?) -> (),
	CastSkill: (self: System, id: string, direction: Vector3?, target: Instance?) -> (),
	PlaySkillEffect: (self: System, character: Model, id: string, direction: Vector3?, target: Instance?) -> boolean,
	RegisterSkillEffects: (self: System, id: string, handler: SkillEffects.Handler) -> boolean,
	UnregisterSkillEffects: (self: System, id: string) -> (),
	SetSprinting: (self: System, enabled: boolean) -> (),
	SetBlocking: (self: System, enabled: boolean) -> (),
	CanAct: (self: System) -> boolean,
	GetAimDirection: (self: System) -> (Vector3, Vector3?),
}

local System = {} :: System
local Character: Model? = nil
local Humanoid: Humanoid? = nil
local Root: BasePart? = nil
local Connections: { RBXScriptConnection } = {}
local StaminaFill: Frame? = nil
local StaminaLabel: TextLabel? = nil
local HealthFill: Frame? = nil
local HealthLabel: TextLabel? = nil
local Controls: Frame? = nil
local ControlsScale: UIScale? = nil
local Vitals: Frame? = nil
local Buttons: { [string]: TextButton } = {}
local Cooldowns: { [string]: TextLabel } = {}
local LocalReadyAt: { [string]: number } = {}
local PendingSkill: { Name: string, Direction: Vector3?, Touch: boolean?, Target: Instance?, Expires: number }? = nil
local InputController: InputActionController.Controller? = nil
local SettingsOpen = false
local SprintRequested = false
local SprintSent = false
local BlockRequested = false
local BlockSent = false
local Locked = false
local LocalAttackReadyAt = 0
local AttackFacingUntil = 0
local DefaultAutoRotate = true
local StrikeIndex = 0
local AttackSequence = 0
local PendingDashDirection: Vector3? = nil
local Spinning = false
local SpinStartedAt = 0
local SpinSweep = 0
local CueAt: { [string]: { Until: number, StartedAt: number, Next: number, Cues: { SkillDefinitions.Cue } } } = {}
local DrawId: number? = nil
local DrawStartedAt = 0
local DrawAcknowledged = false
local WeaponSelector: Frame? = nil
local WeaponCurrent: TextLabel? = nil
local DesktopHint: TextLabel? = nil

local function Ranged(): boolean
	return Weapons.Weapon(Character) == "Yumi"
end

local function SendSkill(slot: string, direction: Vector3, target: Instance?)
	local index = SkillDefinitions.Index(slot)
	if index then
		Client.Combat.CastSlot.Fire(index, direction, target)
	end
end

local function PlayCue(cue: SkillDefinitions.Cue)
	Feedback:Play(cue.Sound, Root, cue.Volume or 0.34)
	if cue.Shake then
		Camera:Shake(cue.Shake, cue.ShakeDuration or 0.16)
	end
end

local function CancelDraw()
	local id = DrawId
	DrawId = nil
	DrawStartedAt = 0
	DrawAcknowledged = false
	if id then
		Client.Combat.Draw.Fire(id, false)
		AimPreview:Clear()
	end
end

local function Active(attribute: string): boolean
	local character = Character
	return character ~= nil and (character:GetAttribute(attribute) :: number? or 0) > workspace:GetServerTimeNow()
end

local function Living(): boolean
	return Humanoid ~= nil and Humanoid.Health > 0 and Root ~= nil
end

local function MatchActive(): boolean
	local status = Player:GetAttribute("CaptureStatus")
	return (status == nil or status == "Playing" or status == "Practice")
		and (Character == nil or Character:GetAttribute("CaptureActive") ~= false)
end

local function Friendly(target: Model): boolean
	local team = Character and Character:GetAttribute("CaptureTeam") or Player:GetAttribute("CaptureTeam")
	local targetPlayer = Players:GetPlayerFromCharacter(target)
	local targetTeam = target:GetAttribute("CaptureTeam") or (targetPlayer and targetPlayer:GetAttribute("CaptureTeam"))
	return team ~= nil and targetTeam == team
end

local function Interrupted(): boolean
	return not Living()
		or not MatchActive()
		or SettingsOpen
		or Active("CaptureProtectedUntil")
		or Active("StunnedUntil")
		or Active("ControlDisabledUntil")
		or Active("StaggeredUntil")
		or GuiService.MenuIsOpen
		or UserInputService:GetFocusedTextBox() ~= nil
end

local SkillPresentation = SkillEffects.new({
	Sound = function(name, position, volume, context)
		if context.Skill.Weapon == "Yumi" then
			Audio.PlayAtPosition(name, position, volume)
		end
	end,
	Shake = function(amplitude, duration, context)
		if context.Skill.Weapon == "Yumi" then
			Camera:Shake(amplitude, duration)
		end
	end,
	IsLocal = function(character)
		return character == Character
	end,
	CanPresent = function(character)
		return character:GetAttribute("DungeonDowned") ~= true and (character ~= Character or MatchActive())
	end,
	OnCast = function(context)
		if
			context.Character == Character
			and context.Skill.Weapon == "Yumi"
			and context.Skill.Presentation.Animation
		then
			CharacterAnimations:Play(context.Skill.Slot, 0.04)
		end
	end,
	OnEnd = function(context)
		if context.Character == Character and context.Skill.Weapon == "Yumi" then
			CharacterAnimations:Stop(context.Skill.Slot, 0.06)
		end
	end,
})
local ObservedActors: { [Model]: boolean } = {}

local function UpdateSkillEffects()
	local visible: { [Model]: boolean } = {}
	for _, instance in CollectionService:GetTagged("Combatant") do
		if not instance:IsA("Model") then
			continue
		end
		local root = instance:FindFirstChild("HumanoidRootPart")
		if
			instance == Character
			or (Root and root and root:IsA("BasePart") and (root.Position - Root.Position).Magnitude <= 64)
		then
			visible[instance] = true
			SkillPresentation:Observe(instance)
		end
	end
	for actor in ObservedActors do
		if not visible[actor] then
			SkillPresentation:Forget(actor)
		end
	end
	ObservedActors = visible
	SkillPresentation:Step(workspace:GetServerTimeNow())
end

local function Blocked(): boolean
	return Interrupted()
		or Active("ActionRecoveryUntil")
		or Active("SpinUntil")
		or Active("ChargeUntil")
		or Active("RisingCrashUntil")
		or Active("GroundShockUntil")
end

local function MovementLocked(): boolean
	return not Living()
		or not MatchActive()
		or Active("StunnedUntil")
		or Active("ControlDisabledUntil")
		or Active("RootedUntil")
		or (Active("StaggeredUntil") and Character ~= nil and Character:GetAttribute("StaggerLevel") == "Strong")
end

local function Stamina(): number
	local character = Character
	local value = character and character:GetAttribute("Stamina")
	return if typeof(value) == "number" then value else Config.Stamina.Max
end

local function Guarding(): boolean
	return Character ~= nil and Character:GetAttribute("Blocking") == true
end

local function Recovery(): number
	local ready = Character and Character:GetAttribute("AttackReadyAt")
	local actionReady = Character and Character:GetAttribute("ActionRecoveryUntil")
	return math.max(
		LocalAttackReadyAt,
		if typeof(ready) == "number" then ready else 0,
		if typeof(actionReady) == "number" then actionReady else 0
	) - workspace:GetServerTimeNow()
end

local function SkillRecovery(name: string): number
	local now = workspace:GetServerTimeNow()
	local recovery = if name == "Dash" then 0 else Recovery()
	if Character then
		for _, attribute in
			{
				"SpinUntil",
				"ChargeUntil",
				"RisingCrashUntil",
				"GroundShockUntil",
				"DashingUntil",
				"ActionRecoveryUntil",
			}
		do
			local value = Character:GetAttribute(attribute)
			if typeof(value) == "number" then
				recovery = math.max(recovery, value - now)
			end
		end
	end
	return recovery
end

local function ReadyAt(name: string): number
	local ready = Character and Character:GetAttribute(name .. "ReadyAt")
	return math.max(LocalReadyAt[name] or 0, if typeof(ready) == "number" then ready else 0)
end

local function Flat(direction: Vector3): Vector3?
	local horizontal = Vector3.new(direction.X, 0, direction.Z)
	return if horizontal.Magnitude > 0.001 then horizontal.Unit else nil
end

local function Facing(): Vector3
	return if Root then Flat(Root.CFrame.LookVector) or Vector3.zAxis else Vector3.zAxis
end

local function ScreenDirection(delta: Vector2): Vector3?
	if delta.Magnitude < DRAG_DEADZONE then
		return nil
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	return Flat(camera.CFrame.RightVector * delta.X - camera.CFrame.UpVector * delta.Y)
end

local function MovementDirection(): Vector3?
	local humanoid = Humanoid
	return if humanoid then Flat(humanoid.MoveDirection) else nil
end

local function MouseDirection(): (Vector3?, Vector3?)
	local root = Root
	local camera = workspace.CurrentCamera
	if not root or not camera then
		return nil, nil
	end
	local ignored = CollectionService:GetTagged("Combatant")
	if Character then
		table.insert(ignored, Character)
	end
	for _, name in { "Visual", "CombatAimPreview" } do
		local visual = workspace:FindFirstChild(name)
		if visual then
			table.insert(ignored, visual)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignored
	params.RespectCanCollide = true
	return MouseAim.Direction(camera, UserInputService:GetMouseLocation(), root.Position, params)
end

local function BeginDraw()
	local definition = Weapons.Get("Yumi")
	if
		DrawId
		or not definition
		or not System:CanAct()
		or Recovery() > 0
		or Stamina() < definition.Attack.Stamina
		or (InputController and InputController.Aiming)
		or Active("RootedUntil")
		or Active("DashingUntil")
	then
		return
	end
	AttackSequence = AttackSequence % 4294967295 + 1
	DrawId = AttackSequence
	DrawStartedAt = workspace:GetServerTimeNow()
	DrawAcknowledged = false
	PendingSkill = nil
	Client.Combat.Draw.Fire(AttackSequence, true)
end

local function ReleaseDraw(cancelled: boolean)
	local id = DrawId
	if not id then
		return
	end
	if
		cancelled
		or not Ranged()
		or Interrupted()
		or Guarding()
		or BlockRequested
		or Blocked()
		or Active("RootedUntil")
		or Active("DashingUntil")
	then
		CancelDraw()
		return
	end
	local direction = Flat((InputController and InputController:GetAttackAim()) or System:GetAimDirection()) or Facing()
	DrawId = nil
	DrawStartedAt = 0
	DrawAcknowledged = false
	AimPreview:Clear()
	LocalAttackReadyAt = workspace:GetServerTimeNow() + 0.2
	Client.Combat.Release.Fire(id, direction)
end

local function SyncSkillVisuals()
	if Ranged() then
		Spinning = false
		return
	end
	local character = Character
	local spinning = character ~= nil and Active("SpinUntil")
	if spinning ~= Spinning then
		Spinning = spinning
		local skill = SkillDefinitions.Get("WindSpin")
		SpinStartedAt = if spinning and character
			then (character:GetAttribute("SpinUntil") :: number) - (if skill then skill.Duration else 0)
			else 0
		SpinSweep = 0
		if character then
			CharacterAnimations.Trail(character, spinning and skill ~= nil and skill.Presentation.Trail == true)
		end
		if spinning then
			CharacterAnimations:Play("Spin", 0.06)
		else
			CharacterAnimations:Stop("Spin", 0.08)
		end
	end
end

local function QueueSkillCues(name: string, definition: SkillDefinitions.Definition, endsAt: number)
	CueAt[name] = nil
	if #definition.Presentation.Cues > 0 then
		CueAt[name] =
			{ Until = endsAt, StartedAt = endsAt - definition.Duration, Next = 1, Cues = definition.Presentation.Cues }
	end
end

local function UpdateSkillCues()
	if Ranged() then
		table.clear(CueAt)
		return
	end
	local character = Character
	local now = workspace:GetServerTimeNow()
	for name, cue in CueAt do
		if
			not character
			or character:GetAttribute(name .. "Until") ~= cue.Until
			or cue.Until <= now
			or not Living()
			or not MatchActive()
			or Active("StunnedUntil")
			or Active("StaggeredUntil")
			or Active("ControlDisabledUntil")
		then
			CueAt[name] = nil
		else
			while cue.Next <= #cue.Cues and now >= cue.StartedAt + cue.Cues[cue.Next].At do
				PlayCue(cue.Cues[cue.Next])
				cue.Next += 1
			end
			if cue.Next > #cue.Cues then
				CueAt[name] = nil
			end
		end
	end
end

local function CancelLocalDash(character: Model, root: BasePart)
	if not root:FindFirstChild("DashVelocity") then
		return
	end
	Knockback.CancelDash(character)
	local current = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(0, current.Y, 0)
end

local function SyncStatus()
	if InputController then
		InputController:Sync()
	end
	local blocked = Blocked()
	local movementLocked = MovementLocked()
	if movementLocked ~= Locked then
		Locked = movementLocked
		if movementLocked then
			Request.Lock:Invoke(LOCK)
		else
			Request.Unlock:Invoke(LOCK)
		end
	end
	local shouldBlock = BlockRequested and not blocked and Stamina() > 0
	if shouldBlock ~= BlockSent then
		BlockSent = shouldBlock
		Client.Combat.Block.Fire(shouldBlock)
	end
	local shouldSprint = SprintRequested and DrawId == nil and not blocked and not shouldBlock and Stamina() > 0
	if shouldSprint ~= SprintSent then
		SprintSent = shouldSprint
		Client.Combat.Sprint.Fire(shouldSprint)
	end
	if StaminaFill then
		StaminaFill.Size = UDim2.fromScale(math.clamp(Stamina() / Config.Stamina.Max, 0, 1), 1)
	end
	if StaminaLabel then
		StaminaLabel.Text = "STAMINA " .. math.floor(Stamina() + 0.5)
	end
	if HealthFill and Humanoid then
		HealthFill.Size = UDim2.fromScale(math.clamp(Humanoid.Health / math.max(1, Humanoid.MaxHealth), 0, 1), 1)
	end
	if HealthLabel then
		HealthLabel.Text = if Humanoid then "HEALTH " .. math.ceil(Humanoid.Health) else "RESPAWNING"
	end
	local now = workspace:GetServerTimeNow()
	local definition = Weapons.Get(Weapons.Weapon(Character))
	ControlVisuals:Weapon(Weapons.Weapon(Character))
	if WeaponSelector then
		WeaponSelector.Visible = Weapons.CanEquip(
			Player:GetAttribute("CaptureStatus"),
			Character ~= nil and Character:GetAttribute("DungeonRunId") ~= nil
		)
		WeaponSelector.Position =
			UDim2.fromOffset(12, if UserInputService.TouchEnabled and MatchActive() then 148 else 124)
	end
	if DesktopHint then
		DesktopHint.Text = if Ranged()
			then "HOLD LMB / RELEASE SHOT   F GUARD   E DASH   1 PIERCE   2 VOLLEY   3 QUICK SHOT   4 PIN"
			else "LMB SLASH   F GUARD   E DASH   1 RISING CRASH   2 WIND SPIN   3 CHARGE   4 GROUND SHOCK"
	end
	if WeaponCurrent then
		local message = Player:GetAttribute("WeaponMessage")
		WeaponCurrent.Text = if typeof(message) == "string" and message ~= ""
			then message
			else "WEAPON: " .. Weapons.Weapon(Character)
	end
	for name, label in Cooldowns do
		local chargeRange = false
		if not Ranged() and name == "Charge" and Targeting.Target and Root then
			local targetRoot = Targeting.Target:FindFirstChild("HumanoidRootPart")
			if targetRoot and targetRoot:IsA("BasePart") then
				local offset = targetRoot.Position - Root.Position
				chargeRange = Vector3.new(offset.X, 0, offset.Z).Magnitude > Config.Charge.Range
					or math.abs(offset.Y) > 5
			end
		end
		local remaining = if name == "Attack" then Recovery() else ReadyAt(name) - now
		if name == "Spin" or name == "Charge" or name == "RisingCrash" or name == "GroundShock" then
			remaining = math.max(remaining, Recovery())
		end
		local skill = definition and definition.Skills[name]
		local cost = if skill
			then skill.Stamina
			elseif name == "Attack" and definition then definition.Attack.Stamina
			elseif name == "Dash" then Config.Stamina.Dash
			elseif name == "Spin" then Config.Spin.Stamina
			elseif name == "Charge" then Config.Charge.Stamina
			elseif name == "RisingCrash" then Config.RisingCrash.Stamina
			elseif name == "GroundShock" then Config.GroundShock.Stamina
			else 0
		local protection = Character and Character:GetAttribute("CaptureProtectedUntil")
		local protectedFor = if typeof(protection) == "number" then protection - now else 0
		local isBlock = name == "Block"
		local reason = if protectedFor > 0
			then string.format("SPAWN %.1f", protectedFor)
			elseif blocked then "WAIT"
			elseif Guarding() and not isBlock then "GUARD"
			elseif
				(
					name == "Dash"
					or (Ranged() and (skill ~= nil or name == "Attack"))
					or (not Ranged() and (name == "Charge" or name == "Spin"))
				) and Active("RootedUntil")
			then "ROOTED"
			elseif Stamina() < cost then "STAMINA"
			elseif remaining > 0 then string.format("%.1f", remaining)
			elseif not Ranged() and name == "Charge" and not Targeting.Target then "LOCK"
			elseif chargeRange then "RANGE"
			else ""
		if name == "Attack" and DrawId and definition then
			local started = Character and Character:GetAttribute("BowDrawStartedAt")
			local since = if typeof(started) == "number" and started > 0 then started else DrawStartedAt
			reason =
				string.format("%d%%", math.floor(math.clamp((now - since) / (definition.ChargeTime or 1), 0, 1) * 100))
		end
		label.Text = reason
		label.Visible = reason ~= ""
		ControlVisuals:Update(
			name,
			reason == "",
			remaining,
			(name == "Block" and shouldBlock)
				or (name == "Sprint" and shouldSprint)
				or (InputController ~= nil and InputController.Aiming ~= nil and InputController.Aiming.Name == name)
				or (name == "Attack" and DrawId ~= nil)
		)
	end
	local camera = workspace.CurrentCamera
	if ControlsScale and camera then
		ControlsScale.Scale = math.clamp(math.min(camera.ViewportSize.X / 850, camera.ViewportSize.Y / 520), 0.8, 1.15)
	end
	if Vitals then
		Vitals.Visible = MatchActive()
		Vitals.AnchorPoint = if UserInputService.TouchEnabled then Vector2.zero else Vector2.new(0.5, 1)
		Vitals.Position = if UserInputService.TouchEnabled then UDim2.fromOffset(12, 92) else UDim2.new(0.5, 0, 1, -24)
		local gui = Vitals.Parent
		local safeWidth = if gui and gui:IsA("ScreenGui") then gui.AbsoluteSize.X else 850
		local width = if UserInputService.TouchEnabled then math.clamp((safeWidth - 270) * 0.5 - 24, 96, 212) else 212
		Vitals.Size = UDim2.new(0, width, Vitals.Size.Y.Scale, Vitals.Size.Y.Offset)
	end
	if Controls then
		Controls.Visible = MatchActive()
	end
	CharacterAnimations:Guard(shouldBlock or Guarding())
end

local function ReleaseControls()
	if InputController then
		InputController:Reset()
	else
		CancelDraw()
		BlockRequested = false
		SprintRequested = false
		PendingSkill = nil
	end
	SyncStatus()
end

local function BindCharacter(character: Model)
	if Player.Character ~= character then
		return
	end
	if Character then
		SkillPresentation:Forget(Character)
		Melee:Unbind(Character)
	end
	if Humanoid then
		Humanoid.AutoRotate = DefaultAutoRotate
	end
	for _, connection in Connections do
		connection:Disconnect()
	end
	table.clear(Connections)
	CharacterAnimations:Clear()
	ReleaseControls()
	Targeting:Clear()
	table.clear(LocalReadyAt)
	table.clear(CueAt)
	LocalAttackReadyAt = 0
	AttackFacingUntil = 0
	StrikeIndex = 0
	Spinning = false
	BlockRequested = false
	BlockSent = false
	Humanoid = nil
	Root = nil
	Feedback:Bind(Character, nil)
	local humanoid = character:WaitForChild("Humanoid", 5)
	local root = character:WaitForChild("HumanoidRootPart", 5)
	if Player.Character ~= character then
		return
	end
	Character = character
	Feedback:Bind(character, nil)
	if not humanoid or not humanoid:IsA("Humanoid") or not root or not root:IsA("BasePart") then
		warn("[Combat] Character is missing Humanoid or HumanoidRootPart")
		SyncStatus()
		return
	end
	Humanoid = humanoid
	Root = root
	Feedback:Bind(character, root)
	DefaultAutoRotate = humanoid.AutoRotate
	local lastHealth = humanoid.Health
	table.insert(
		Connections,
		humanoid.HealthChanged:Connect(function(health)
			if Character == character and health < lastHealth then
				CancelLocalDash(character, root)
				Feedback:Flash(character, Color3.fromRGB(255, 95, 104), 0.38)
				Feedback:Play("Hurt", root, 0.33)
				Camera:Shake(0.42, 0.24)
			end
			lastHealth = health
		end)
	)
	local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator", 5)
	CharacterAnimations:Bind(character, animator, Ranged())
	for _, name in
		{
			"StunnedUntil",
			"StaggeredUntil",
			"StaggerLevel",
			"ControlDisabledUntil",
			"Blocking",
			"Stamina",
			"ConfusedUntil",
			"Sprinting",
			"DashingUntil",
			"RootedUntil",
			"SpinUntil",
			"ChargeUntil",
			"RisingCrashUntil",
			"GroundShockUntil",
			"AttackReadyAt",
			"BowDrawStartedAt",
			"ActionRecoveryUntil",
			"DashReadyAt",
			"SpinReadyAt",
			"ChargeReadyAt",
			"RisingCrashReadyAt",
			"GroundShockReadyAt",
			"ExposedUntil",
			"SlowUntil",
			"SlowRatio",
			"LastBlockedAt",
		}
	do
		table.insert(
			Connections,
			character:GetAttributeChangedSignal(name):Connect(function()
				if name == "BowDrawStartedAt" then
					local started = character:GetAttribute(name)
					if typeof(started) == "number" and started > 0 and DrawId then
						DrawAcknowledged = true
					elseif DrawAcknowledged then
						CancelDraw()
					end
				end
				if
					Ranged()
					and (
						name == "SpinUntil"
						or name == "ChargeUntil"
						or name == "RisingCrashUntil"
						or name == "GroundShockUntil"
					)
				then
					SyncStatus()
					return
				end
				if name == "DashingUntil" then
					if Active(name) then
						local aim = PendingDashDirection
						if aim then
							if Active("ConfusedUntil") then
								aim = -aim
							end
							root.AssemblyLinearVelocity = aim * Config.DashSpeed
								+ Vector3.yAxis * root.AssemblyLinearVelocity.Y
							PendingDashDirection = nil
						end
						Feedback:Play("Dash", Root, 0.35)
						Camera:Shake(0.15, 0.14)
					else
						PendingDashDirection = nil
						CancelLocalDash(character, root)
					end
				elseif name == "SpinUntil" then
					SyncSkillVisuals()
				elseif name == "RisingCrashUntil" or name == "GroundShockUntil" then
					local skill = if name == "RisingCrashUntil" then "RisingCrash" else "GroundShock"
					if Active(name) then
						CharacterAnimations:Play(skill, 0.04)
						local endsAt = character:GetAttribute(name) :: number
						local definition = SkillDefinitions.Resolve(Weapons.Weapon(character), skill)
						CharacterAnimations.Trail(
							character,
							definition ~= nil and definition.Presentation.Trail == true
						)
						if definition then
							QueueSkillCues(skill, definition, endsAt)
							UpdateSkillCues()
						end
					else
						CueAt[skill] = nil
						CharacterAnimations:Stop(skill, 0.06)
						CharacterAnimations.Trail(character, Spinning)
					end
				elseif name == "ChargeUntil" then
					if Active(name) then
						local skill = SkillDefinitions.Get("Charge")
						if skill then
							QueueSkillCues("Charge", skill, character:GetAttribute(name) :: number)
							UpdateSkillCues()
						end
					else
						UpdateSkillCues()
					end
					if Active(name) then
						CharacterAnimations:Play("Charge", 0.04)
					else
						CharacterAnimations:Stop("Charge", 0.06)
					end
				elseif name == "LastBlockedAt" then
					Feedback:Flash(character, Color3.fromRGB(111, 190, 255), 0.48)
					Feedback:Block(Root, true)
					Camera:Shake(0.25, 0.17)
				end
				if (name == "StunnedUntil" or name == "StaggeredUntil") and Active(name) then
					table.clear(CueAt)
					CancelLocalDash(character, root)
					if name == "StaggeredUntil" and character:GetAttribute("StaggerLevel") == "Strong" then
						Camera:Shake(0.3, 0.2)
					end
					Melee:Cancel(character)
					CharacterAnimations:StopActions(0.05)
					CharacterAnimations.Trail(character, false)
					SyncSkillVisuals()
					CharacterAnimations:Play("Impact", 0.05)
				end
				SyncStatus()
			end)
		)
	end
	table.insert(
		Connections,
		character:GetAttributeChangedSignal("Weapon"):Connect(function()
			ReleaseControls()
			task.defer(BindCharacter, character)
		end)
	)
	table.insert(
		Connections,
		character.ChildAdded:Connect(function(child)
			if child.Name == "Katana" then
				task.defer(function()
					child:WaitForChild("Sword", 5)
					if Player.Character == character and not Ranged() and child.Parent == character then
						Melee:Bind(character)
					end
				end)
			end
		end)
	)
	table.insert(Connections, humanoid.Died:Connect(SyncStatus))
	local weapon = if not Ranged() then character:WaitForChild("Katana", 5) else nil
	if weapon and Player.Character == character and not Ranged() then
		weapon:WaitForChild("Sword", 5)
		if not Melee:Bind(character) then
			warn("[Combat] Could not bind local katana hitbox")
		end
	end
	SyncStatus()
	SyncSkillVisuals()
	SkillPresentation:Observe(character)
end

local function TapAim(): Vector3
	local root = Root
	local character = Character
	if not root or not character then
		return Facing()
	end
	local weapon = character:FindFirstChild("Katana")
	local sword = weapon and weapon:FindFirstChild("Sword")
	local definition = Weapons.Get(Weapons.Weapon(Character))
	local reach = if definition and definition.IsRanged
		then definition.Range
		elseif sword and sword:IsA("BasePart") then sword.Size.Y + 1.5
		else 5
	local nearest = reach
	local aim = Facing()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	for _, target in CollectionService:GetTagged("Combatant") do
		if
			not target:IsA("Model")
			or target == character
			or Friendly(target)
			or target:GetAttribute("CaptureActive") == false
		then
			continue
		end
		local humanoid = target:FindFirstChildOfClass("Humanoid")
		local targetRoot = target:FindFirstChild("HumanoidRootPart")
		if not humanoid or humanoid.Health <= 0 or not targetRoot or not targetRoot:IsA("BasePart") then
			continue
		end
		local displacement = targetRoot.Position - root.Position
		local distance = Vector3.new(displacement.X, 0, displacement.Z).Magnitude
		if distance > nearest or distance < 0.01 or math.abs(displacement.Y) > Config.Attack.Height then
			continue
		end
		local wall = workspace:Raycast(root.Position, displacement, params)
		if wall and not wall.Instance:IsDescendantOf(target) then
			continue
		end
		nearest = distance
		aim = Flat(displacement) or aim
	end
	return aim
end

local function RequestSkill(name: string, direction: Vector3?, touch: boolean?, target: Instance?)
	local skill = SkillDefinitions.Resolve(Weapons.Weapon(Character), name)
	local isDash = name == "Dash"
	if not isDash and not skill then
		return
	end
	if Ranged() then
		CancelDraw()
	end
	local now = workspace:GetServerTimeNow()
	local decision = InputRules.Window(
		now,
		Interrupted() or Guarding() or BlockRequested or (Ranged() and Active("RootedUntil")),
		SkillRecovery(name),
		ReadyAt(name) - now,
		INPUT_BUFFER
	)
	if decision == "Reject" then
		return
	end
	if decision == "Buffer" then
		PendingSkill = {
			Name = name,
			Direction = direction,
			Touch = touch,
			Target = target,
			Expires = now + INPUT_BUFFER,
		}
		return
	end
	PendingSkill = nil
	if Ranged() and not isDash then
		if not skill or Stamina() < skill.Stamina or Active("DashingUntil") then
			return
		end
		local index = SkillDefinitions.Index(name)
		if index then
			LocalReadyAt[name] = now + 0.2
			Client.Combat.CastSlot.Fire(
				index,
				Flat(direction or Targeting:Direction() or (if touch then TapAim() else System:GetAimDirection()))
					or Facing(),
				nil
			)
		end
		return
	end
	if touch and not direction and skill and skill.Aim == "Direction" then
		direction = Targeting:Direction() or TapAim()
	end
	if name == "RisingCrash" then
		System:RisingCrash(direction)
	elseif name == "GroundShock" then
		System:GroundShock(direction)
	elseif name == "Spin" then
		System:Spin()
	elseif name == "Charge" then
		System:ChargeTarget(target)
	elseif name == "Dash" then
		System:Dash(direction)
	end
end

function System:RequestSkill(slot: string, direction: Vector3?, target: Instance?)
	RequestSkill(slot, direction, nil, target)
end

function System:CastSkill(id: string, direction: Vector3?, target: Instance?)
	local definition = SkillDefinitions.Get(id)
	if definition and definition.Weapon == Weapons.Weapon(Character) then
		RequestSkill(definition.Slot, direction, nil, target)
	end
end

function System:PlaySkillEffect(character: Model, id: string, direction: Vector3?, target: Instance?): boolean
	return SkillPresentation:Play(character, id, direction, target)
end

function System:RegisterSkillEffects(id: string, handler: SkillEffects.Handler): boolean
	return SkillPresentation:Register(id, handler)
end

function System:UnregisterSkillEffects(id: string)
	SkillPresentation:Unregister(id)
end

local function HideEditorPreview(instance: Instance)
	if instance:IsA("ScreenGui") and instance:GetAttribute("EditorPreview") == true then
		instance.Enabled = false
	end
end

local function BindControls()
	local playerGui = Player:WaitForChild("PlayerGui") :: PlayerGui
	playerGui.ChildAdded:Connect(HideEditorPreview)
	for _, child in playerGui:GetChildren() do
		HideEditorPreview(child)
	end
	local gui = playerGui:WaitForChild("CombatControls") :: ScreenGui
	gui.Enabled = true
	local controls = gui:WaitForChild("Controls") :: Frame
	Controls = controls
	ControlsScale = controls:WaitForChild("UIScale") :: UIScale
	for _, name in { "Attack", "RisingCrash", "GroundShock", "Dash", "Spin", "Charge", "Sprint", "Block" } do
		local button = controls:WaitForChild(name) :: TextButton
		Buttons[name] = button
		local cooldown = button:WaitForChild("Container"):WaitForChild("Cooldown")
		assert(
			cooldown:IsA("TextLabel"),
			cooldown:GetFullName() .. " must be a TextLabel; check for stale UI instances"
		)
		Cooldowns[name] = cooldown
		local hint = button:WaitForChild("Hint") :: TextLabel
		hint.Visible = not UserInputService.TouchEnabled
	end
	local input = InputActionController.new({
		Attack = function()
			System:Attack()
		end,
		ReleaseDraw = ReleaseDraw,
		CancelDraw = CancelDraw,
		RequestSkill = RequestSkill,
		AimMode = function(name)
			local definition = SkillDefinitions.Resolve(Weapons.Weapon(Character), name)
			return definition and definition.Aim
		end,
		SetBlocking = function(enabled)
			System:SetBlocking(enabled)
		end,
		SetSprinting = function(enabled)
			System:SetSprinting(enabled)
		end,
		CanBeginControl = function()
			return MatchActive()
				and not SettingsOpen
				and not GuiService.MenuIsOpen
				and UserInputService:GetFocusedTextBox() == nil
		end,
		CanBeginSkillAim = function()
			return not Interrupted() and not Guarding() and not BlockRequested
		end,
		Ranged = Ranged,
		Facing = Facing,
		ScreenDirection = ScreenDirection,
		MovementDirection = MovementDirection,
		MouseDirection = MouseDirection,
		ClearPendingSkill = function()
			PendingSkill = nil
		end,
		ClearPreview = function()
			AimPreview:Clear()
		end,
		ResetRequests = function()
			BlockRequested = false
			SprintRequested = false
			SyncStatus()
		end,
	}, {
		Input = UserInputService,
		Gui = GuiService,
		PlayerGui = playerGui,
		Parent = Player:WaitForChild("PlayerScripts"),
	})
	InputController = input
	input:Bind(Buttons, gui:WaitForChild("AimCancel") :: Frame)
	input:Start()
	ControlVisuals:Bind(Buttons)
	local selector = gui:WaitForChild("WeaponSelector") :: Frame
	WeaponSelector = selector
	WeaponCurrent = selector:WaitForChild("Current") :: TextLabel
	for _, id in { "Katana", "Yumi" } do
		local button = selector:WaitForChild(id) :: TextButton
		button.Activated:Connect(function()
			ReleaseControls()
			Client.Combat.Equip.Fire(id)
		end)
	end
	local vitals = gui:WaitForChild("Vitals")
	Vitals = vitals :: Frame
	local stamina = vitals:WaitForChild("Stamina")
	StaminaFill = stamina:WaitForChild("Fill") :: Frame
	StaminaLabel = stamina:WaitForChild("Value") :: TextLabel
	local health = vitals:WaitForChild("Health")
	HealthFill = health:WaitForChild("Fill") :: Frame
	HealthLabel = health:WaitForChild("Value") :: TextLabel
	local desktopHint = gui:WaitForChild("DesktopHint") :: TextLabel
	DesktopHint = desktopHint
	desktopHint.Visible = not UserInputService.TouchEnabled
	local panel = gui:WaitForChild("SettingsPanel") :: Frame
	local settings = gui:WaitForChild("Settings") :: TextButton
	settings.Activated:Connect(function()
		panel.Visible = not panel.Visible
		SettingsOpen = panel.Visible
		ReleaseControls()
	end)
	for _, setting in { { "Shake", "ReduceShake", "CAMERA SHAKE" }, { "Flashes", "ReduceFlashes", "HIT FLASHES" } } do
		local button = panel:WaitForChild(setting[1]) :: TextButton
		local function refresh()
			button.Text = setting[3] .. (if Player:GetAttribute(setting[2]) == true then ": REDUCED" else ": FULL")
		end
		button.Activated:Connect(function()
			Player:SetAttribute(setting[2], Player:GetAttribute(setting[2]) ~= true)
			refresh()
		end)
		refresh()
	end
	SyncStatus()
end

local function UpdateAim()
	local input = InputController
	local touchAim = input and input:GetAttackAim()
	if DrawId then
		if
			Blocked()
			or Guarding()
			or BlockRequested
			or Active("RootedUntil")
			or Active("DashingUntil")
			or not Ranged()
			or not Character
		then
			CancelDraw()
		else
			local direction, position = System:GetAimDirection()
			local aim = Flat(touchAim or direction) or Facing()
			if Root then
				local visualAim = if Active("ConfusedUntil") then -aim else aim
				Root.CFrame = CFrame.lookAt(Root.Position, Root.Position + visualAim)
				AimPreview:Show(
					"Attack",
					Character,
					visualAim,
					Targeting.Target,
					false,
					if touchAim then nil else position
				)
			end
		end
	end
	local aiming = input and input.Aiming
	if input and aiming then
		if Interrupted() or Guarding() or BlockRequested or not Character then
			input:ClearSkillAim()
		else
			local position: Vector3? = nil
			if
				aiming.Input.UserInputType == Enum.UserInputType.MouseButton1 and (Ranged() or aiming.Name ~= "Charge")
			then
				local direction, point = MouseDirection()
				aiming.Direction = direction
				position = point
			end
			local direction = aiming.Direction
				or Targeting:Direction()
				or (
					if aiming.Input.UserInputType == Enum.UserInputType.Touch
						then TapAim()
						else System:GetAimDirection()
				)
			aiming.Valid =
				AimPreview:Show(aiming.Name, Character, direction, Targeting.Target, aiming.Cancelled, position)
			if
				not Ranged()
				and input
				and input.CancelLabel
				and aiming.Name == "Charge"
				and not aiming.Cancelled
				and not aiming.Valid
			then
				input.CancelLabel.Text = if Targeting.Target then "CHARGE BLOCKED" else "SELECT A TARGET"
			end
		end
	end
end

local function Update(dt: number)
	local input = InputController
	BowVisuals:Step()
	Targeting:Step(dt)
	Telegraphs:Step(dt)
	StatusIndicators:Step(dt)
	RemoteCues:Step(dt)
	UpdateSkillEffects()
	Feedback:Step()
	SyncStatus()
	SyncSkillVisuals()
	UpdateSkillCues()
	local humanoid = Humanoid
	if not humanoid or humanoid.Health <= 0 then
		ReleaseControls()
		return
	end
	if not MatchActive() then
		ReleaseControls()
	end
	local guarding = (Guarding() or BlockSent) and not Blocked()
	local attackFacing = workspace:GetServerTimeNow() < AttackFacingUntil and not Blocked()
	humanoid.AutoRotate = DefaultAutoRotate
		and DrawId == nil
		and not guarding
		and not attackFacing
		and not Active("DashingUntil")
		and not Active("SpinUntil")
		and not Active("ChargeUntil")
		and not Active("RisingCrashUntil")
		and not Active("GroundShockUntil")
	if guarding and Root then
		local aim = (InputController and InputController:GetGuardAim())
			or (if UserInputService.MouseEnabled then MouseDirection() else nil)
		if aim then
			Root.CFrame = CFrame.lookAt(Root.Position, Root.Position + aim)
		end
	end
	local pending = PendingSkill
	if pending then
		if workspace:GetServerTimeNow() > pending.Expires or Interrupted() or Guarding() or BlockRequested then
			PendingSkill = nil
		elseif SkillRecovery(pending.Name) <= 0 and ReadyAt(pending.Name) <= workspace:GetServerTimeNow() then
			PendingSkill = nil
			RequestSkill(pending.Name, pending.Direction, pending.Touch, pending.Target)
		end
	end
	if
		input
		and input:IsAttackHeld()
		and not Ranged()
		and not PendingSkill
		and not input.Aiming
		and not UserInputService:GetFocusedTextBox()
		and not GuiService.MenuIsOpen
	then
		System:Attack(input:GetAttackAim())
	end
	if Spinning and Root then
		Root.CFrame *= CFrame.Angles(0, Config.Spin.TurnSpeed * dt, 0)
		local elapsed = workspace:GetServerTimeNow() - SpinStartedAt
		local skill = SkillDefinitions.Get("WindSpin")
		local cues: { SkillDefinitions.Cue } = if skill then skill.Presentation.Cues else {}
		for index, cue in cues do
			if index > SpinSweep and elapsed >= cue.At then
				SpinSweep = index
				PlayCue(cue)
			end
		end
	end
	local moving = humanoid.MoveDirection.Magnitude > 0.1
	CharacterAnimations:Locomotion(
		if not moving then "Idle" elseif Character and Character:GetAttribute("Sprinting") == true then "Run" else "Walk"
	)
	if Active("ConfusedUntil") and not Blocked() then
		local move = humanoid.MoveDirection
		if move.Magnitude > 0.01 then
			humanoid:Move(-move, false)
		end
	end
end

function System:CanAct(): boolean
	return not Blocked() and not Guarding() and not BlockRequested and not Active("AttackReadyAt")
end

function System:GetAimDirection(): (Vector3, Vector3?)
	local target = Targeting:Direction()
	if target then
		return target, nil
	end
	if UserInputService.MouseEnabled then
		local direction, position = MouseDirection()
		return direction or Facing(), position
	end
	return Facing(), nil
end

local function BeginAttack(system: System, direction: Vector3?)
	local config = Config.Attack
	local now = workspace:GetServerTimeNow()
	if not system:CanAct() or now < LocalAttackReadyAt then
		return
	end
	local defaultAim = if not direction
			and InputController
			and InputController:IsTouchAttacking()
		then Targeting:Direction() or TapAim()
		else nil
	local requestedAim = Flat(direction or defaultAim or system:GetAimDirection()) or Facing()
	local aim = if Active("ConfusedUntil") then -requestedAim else requestedAim
	local character = Character
	local humanoid = Humanoid
	local root = Root
	if not character or not humanoid or not root then
		return
	end
	LocalAttackReadyAt = now + config.Cooldown
	AttackSequence = AttackSequence % 4294967295 + 1
	local attackId = AttackSequence
	StrikeIndex = StrikeIndex % #ATTACK_NAMES + 1
	local animation = ATTACK_NAMES[StrikeIndex]
	CharacterAnimations:Play(animation, 0.03)
	Feedback:Play("Swing", root, 0.28)
	Camera:Shake(0.09, 0.11)
	root.CFrame = CFrame.lookAt(root.Position, root.Position + aim)
	AttackFacingUntil = now + config.Windup + config.Active
	humanoid.AutoRotate = false
	CharacterAnimations.Trail(character, true)
	task.delay(config.Windup + config.Active, function()
		if Character == character then
			CharacterAnimations.Trail(character, false)
		end
	end)
	Client.Combat.Attack.Fire(attackId, now, requestedAim, M1_ATTACK)
	local accented = false
	local contacted = false
	task.delay(config.Windup, function()
		if Character ~= character or Blocked() then
			return
		end
		Melee:Swing(character, aim, config.Active, function(target, _, position, hitPart)
			if Friendly(target) or target:GetAttribute("CaptureActive") == false then
				return
			end
			if Feedback:Contact(target, hitPart, not contacted, not accented) then
				accented = true
			end
			contacted = true
			Client.Combat.HitCandidate.Fire(attackId, target, workspace:GetServerTimeNow(), position)
		end)
	end)
end

function System:Attack(direction: Vector3?)
	if Ranged() then
		BeginDraw()
		return
	end
	BeginAttack(self, direction)
end

local function CanCast(system: System, name: string, cost: number): boolean
	return system:CanAct()
		and Recovery() <= 0
		and ReadyAt(name) <= workspace:GetServerTimeNow()
		and Stamina() >= cost
		and not Active("DashingUntil")
end

function System:RisingCrash(direction: Vector3?)
	local skill = SkillDefinitions.Get("RisingCrash")
	if Ranged() or not skill or not CanCast(self, skill.Slot, skill.Stamina) then
		return
	end
	LocalReadyAt.RisingCrash = workspace:GetServerTimeNow() + 0.2
	SendSkill(skill.Slot, Flat(direction or self:GetAimDirection()) or Facing(), nil)
end

function System:GroundShock(direction: Vector3?)
	local skill = SkillDefinitions.Get("GroundShock")
	if Ranged() or not skill or not CanCast(self, skill.Slot, skill.Stamina) then
		return
	end
	LocalReadyAt.GroundShock = workspace:GetServerTimeNow() + 0.2
	SendSkill(skill.Slot, Flat(direction or self:GetAimDirection()) or Facing(), nil)
end

function System:Dash(direction: Vector3?)
	if
		Blocked()
		or Guarding()
		or BlockRequested
		or Stamina() < Config.Stamina.Dash
		or ReadyAt("Dash") > workspace:GetServerTimeNow()
		or Active("RootedUntil")
	then
		return
	end
	local aim = Flat(direction or MovementDirection() or Facing()) or Facing()
	LocalReadyAt.Dash = workspace:GetServerTimeNow() + Config.DashCooldown
	PendingDashDirection = aim
	Client.Combat.Dash.Fire(aim)
end

function System:Spin()
	local skill = SkillDefinitions.Get("WindSpin")
	if
		Ranged()
		or not skill
		or Blocked()
		or Guarding()
		or BlockRequested
		or Active("RootedUntil")
		or Active("AttackReadyAt")
		or workspace:GetServerTimeNow() < LocalAttackReadyAt
		or ReadyAt("Spin") > workspace:GetServerTimeNow()
		or Stamina() < skill.Stamina
		or Active("DashingUntil")
	then
		return
	end
	LocalReadyAt.Spin = workspace:GetServerTimeNow() + skill.Cooldown
	LocalAttackReadyAt = workspace:GetServerTimeNow() + skill.Duration
	SendSkill(skill.Slot, Facing(), nil)
end

function System:Charge()
	self:ChargeTarget(nil)
end

function System:ChargeTarget(requestedTarget: Instance?)
	local skill = SkillDefinitions.Get("Charge")
	if
		Ranged()
		or not skill
		or Blocked()
		or Guarding()
		or BlockRequested
		or Active("RootedUntil")
		or Active("AttackReadyAt")
		or workspace:GetServerTimeNow() < LocalAttackReadyAt
		or ReadyAt("Charge") > workspace:GetServerTimeNow()
		or Stamina() < skill.Stamina
		or Active("DashingUntil")
	then
		return
	end
	local target = requestedTarget or Targeting.Target
	local root = Root
	local targetRoot = target and target:FindFirstChild("HumanoidRootPart")
	if not target or not target:IsA("Model") or not root or not targetRoot or not targetRoot:IsA("BasePart") then
		return
	end
	local offset = targetRoot.Position - root.Position
	if
		offset.Magnitude < 0.01
		or Vector3.new(offset.X, 0, offset.Z).Magnitude > skill.Range
		or math.abs(offset.Y) > (skill.Presentation.Height or 5)
	then
		return
	end
	-- Only reserve a short request interval; the server owns the actual cooldown.
	LocalReadyAt.Charge = workspace:GetServerTimeNow() + 0.2
	SendSkill(skill.Slot, Flat(offset) or Facing(), target)
end

function System:SetSprinting(enabled: boolean)
	SprintRequested = enabled
	SyncStatus()
end

function System:SetBlocking(enabled: boolean)
	if enabled then
		CancelDraw()
	end
	BlockRequested = enabled
	SyncStatus()
end

function System:Init()
	BowVisuals:Init()
	RunService.PreSimulation:Connect(function()
		BowVisuals:Pose()
	end)
	Targeting:Init()
	Telegraphs:Init()
	StatusIndicators:Init()
	AimPreview:Init()
	Feedback:Init()
	if Player.Character then
		task.spawn(BindCharacter, Player.Character)
	end
	Player.CharacterAdded:Connect(BindCharacter)
	Player.CharacterRemoving:Connect(function(character)
		if Character == character then
			SkillPresentation:Forget(character)
			ObservedActors[character] = nil
			ReleaseControls()
			Targeting:Clear()
			AttackFacingUntil = 0
			Spinning = false
			table.clear(CueAt)
			PendingDashDirection = nil
			Feedback:ClearCharacter(character)
			Melee:Unbind(character)
			for _, connection in Connections do
				connection:Disconnect()
			end
			table.clear(Connections)
			Character = nil
			Humanoid = nil
			Root = nil
			Feedback:Bind(nil, nil)
			CharacterAnimations:Clear()
			SyncStatus()
		end
	end)
	RunService:BindToRenderStep(MOVE_STEP, Enum.RenderPriority.Input.Value + 1, Update)
	-- The camera follows at Character + 1; project the cursor against its final frame.
	RunService:BindToRenderStep(AIM_STEP, Enum.RenderPriority.Character.Value + 2, UpdateAim)
end

function System:Start()
	BindControls()
	Client.Combat.Feedback.On(function(kind, position)
		if Root and kind == "GuardParried" then
			PendingSkill = nil
		end
		Feedback:Show(kind, position)
	end)
	Client.Combat.SkillContact.On(function(instance, blocked)
		Feedback:SkillContact(instance, blocked)
	end)
	Client.Combat.Projectile.On(function(shooter, origin, direction, speed, range, firedAt, pierceLimit)
		BowVisuals:Fire(shooter, origin, direction, speed, range, firedAt, pierceLimit)
	end)
	Client.Combat.Knockback.On(function(velocityChange)
		local character = Character
		if character and Living() and typeof(velocityChange) == "Vector3" and velocityChange.Magnitude <= 20 then
			Knockback.ApplyVelocity(character, velocityChange)
		end
	end)
end

return System

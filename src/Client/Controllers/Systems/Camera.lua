--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Player = Players.LocalPlayer

local OFFSET = Vector3.new(25, 42, 25)
local FIELD_OF_VIEW = 40
local LOOK_AHEAD = 7
local TOUCH_LOOK_AHEAD = 2
local TOUCH_FOCUS_HEIGHT = 3
local LOOK_SPEED = 4
local ZOOM_SPEED = 7
local MIN_ZOOM = 0.6
local MAX_ZOOM = 1.25
local RENDER_STEP = "BrawlCamera"
local MAX_SHAKE = 0.7

export type System = {
	Init: (self: System) -> (),
	Start: (self: System) -> (),
	SetZoom: (self: System, scale: number) -> (),
	ResetZoom: (self: System) -> (),
	Shake: (self: System, strength: number, duration: number) -> (),
}

local System = {} :: System

local LookAhead: Vector3? = nil
local Character: Model? = nil
local Zoom = 1
local TargetZoom = 1
local MotionPhase = 0
local MotionWeight = 0
local ShakeClock = 0
local ShakeRemaining = 0
local ShakeDuration = 0
local ShakeStrength = 0

local function Update(dt: number)
	local character = Player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	if not root or not root:IsA("BasePart") or not camera then
		return
	end

	if character ~= Character then
		if Character then
			Zoom = 1
			TargetZoom = 1
		end
		Character = character
		LookAhead = nil
		MotionPhase = 0
		MotionWeight = 0
		ShakeRemaining = 0
	end

	local facing = root.CFrame.LookVector
	local flatFacing = Vector3.new(facing.X, 0, facing.Z)
	local targetLookAhead = Vector3.zero
	if flatFacing.Magnitude > 0 then
		targetLookAhead = flatFacing.Unit * (if UserInputService.TouchEnabled then TOUCH_LOOK_AHEAD else LOOK_AHEAD)
	end

	local lookAlpha = 1 - math.exp(-LOOK_SPEED * dt)
	local zoomAlpha = 1 - math.exp(-ZOOM_SPEED * dt)
	local lookAhead = if LookAhead then LookAhead:Lerp(targetLookAhead, lookAlpha) else targetLookAhead
	LookAhead = lookAhead
	local focus = root.Position + lookAhead
	if UserInputService.TouchEnabled then
		-- Keep the character below the objective HUD on short landscape screens.
		focus += Vector3.yAxis * TOUCH_FOCUS_HEIGHT
	end
	Zoom += (TargetZoom - Zoom) * zoomAlpha
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local moving = humanoid ~= nil
		and humanoid.Health > 0
		and humanoid.MoveDirection.Magnitude > 0.1
		and humanoid.FloorMaterial ~= Enum.Material.Air
	local sprinting = moving and character ~= nil and character:GetAttribute("Sprinting") == true
	local targetWeight = if sprinting then 1 else if moving then 0.35 else 0
	MotionWeight += (targetWeight - MotionWeight) * (1 - math.exp(-9 * dt))
	MotionPhase += dt * (if sprinting then 15 else 10)
	local motion = Vector3.new(math.sin(MotionPhase) * 0.035, math.abs(math.cos(MotionPhase)) * 0.045, 0) * MotionWeight
	ShakeClock += dt
	ShakeRemaining = math.max(0, ShakeRemaining - dt)
	local fade = if ShakeDuration > 0 then ShakeRemaining / ShakeDuration else 0
	local shake = Vector3.new(math.sin(ShakeClock * 79), math.sin(ShakeClock * 103), 0) * ShakeStrength * fade
	local roll = math.sin(ShakeClock * 67) * ShakeStrength * fade * 0.018
	if Player:GetAttribute("ReduceShake") == true then
		motion = Vector3.zero
		shake *= 0.15
		roll = 0
	end

	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = FIELD_OF_VIEW
	camera.CFrame = CFrame.lookAt(focus + OFFSET * Zoom, focus) * CFrame.new(motion + shake) * CFrame.Angles(0, 0, roll)
	camera.Focus = CFrame.new(focus)
end

function System:Init()
	RunService:BindToRenderStep(RENDER_STEP, Enum.RenderPriority.Character.Value + 1, Update)
end

function System:Start() end

function System:SetZoom(scale: number)
	if scale ~= scale then
		return
	end
	TargetZoom = math.clamp(scale, MIN_ZOOM, MAX_ZOOM)
end

function System:ResetZoom()
	TargetZoom = 1
end

function System:Shake(strength: number, duration: number)
	if strength ~= strength or duration ~= duration or strength <= 0 or duration <= 0 then
		return
	end
	ShakeStrength = math.min(
		MAX_SHAKE,
		ShakeStrength * (if ShakeDuration > 0 then ShakeRemaining / ShakeDuration else 0) + strength
	)
	ShakeDuration = duration
	ShakeRemaining = duration
end

return System

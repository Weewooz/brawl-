--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SwiftCast = require(ReplicatedStorage.Packages.SwiftCast)
local SoundUtilities = require(ReplicatedStorage.Shared.Utilities.SoundUtilities)

local Templates = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Projectiles")
local ContainerTemplate = Templates:WaitForChild("Container")
local WeldTemplate = Templates:WaitForChild("Weld")
local TrailTemplate = Templates:WaitForChild("TrailRig")
assert(ContainerTemplate:IsA("Model"), "Assets.Projectiles.Container must be a Model")
assert(WeldTemplate:IsA("WeldConstraint"), "Assets.Projectiles.Weld must be a WeldConstraint")
assert(TrailTemplate:IsA("Folder"), "Assets.Projectiles.TrailRig must be a Folder")

local VISUAL_FOLDER_NAME = "_Projectiles"
local MAX_AGE = 0.5 -- Seconds of catch-up allowed from the shared server clock
local DRIFT = 1 / 60 -- Shortfall tolerated before re-anchoring to the shared clock
local DEBUG = false -- Temporary: prints spawn/hit telemetry to compare predict vs authority
local SIDE = if RunService:IsServer() then "Server" else "Client"

-- Definition shape used by Launch / Bouncing (decoupled from game weapon libraries)
export type Definition = {
	Speed: number,
	Acceleration: Vector3,
	Fly: {
		Time: number,
		Distance: number,
	},
	Cast: {
		Size: Vector3,
		Shape: "Block" | "Sphere"?,
	},
	Model: Instance,
	Loop: Sound?,
	Visual: {
		Color: Color3?,
		Scale: number?,
		Spin: number?,
		Trail: boolean?,
	}?,
}

export type Projectile = SwiftCast.Projectile
export type LaunchInfo = {
	Origin: Vector3,
	Obstruction: RaycastResult?,
}
export type LaunchOptions = {
	Definition: Definition,
	Origin: Vector3,
	Direction: Vector3,
	Filter: { Instance }?,
	Visual: boolean?,
	Color: Color3?, -- Optional tint (debug)
	Speed: number?,
	Velocity: Vector3?,
	Acceleration: Vector3?,
	Lifetime: number?,
	FiredAt: number?, -- Shared-clock birth time; enables per-frame re-anchoring
	UserData: any?,
	CanPierce: ((projectile: Projectile, raycastResult: RaycastResult) -> boolean)?,
	OnHit: ((projectile: Projectile, raycastResult: RaycastResult, hasPierced: boolean) -> ())?,
	OnDestroy: ((projectile: Projectile, reason: string?) -> ())?,
}

local Projectiles = {}
local LAUNCH_CLEARANCE = 0.1
local LAUNCH_CHECK_DEPTH = 0.1

Projectiles.MAX_AGE = MAX_AGE

local Tracked: { [Projectile]: number } = {} -- Projectile -> FiredAt on the shared clock

function Projectiles.NormalizeDirection(direction: any): Vector3?
	if typeof(direction) ~= "Vector3" then
		return nil
	end

	local magnitude = direction.Magnitude
	if magnitude ~= magnitude or magnitude == math.huge or magnitude < 0.001 then
		return nil
	end

	return direction.Unit
end

-- Temporary sync telemetry. Both sides emit the same shape so lines can be
-- paired by shot id and compared on age (simulated) and clock (wall time).
local function Report(stage: string, projectile: Projectile, position: Vector3, caught: number?)
	local data = projectile.UserData
	local shot = if typeof(data) == "table" then data.ShotId else nil

	print(
		string.format(
			"[Sync][%s][%s] shot=%s age=%.4f clock=%.4f caught=%.4f pos=%.2f,%.2f,%.2f",
			SIDE,
			stage,
			tostring(shot),
			projectile.Elapsed,
			workspace:GetServerTimeNow(),
			caught or 0,
			position.X,
			position.Y,
			position.Z
		)
	)
end

-- Age on the shared clock. Ping is deliberately excluded: the shooter evaluates
-- this at zero and every later receiver at its own transit, so all sims land on
-- one timeline. Any ping term would only be added by whoever measures it.
function Projectiles.Age(firedAt: number): number
	return math.clamp(workspace:GetServerTimeNow() - firedAt, 0, MAX_AGE)
end

-- SwiftCast integrates raw frame deltas, and the engine clamps those during a
-- hitch, so a stalled peer silently drops simulation time and never recovers it.
-- Stepping tracked projectiles by the shortfall keeps every side on the shared
-- clock no matter how badly its frames behave.
local function Reanchor()
	local now = workspace:GetServerTimeNow()

	-- Collect before stepping: a step can hit, detonate and spawn, and mutating
	-- Tracked mid-traversal is undefined.
	local due: { Projectile } = {}
	for projectile, firedAt in Tracked do
		if projectile._Destroyed or projectile._MarkedForDestruction then
			Tracked[projectile] = nil
		elseif now - firedAt - projectile.Elapsed > DRIFT then
			table.insert(due, projectile)
		end
	end

	for _, projectile in due do
		local firedAt = Tracked[projectile]
		if not firedAt or projectile._Destroyed or projectile._MarkedForDestruction then
			continue
		end

		local drift = math.min(now - firedAt - projectile.Elapsed, MAX_AGE)
		if drift <= 0 then
			continue
		end

		SwiftCast.StepProjectile(projectile, drift)

		if DEBUG then
			Report("Drift", projectile, projectile.Position, drift)
		end
	end
end

RunService.PostSimulation:Connect(Reanchor)

-- Fast-forward simulation so Elapsed/position match shared server time.
function Projectiles.CatchUp(projectile: Projectile, seconds: number, maxSeconds: number?)
	if projectile._Destroyed or projectile._MarkedForDestruction then
		return
	end

	local limit = maxSeconds or MAX_AGE
	local dt = math.clamp(seconds, 0, limit)
	if dt > 0 then
		SwiftCast.StepProjectile(projectile, dt)
	end

	if DEBUG then
		Report("Spawn", projectile, projectile.Position, dt)
	end
end

function Projectiles.GetVisualFolder(): Folder
	local existing = workspace:FindFirstChild(VISUAL_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = VISUAL_FOLDER_NAME
	folder.Parent = workspace
	return folder
end

local function GetRaycastParams(filter: { Instance }?): RaycastParams
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = table.clone(filter or {})
	return raycastParams
end

function Projectiles.GetLaunchInfo(
	definition: Definition,
	muzzlePosition: Vector3,
	rawDirection: Vector3,
	filter: { Instance }?
): LaunchInfo?
	local direction = Projectiles.NormalizeDirection(rawDirection)
	if not direction then
		return nil
	end

	local castSize = definition.Cast.Size
	local launchDistance = castSize.Z * 0.5 + LAUNCH_CLEARANCE
	local checkOrigin = muzzlePosition - direction * LAUNCH_CHECK_DEPTH
	local checkSize = Vector3.new(castSize.X, castSize.Y, LAUNCH_CHECK_DEPTH)
	local obstruction = workspace:Blockcast(
		CFrame.lookAlong(checkOrigin, direction),
		checkSize,
		direction * (launchDistance + LAUNCH_CHECK_DEPTH),
		GetRaycastParams(filter)
	)

	return {
		Origin = muzzlePosition + direction * launchDistance,
		Obstruction = obstruction,
	}
end

local function CreateVisual(
	definition: Definition,
	origin: Vector3,
	direction: Vector3,
	color: Color3?
): (BasePart, Instance)
	local projectileVisual: PVInstance
	local projectileTemplate = definition.Model:Clone()
	local projectilePart: BasePart
	if projectileTemplate:IsA("Tool") then
		local visualModel = ContainerTemplate:Clone()
		visualModel.Name = projectileTemplate.Name
		for _, child in projectileTemplate:GetChildren() do
			child.Parent = visualModel
		end
		projectileTemplate:Destroy()
		projectileVisual = visualModel
	elseif projectileTemplate:IsA("BasePart") or projectileTemplate:IsA("Model") then
		projectileVisual = projectileTemplate
	else
		error(`Projectile template '{projectileTemplate.Name}' must be a Tool, BasePart, or Model`)
	end

	if projectileVisual:IsA("BasePart") then
		projectilePart = projectileVisual
	else
		assert(
			projectileVisual:IsA("Model"),
			`Projectile template '{projectileVisual.Name}' must be a BasePart or Model`
		)
		local modelPart = projectileVisual.PrimaryPart or projectileVisual:FindFirstChildWhichIsA("BasePart", true)
		assert(modelPart, `Projectile template '{projectileVisual.Name}' requires a BasePart`)
		projectilePart = modelPart
		projectileVisual.PrimaryPart = projectilePart
	end

	local function prepare(part: BasePart)
		part.Anchored = false
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		if color then
			part.Color = color
		end
	end

	local visualParts: { BasePart } = {}
	for _, descendant in projectileVisual:GetDescendants() do
		if descendant:IsA("BasePart") then
			prepare(descendant)
			table.insert(visualParts, descendant)
		end
	end

	prepare(projectilePart)
	local visual = definition.Visual
	local visualScale = if visual then visual.Scale else nil
	if visualScale and visualScale ~= 1 then
		if projectileVisual:IsA("Model") then
			projectileVisual:ScaleTo(visualScale)
		else
			projectilePart.Size *= visualScale
		end
	end
	if visual and visual.Trail then
		local trailRig = TrailTemplate:Clone()
		local front = trailRig:FindFirstChild("Front")
		local back = trailRig:FindFirstChild("Back")
		local trail = trailRig:FindFirstChild("Trail")
		assert(front and front:IsA("Attachment"), "Assets.Projectiles.TrailRig.Front must be an Attachment")
		assert(back and back:IsA("Attachment"), "Assets.Projectiles.TrailRig.Back must be an Attachment")
		assert(trail and trail:IsA("Trail"), "Assets.Projectiles.TrailRig.Trail must be a Trail")
		front.Position = Vector3.new(0, 0, -projectilePart.Size.Z * 0.45)
		back.Position = Vector3.new(0, 0, projectilePart.Size.Z * 0.45)
		trail.Color = ColorSequence.new(color or projectilePart.Color)
		for _, child in trailRig:GetChildren() do
			child.Parent = projectilePart
		end
		trailRig:Destroy()
	end
	for _, part in visualParts do
		if part ~= projectilePart then
			local weld = WeldTemplate:Clone()
			weld.Part0 = projectilePart
			weld.Part1 = part
			weld.Parent = projectilePart
		end
	end
	projectilePart.Anchored = true
	projectileVisual:PivotTo(CFrame.lookAlong(origin, direction))
	projectileVisual.Parent = Projectiles.GetVisualFolder()

	return projectilePart, projectileVisual
end

function Projectiles.Launch(options: LaunchOptions): Projectile
	local direction = Projectiles.NormalizeDirection(options.Direction)
	assert(direction, "Projectiles.Launch requires a valid direction")

	local filter: { Instance } = table.clone(options.Filter or {})
	local projectilePart: BasePart? = nil
	local projectileVisual: Instance? = nil
	local definition = options.Definition
	local visual = definition.Visual
	if options.Visual then
		projectilePart, projectileVisual =
			CreateVisual(definition, options.Origin, direction, options.Color or if visual then visual.Color else nil)
		table.insert(filter, Projectiles.GetVisualFolder())
		SoundUtilities.PlayLoopedSoundTemplate(definition.Loop, projectilePart)
	end

	local cast = definition.Cast
	local castSize = cast.Size
	local sphere = cast.Shape == "Sphere"
	local projectileSettingsOptions = {
		MaxFlyTime = definition.Fly.Time,
		MaxFlyDistance = definition.Fly.Distance,
		RaycastParams = GetRaycastParams(filter),
		RaycastFunction = if sphere
			then SwiftCast.RaycastFunctions.Spherecast
			else SwiftCast.RaycastFunctions.Blockcast,
		BlockcastSize = if sphere then nil else castSize,
		SpherecastRadius = if sphere then math.min(castSize.X, castSize.Y, castSize.Z) * 0.5 else nil,
	}
	local projectileSettings = SwiftCast.ProjectileSettings.new(projectileSettingsOptions)

	local spin = if visual then visual.Spin else nil
	local projectile = SwiftCast.SpawnProjectile({
		Position = options.Origin,
		Velocity = options.Velocity or direction * (options.Speed or definition.Speed),
		Acceleration = options.Acceleration or definition.Acceleration,
		MaxFlyTime = options.Lifetime,
		ProjectilePart = projectilePart,
		UserData = options.UserData,
		CanPierce = options.CanPierce,
		OnHit = function(projectile, raycastResult, hasPierced)
			if DEBUG then
				Report("Hit", projectile, raycastResult.Position)
			end
			if options.OnHit then
				options.OnHit(projectile, raycastResult, hasPierced)
			end
		end,
		OnStep = if spin
			then function(projectile, deltaTime)
				local speed = projectile.Velocity.Magnitude
				if speed > 0.5 then
					projectile.ProjectilePartRotation *= CFrame.Angles(spin * deltaTime, spin * 0.7 * deltaTime, 0)
				end
			end
			else nil,
		OnDestroy = function(projectile, reason)
			Tracked[projectile] = nil
			if projectileVisual then
				projectileVisual:Destroy()
			end
			if options.OnDestroy then
				options.OnDestroy(projectile, reason)
			end
		end,
	}, projectileSettings)

	local firedAt = options.FiredAt
	if firedAt then
		Tracked[projectile] = firedAt
	end

	return projectile
end

function Projectiles.Terminate(projectile: Projectile, reason: string?)
	if projectile._Destroyed or projectile._MarkedForDestruction then
		return
	end

	SwiftCast.TerminateProjectile(projectile, reason)
end

return Projectiles

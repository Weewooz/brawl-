--!strict
local Projectiles = require(script.Parent)

export type Controller = {
	Projectile: Projectiles.Projectile?,
	Destroyed: boolean,
	DetonateAt: number,
	LastHit: RaycastResult?,
	Bounces: number,
	Settled: boolean,
}

export type Throwable = {
	Up: number,
}

export type LaunchOptions = {
	Definition: Projectiles.Definition,
	Origin: Vector3,
	Velocity: Vector3,
	Filter: { Instance }?,
	Visual: boolean?,
	FiredAt: number,
	Fuse: number,
	Bounciness: number,
	Settle: number,
	Bounces: number,
	Impact: "Bounce" | "Stick" | "Detonate"?,
	UserData: any?,
	OnDetonate: (controller: Controller, position: Vector3, normal: Vector3, velocity: Vector3, hit: Instance?) -> (),
}

local Bouncing = {}

function Bouncing.ThrowVelocity(
	definition: Projectiles.Definition,
	throwable: Throwable,
	direction: Vector3
): Vector3
	return direction * definition.Speed + Vector3.yAxis * throwable.Up
end

function Bouncing.Launch(options: LaunchOptions): Controller
	local controller: Controller = {
		Projectile = nil,
		Destroyed = false,
		DetonateAt = options.FiredAt + options.Fuse,
		LastHit = nil,
		Bounces = 0,
		Settled = false,
	}

	local function detonate(
		projectile: Projectiles.Projectile,
		position: Vector3?,
		normal: Vector3?,
		hitInstance: Instance?
	)
		if controller.Destroyed then
			return
		end
		controller.Destroyed = true
		local lastHit = controller.LastHit
		options.OnDetonate(
			controller,
			position or projectile.Position,
			normal or if lastHit then lastHit.Normal else Vector3.yAxis,
			projectile.Velocity,
			hitInstance or if lastHit then lastHit.Instance else nil
		)
	end

	local launchSegment: (Vector3, Vector3, number, boolean?) -> ()
	launchSegment = function(origin: Vector3, velocity: Vector3, firedAt: number, settled: boolean?)
		if controller.Destroyed then
			return
		end

		local age = Projectiles.Age(firedAt)
		local lifetime = math.max(controller.DetonateAt - workspace:GetServerTimeNow() + age, 0.001)
		local direction = if velocity.Magnitude > 0.001 then velocity.Unit else Vector3.yAxis
		local projectile = Projectiles.Launch({
			Definition = options.Definition,
			Origin = origin,
			Direction = direction,
			Velocity = velocity,
			Acceleration = if settled then Vector3.zero else nil,
			Lifetime = lifetime,
			Filter = options.Filter,
			Visual = options.Visual,
			FiredAt = firedAt,
			UserData = options.UserData,
			CanPierce = if settled
				then nil
				else function()
					return true
				end,
			OnHit = if settled
				then nil
				else function(activeProjectile, hit)
					if controller.Destroyed or controller.Projectile ~= activeProjectile then
						return
					end

					controller.LastHit = hit
					controller.Bounces += 1
					Projectiles.Terminate(activeProjectile, "Bounced")
					local impact = options.Impact or "Bounce"
					if impact == "Detonate" then
						detonate(activeProjectile, hit.Position, hit.Normal, hit.Instance)
						return
					end

					local reflected = activeProjectile.Velocity
						- hit.Normal * (2 * activeProjectile.Velocity:Dot(hit.Normal))
					local speed = reflected.Magnitude * options.Bounciness
					local castSize = options.Definition.Cast.Size
					local clearance = math.max(castSize.X, castSize.Y, castSize.Z) * 0.5 + 0.05
					local shouldSettle = impact == "Stick"
						or controller.Bounces >= options.Bounces
						or (hit.Normal.Y > 0.45 and speed <= options.Settle)
					local nextOrigin = hit.Position + hit.Normal * clearance
					if shouldSettle then
						controller.Settled = true
						launchSegment(nextOrigin, Vector3.zero, workspace:GetServerTimeNow(), true)
					elseif speed > 0.001 then
						launchSegment(nextOrigin, reflected.Unit * speed, workspace:GetServerTimeNow())
					else
						controller.Settled = true
						launchSegment(nextOrigin, Vector3.zero, workspace:GetServerTimeNow(), true)
					end
				end,
			OnDestroy = function(activeProjectile, reason)
				if controller.Projectile == activeProjectile then
					controller.Projectile = nil
				end
				if reason == "MaxTime" or reason == "MaxDistance" then
					detonate(activeProjectile)
				end
			end,
		})
		controller.Projectile = projectile
		Projectiles.CatchUp(projectile, age, lifetime)
	end

	launchSegment(options.Origin, options.Velocity, options.FiredAt)
	return controller
end

function Bouncing.Terminate(controller: Controller, reason: string?)
	if controller.Destroyed then
		return
	end
	controller.Destroyed = true
	if controller.Projectile then
		Projectiles.Terminate(controller.Projectile, reason or "Terminated")
	end
end

return Bouncing

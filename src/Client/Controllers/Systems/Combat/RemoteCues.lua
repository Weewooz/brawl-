--!strict
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Audio = require(ReplicatedStorage.Shared.Utilities.AudioUtilities)
local Config = require(ReplicatedStorage.Shared.Combat.Config)
local Weapons = require(ReplicatedStorage.Shared.Combat.Weapons)
local Player = Players.LocalPlayer
local INTERVAL = 1 / 30
local RANGE = 64
local TIMING = {
	RisingCrash = { Duration = Config.RisingCrash.Duration, Times = { Config.RisingCrash.Windup }, Cue = "RisingCrash" },
	GroundShock = { Duration = Config.GroundShock.Duration, Times = { Config.GroundShock.Windup }, Cue = "GroundShock" },
	Spin = {
		Duration = Config.Spin.Duration,
		Times = { Config.Spin.FirstHit, Config.Spin.FirstHit + Config.Spin.Interval },
		Cue = "WindSpin",
	},
	Charge = { Duration = Config.Charge.Duration, Times = { 0 }, Cue = "Charge" },
}

type Cue = { Until: number, Next: number }

export type System = {
	Elapsed: number,
	Actors: { [Model]: { [string]: Cue } },
	Step: (self: System, dt: number) -> (),
}

local RemoteCues: System = { Elapsed = 0, Actors = {} }

local function Active(character: Model, attribute: string, now: number): boolean
	local value = character:GetAttribute(attribute)
	return typeof(value) == "number" and value > now
end

function RemoteCues:Step(dt: number)
	self.Elapsed += dt
	if self.Elapsed < INTERVAL then
		return
	end
	self.Elapsed %= INTERVAL
	local character = Player.Character
	local origin = character and character:FindFirstChild("HumanoidRootPart")
	if not origin or not origin:IsA("BasePart") then
		table.clear(self.Actors)
		return
	end
	local now = workspace:GetServerTimeNow()
	local seen: { [Model]: boolean } = {}
	for _, instance in CollectionService:GetTagged("Combatant") do
		if
			not instance:IsA("Model")
			or instance == character
			or not instance:IsDescendantOf(workspace)
			or Weapons.Weapon(instance) == "Yumi"
		then
			continue
		end
		local humanoid = instance:FindFirstChildOfClass("Humanoid")
		local root = instance:FindFirstChild("HumanoidRootPart")
		if
			not humanoid
			or humanoid.Health <= 0
			or not root
			or not root:IsA("BasePart")
			or instance:GetAttribute("CaptureActive") == false
			or (root.Position - origin.Position).Magnitude > RANGE
			or Active(instance, "StaggeredUntil", now)
			or Active(instance, "StunnedUntil", now)
			or Active(instance, "ControlDisabledUntil", now)
		then
			continue
		end
		seen[instance] = true
		local cues = self.Actors[instance]
		if not cues then
			cues = {}
			self.Actors[instance] = cues
		end
		for name, timing in TIMING do
			local endsAt = instance:GetAttribute(name .. "Until")
			if typeof(endsAt) ~= "number" or endsAt <= now then
				cues[name] = nil
				continue
			end
			local cue = cues[name]
			local startedAt = endsAt - timing.Duration
			if not cue or cue.Until ~= endsAt then
				cue = { Until = endsAt, Next = 1 }
				cues[name] = cue
				-- Entering audible range during a cast must not replay earlier impacts.
				local tolerance = if name == "Charge" then 0.12 else INTERVAL
				while cue.Next <= #timing.Times and startedAt + timing.Times[cue.Next] < now - tolerance do
					cue.Next += 1
				end
			end
			while cue.Next <= #timing.Times and now >= startedAt + timing.Times[cue.Next] do
				Audio.PlayAtPart(timing.Cue, root, if name == "GroundShock" then 0.28 else 0.24)
				cue.Next += 1
			end
		end
	end
	for actor in self.Actors do
		if not seen[actor] then
			self.Actors[actor] = nil
		end
	end
end

return RemoteCues

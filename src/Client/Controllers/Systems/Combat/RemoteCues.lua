--!strict
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Audio = require(ReplicatedStorage.Shared.Utilities.AudioUtilities)
local SkillDefinitions = require(ReplicatedStorage.Shared.Combat.SkillDefinitions)
local Weapons = require(ReplicatedStorage.Shared.Combat.Weapons)
local Player = Players.LocalPlayer
local INTERVAL = 1 / 30
local RANGE = 64

type Cue = { Until: number, Next: number }

export type System = {
	Elapsed: number,
	Actors: { [Model]: { [string]: Cue } },
	Step: (self: System, dt: number) -> (),
}

local RemoteCues = { Elapsed = 0, Actors = {} } :: System

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
		if not instance:IsA("Model") or instance == character or not instance:IsDescendantOf(workspace) then
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
			or Weapons.Weapon(instance) == "Yumi"
		then
			continue
		end
		seen[instance] = true
		local cues = self.Actors[instance]
		if not cues then
			cues = {}
			self.Actors[instance] = cues
		end
		local skills = SkillDefinitions.ForWeapon(Weapons.Weapon(instance))
		if not skills then
			continue
		end
		for name, skill in skills do
			local timeline = skill.Presentation.Cues
			if #timeline == 0 then
				cues[name] = nil
				continue
			end
			local endsAt = instance:GetAttribute(name .. "Until")
			if typeof(endsAt) ~= "number" or endsAt <= now then
				cues[name] = nil
				continue
			end
			local cue = cues[name]
			local startedAt = endsAt - skill.Duration
			local current: Cue = if cue and cue.Until == endsAt then cue else { Until = endsAt, Next = 1 }
			if current ~= cue then
				cues[name] = current
				-- Entering audible range during a cast must not replay earlier impacts.
				local tolerance = if timeline[1].At == 0 then 0.12 else INTERVAL
				while current.Next <= #timeline and startedAt + timeline[current.Next].At < now - tolerance do
					current.Next += 1
				end
			end
			while current.Next <= #timeline and now >= startedAt + timeline[current.Next].At do
				local event = timeline[current.Next]
				Audio.PlayAtPart(event.Sound, root, event.RemoteVolume or event.Volume or 0.24)
				current.Next += 1
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

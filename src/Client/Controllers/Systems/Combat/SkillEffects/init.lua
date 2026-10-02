--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkillDefinitions = require(ReplicatedStorage.Shared.Combat.SkillDefinitions)
local Templates = require(script.Templates)

export type Context = {
	Character: Model,
	Skill: SkillDefinitions.Definition,
	Direction: Vector3?,
	Target: Instance?,
	Position: Vector3,
	StartedAt: number,
	EndsAt: number,
}
export type Handler = {
	OnCast: ((context: Context) -> ())?,
	OnImpact: ((context: Context) -> ())?,
	OnEnd: ((context: Context, cancelled: boolean) -> ())?,
}
export type Callbacks = {
	OnCast: ((context: Context) -> ())?,
	OnEnd: ((context: Context, cancelled: boolean) -> ())?,
	Sound: ((name: string, position: Vector3, volume: number, context: Context) -> ())?,
	Shake: ((amplitude: number, duration: number, context: Context) -> ())?,
	IsLocal: ((character: Model) -> boolean)?,
	CanPresent: ((character: Model) -> boolean)?,
}

type Cast = {
	Context: Context,
	Handler: Handler?,
	NextCue: number,
	ImpactPlayed: boolean,
	Observed: boolean,
	Effects: { Templates.Effect },
}
type Actor = { Seen: { [string]: number }, Casts: { [string]: Cast }, Observed: boolean }
type Fields = {
	Callbacks: Callbacks,
	Handlers: { [string]: Handler },
	Actors: { [Model]: Actor },
	Finished: { Templates.Effect },
}
type Methods = {
	new: (callbacks: Callbacks?) -> Controller,
	Play: (self: Controller, character: Model, skillId: string, direction: Vector3?, target: Instance?) -> boolean,
	Register: (self: Controller, skillId: string, handler: Handler) -> boolean,
	Unregister: (self: Controller, skillId: string) -> (),
	Observe: (self: Controller, character: Model) -> (),
	Forget: (self: Controller, character: Model) -> (),
	Step: (self: Controller, now: number) -> (),
	Destroy: (self: Controller) -> (),
}
local SkillEffects = {} :: Methods
local Metatable = { __index = SkillEffects }
export type Controller = typeof(setmetatable({} :: Fields, Metatable))

local function Root(character: Model): BasePart?
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function Active(character: Model, name: string, now: number): boolean
	local value = character:GetAttribute(name)
	return typeof(value) == "number" and value > now
end

local function Present(self: Controller, character: Model, now: number): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return character:IsDescendantOf(workspace)
		and humanoid ~= nil
		and humanoid.Health > 0
		and Root(character) ~= nil
		and character:GetAttribute("CaptureActive") ~= false
		and character:GetAttribute("Blocking") ~= true
		and not (character:GetAttribute("Weapon") == "Yumi" and Active(character, "RootedUntil", now))
		and not Active(character, "StunnedUntil", now)
		and not Active(character, "StaggeredUntil", now)
		and not Active(character, "ControlDisabledUntil", now)
		and (self.Callbacks.CanPresent == nil or self.Callbacks.CanPresent(character))
end

local function Invoke(callback: ((Context) -> ())?, context: Context)
	if callback then
		xpcall(callback, function(message: unknown)
			warn("[Combat.SkillEffects] " .. context.Skill.Id .. " callback failed: " .. tostring(message))
		end, context)
	end
end

local function Spawn(cast: Cast, name: string?, now: number)
	local context = cast.Context
	local root = Root(context.Character)
	if name and root then
		local effect = Templates.Spawn(name, root, context.Position, context.Direction, now, context.Skill.Duration)
		if effect then
			table.insert(cast.Effects, effect)
		end
	end
end

local function InvokeEnd(callback: ((Context, boolean) -> ())?, context: Context, cancelled: boolean)
	if callback then
		xpcall(callback, function(message: unknown)
			warn("[Combat.SkillEffects] " .. context.Skill.Id .. " end callback failed: " .. tostring(message))
		end, context, cancelled)
	end
end

local function End(self: Controller, cast: Cast, cancelled: boolean)
	for _, effect in cast.Effects do
		if cancelled then
			Templates.Destroy(effect)
		else
			table.insert(self.Finished, effect)
		end
	end
	table.clear(cast.Effects)
	local handler = cast.Handler
	InvokeEnd(self.Callbacks.OnEnd, cast.Context, cancelled)
	InvokeEnd(if handler then handler.OnEnd else nil, cast.Context, cancelled)
end

local function Begin(
	self: Controller,
	character: Model,
	actor: Actor,
	key: string,
	definition: SkillDefinitions.Definition,
	startedAt: number,
	endsAt: number,
	direction: Vector3?,
	target: Instance?,
	observed: boolean,
	initial: boolean,
	now: number
)
	local previous = actor.Casts[key]
	if previous then
		End(self, previous, true)
	end
	local root = Root(character)
	if not root then
		return
	end
	local context: Context = {
		Character = character,
		Skill = definition,
		Direction = direction or root.CFrame.LookVector,
		Target = target,
		Position = root.Position,
		StartedAt = startedAt,
		EndsAt = endsAt,
	}
	local cast: Cast = {
		Context = context,
		Handler = self.Handlers[definition.Id],
		NextCue = 1,
		ImpactPlayed = initial and startedAt + definition.Windup < now,
		Observed = observed,
		Effects = {},
	}
	actor.Casts[key] = cast
	if initial then
		while
			cast.NextCue <= #definition.Presentation.Cues
			and startedAt + definition.Presentation.Cues[cast.NextCue].At < now
		do
			cast.NextCue += 1
		end
	else
		Spawn(cast, definition.Presentation.Effects.Cast, now)
		Invoke(self.Callbacks.OnCast, context)
		Invoke(if cast.Handler then cast.Handler.OnCast else nil, context)
	end
end

local function Read(self: Controller, character: Model, actor: Actor, now: number, initial: boolean)
	local weapon = if character:GetAttribute("Weapon") == "Yumi" then "Yumi" else "Katana"
	for _, slot in SkillDefinitions.Slots do
		local definition = SkillDefinitions.Resolve(weapon, slot)
		local untilValue = character:GetAttribute(slot .. "Until")
		local endsAt = if typeof(untilValue) == "number" then untilValue else 0
		local token = endsAt
		local startedAt = if definition then endsAt - definition.Duration else 0
		local directionValue = character:GetAttribute(slot .. "Direction")
		local direction = if typeof(directionValue) == "Vector3" then directionValue else nil
		if weapon == "Yumi" then
			local skillId = character:GetAttribute("SkillId")
			local sequence = character:GetAttribute("SkillSequence")
			local started = character:GetAttribute("SkillStartedAt")
			local ending = character:GetAttribute("SkillUntil")
			if definition and skillId == definition.Id then
				token = if typeof(sequence) == "number" then sequence else 0
				startedAt = if typeof(started) == "number" then started else 0
				endsAt = if typeof(ending) == "number" then ending else 0
				local skillDirection = character:GetAttribute("SkillDirection")
				direction = if typeof(skillDirection) == "Vector3" then skillDirection else nil
			else
				token = 0
				endsAt = 0
			end
		end
		if actor.Seen[slot] ~= token then
			actor.Seen[slot] = token
			if definition and endsAt > now and Present(self, character, now) then
				Begin(self, character, actor, slot, definition, startedAt, endsAt, direction, nil, true, initial, now)
			end
		end
		local cast = actor.Casts[slot]
		if cast and cast.Observed and (not definition or definition.Id ~= cast.Context.Skill.Id or endsAt <= now) then
			End(self, cast, now < cast.Context.EndsAt)
			actor.Casts[slot] = nil
		end
	end
end

function SkillEffects.new(callbacks: Callbacks?): Controller
	local self: Controller =
		setmetatable({ Callbacks = callbacks or {}, Handlers = {}, Actors = {}, Finished = {} }, Metatable)
	return self
end

function SkillEffects:Register(skillId: string, handler: Handler): boolean
	if not SkillDefinitions.Get(skillId) then
		return false
	end
	self.Handlers[skillId] = handler
	return true
end

function SkillEffects:Unregister(skillId: string)
	self.Handlers[skillId] = nil
end

function SkillEffects:Play(character: Model, skillId: string, direction: Vector3?, target: Instance?): boolean
	local definition = SkillDefinitions.Get(skillId)
	local now = workspace:GetServerTimeNow()
	if not definition or not Present(self, character, now) then
		return false
	end
	if
		direction
		and (
			direction.X ~= direction.X
			or direction.Y ~= direction.Y
			or direction.Z ~= direction.Z
			or direction.Magnitude == math.huge
		)
	then
		return false
	end
	local actor = self.Actors[character]
	if not actor then
		actor = { Seen = {}, Casts = {}, Observed = false }
		self.Actors[character] = actor
	end
	Begin(
		self,
		character,
		actor,
		"Manual" .. skillId,
		definition,
		now,
		now + definition.Duration,
		direction,
		target,
		false,
		false,
		now
	)
	return true
end

function SkillEffects:Observe(character: Model)
	local actor = self.Actors[character]
	if not actor then
		actor = { Seen = {}, Casts = {}, Observed = false }
		self.Actors[character] = actor
	end
	if not actor.Observed then
		actor.Observed = true
		Read(self, character, actor, workspace:GetServerTimeNow(), true)
	end
end

function SkillEffects:Forget(character: Model)
	local actor = self.Actors[character]
	if actor then
		self.Actors[character] = nil
		for _, cast in actor.Casts do
			End(self, cast, true)
		end
	end
end

function SkillEffects:Step(now: number)
	if now ~= now or math.abs(now) == math.huge then
		return
	end
	for character, actor in self.Actors do
		if not Present(self, character, now) then
			for key, cast in actor.Casts do
				End(self, cast, true)
				actor.Casts[key] = nil
			end
			if not character:IsDescendantOf(workspace) then
				self.Actors[character] = nil
			elseif actor.Observed then
				Read(self, character, actor, now, false)
			end
			continue
		end
		if actor.Observed then
			Read(self, character, actor, now, false)
		end
		for key, cast in actor.Casts do
			local context = cast.Context
			if now >= context.EndsAt then
				End(self, cast, false)
				actor.Casts[key] = nil
				continue
			end
			local root = Root(character)
			if root then
				context.Position = root.Position
			end
			if not cast.ImpactPlayed and now >= context.StartedAt + context.Skill.Windup then
				cast.ImpactPlayed = true
				Spawn(cast, context.Skill.Presentation.Effects.Impact, now)
				Invoke(if cast.Handler then cast.Handler.OnImpact else nil, context)
			end
			local cues = context.Skill.Presentation.Cues
			while cast.NextCue <= #cues and now >= context.StartedAt + cues[cast.NextCue].At do
				local cue = cues[cast.NextCue]
				cast.NextCue += 1
				if self.Callbacks.Sound then
					local isLocal = not self.Callbacks.IsLocal or self.Callbacks.IsLocal(character)
					local volume = if isLocal then cue.Volume else cue.RemoteVolume
					self.Callbacks.Sound(cue.Sound, context.Position, volume or cue.Volume or 0.34, context)
				end
				if
					cue.Shake
					and self.Callbacks.Shake
					and self.Callbacks.IsLocal
					and self.Callbacks.IsLocal(character)
				then
					self.Callbacks.Shake(cue.Shake, cue.ShakeDuration or 0.16, context)
				end
			end
			for index = #cast.Effects, 1, -1 do
				local effect = cast.Effects[index]
				if now >= effect.Until then
					Templates.Destroy(effect)
					table.remove(cast.Effects, index)
				end
			end
		end
	end
	for index = #self.Finished, 1, -1 do
		local effect = self.Finished[index]
		if now >= effect.Until then
			Templates.Destroy(effect)
			table.remove(self.Finished, index)
		end
	end
end

function SkillEffects:Destroy()
	for character in self.Actors do
		self:Forget(character)
	end
	for _, effect in self.Finished do
		Templates.Destroy(effect)
	end
	table.clear(self.Finished)
	table.clear(self.Handlers)
end

return SkillEffects

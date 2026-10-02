--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SkillDefinitions = require(ReplicatedStorage.Shared.Combat.SkillDefinitions)
local AnimationAssets = ReplicatedStorage.Assets:WaitForChild("CombatAnimations")
local ATTACK_NAMES = { "Slash", "Reverse" }

export type CharacterAnimations = {
	Bind: (self: CharacterAnimations, character: Model, animator: Instance?, ranged: boolean) -> (),
	Clear: (self: CharacterAnimations) -> (),
	Locomotion: (self: CharacterAnimations, name: string) -> (),
	Guard: (self: CharacterAnimations, enabled: boolean) -> (),
	Play: (self: CharacterAnimations, name: string, fade: number) -> (),
	Stop: (self: CharacterAnimations, name: string, fade: number) -> (),
	StopActions: (self: CharacterAnimations, fade: number) -> (),
	Trail: (character: Model, enabled: boolean) -> (),
}

local CharacterAnimations = {} :: CharacterAnimations
local Tracks: { [string]: AnimationTrack } = {}
local DefaultConnection: RBXScriptConnection? = nil

function CharacterAnimations:Clear()
	if DefaultConnection then
		DefaultConnection:Disconnect()
		DefaultConnection = nil
	end
	for _, track in Tracks do
		track:Stop(0)
		track:Destroy()
	end
	table.clear(Tracks)
end

local function LoadTrack(
	animator: Animator,
	name: string,
	priority: Enum.AnimationPriority,
	looped: boolean,
	sourceName: string?
)
	local source = sourceName or name
	local animation = AnimationAssets:FindFirstChild(source)
	if not animation or not animation:IsA("Animation") then
		warn("[Combat] Missing preauthored CombatAnimations." .. source)
		return
	end
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok then
		warn("[Combat] Could not load RPG animation " .. source .. ": " .. tostring(track))
		return
	end
	track.Priority = priority
	track.Looped = looped
	Tracks[name] = track
end

function CharacterAnimations:Locomotion(name: string)
	for _, key in { "Idle", "Walk", "Run" } do
		local track = Tracks[key]
		if track then
			if key == name then
				if not track.IsPlaying then
					track:Play(0.15)
				end
			elseif track.IsPlaying then
				track:Stop(0.15)
			end
		end
	end
end

function CharacterAnimations.Trail(character: Model, enabled: boolean)
	local weapon = character:FindFirstChild("Katana")
	if not weapon then
		return
	end
	for _, descendant in weapon:GetDescendants() do
		if descendant:IsA("Trail") then
			descendant.Enabled = enabled
		end
	end
end

function CharacterAnimations:Bind(character: Model, animator: Instance?, ranged: boolean)
	if animator and animator:IsA("Animator") and not ranged then
		LoadTrack(animator, "Idle", Enum.AnimationPriority.Idle, true)
		LoadTrack(animator, "Walk", Enum.AnimationPriority.Movement, true)
		LoadTrack(animator, "Run", Enum.AnimationPriority.Movement, true)
		LoadTrack(animator, "Impact", Enum.AnimationPriority.Action, false)
		LoadTrack(animator, "Guard", Enum.AnimationPriority.Action2, true)
		for _, name in ATTACK_NAMES do
			LoadTrack(animator, name, Enum.AnimationPriority.Action3, false)
		end
	elseif animator and animator:IsA("Animator") then
		LoadTrack(animator, "Impact", Enum.AnimationPriority.Action, false)
	else
		warn("[Combat] Character Animator unavailable")
	end
	if animator and animator:IsA("Animator") then
		local skills = SkillDefinitions.ForWeapon(if ranged then "Yumi" else "Katana")
		if skills then
			for _, slot in SkillDefinitions.Slots do
				local presentation = skills[slot].Presentation
				if presentation.Animation then
					LoadTrack(
						animator,
						slot,
						Enum.AnimationPriority.Action3,
						presentation.Looped == true,
						presentation.Animation
					)
				end
			end
		end
	end
	local animate = character:FindFirstChild("Animate")
	if animate and animate:IsA("LocalScript") and ranged then
		animate.Enabled = true
	end
	if
		animate
		and animate:IsA("LocalScript")
		and animator
		and animator:IsA("Animator")
		and Tracks.Idle
		and Tracks.Walk
		and Tracks.Run
	then
		animate.Enabled = false
		local function stopDefault(track: AnimationTrack)
			if
				track ~= Tracks.Idle
				and track ~= Tracks.Walk
				and track ~= Tracks.Run
				and track.Priority.Value <= Enum.AnimationPriority.Movement.Value
			then
				track:Stop(0.15)
			end
		end
		for _, track in animator:GetPlayingAnimationTracks() do
			stopDefault(track)
		end
		DefaultConnection = animator.AnimationPlayed:Connect(stopDefault)
	end
end

function CharacterAnimations:Play(name: string, fade: number)
	local track = Tracks[name]
	if track then
		track:Play(fade)
	end
end

function CharacterAnimations:Stop(name: string, fade: number)
	local track = Tracks[name]
	if track then
		track:Stop(fade)
	end
end

function CharacterAnimations:StopActions(fade: number)
	for _, track in Tracks do
		if track.Priority == Enum.AnimationPriority.Action3 then
			track:Stop(fade)
		end
	end
end

function CharacterAnimations:Guard(enabled: boolean)
	local guard = Tracks.Guard
	if guard then
		if enabled and not guard.IsPlaying then
			guard:Play(0.08)
		elseif not enabled and guard.IsPlaying then
			guard:Stop(0.08)
		end
	end
end

return CharacterAnimations

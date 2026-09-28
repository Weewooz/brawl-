--!strict
local RunService = game:GetService("RunService")

local AnimationHandler = {}

export type AnimationSettings = {
	FadeTime: number?,
	Weight: number?,
	Speed: number?,
	Looped: boolean?,
	Priority: Enum.AnimationPriority?,
}

type LoadedAnimation = {
	Track: AnimationTrack,
	Animation: Animation,
}

type RegisteredAnimator = {
	Animator: Animator,
	LoadedAnimations: { [string]: LoadedAnimation }, -- Keyed by AnimationId
}
local RegisteredAnimators: { [Animator]: RegisteredAnimator } = {}

local AnimationIdTags: { [string]: { [string]: true } } = {}
local TRACK_SOFT = 48 -- Leave headroom under Roblox's 64 AnimationTrack limit

--==========================-- Private Functions --==========================--

local function GetTagList(tagOrTagList: string | { string }): { string }
	local tagList = {}

	if type(tagOrTagList) == "string" then
		table.insert(tagList, tagOrTagList)
	elseif type(tagOrTagList) == "table" then
		for _, tag in tagOrTagList do
			table.insert(tagList, tag)
		end
	end

	return tagList
end

local function GetAnimationTags(animation: Animation): { [string]: true }
	return AnimationIdTags[animation.AnimationId] or {}
end

local function GetRegisteredAnimator(animator: Animator): RegisteredAnimator?
	return RegisteredAnimators[animator]
end

local function RegisterAnimator(animator: Animator): RegisteredAnimator
	local registeredAnimator = {
		Animator = animator,
		LoadedAnimations = {},
	}
	RegisteredAnimators[animator] = registeredAnimator

	animator.AncestryChanged:Connect(function(_child: Instance, parent: Instance?)
		if not parent then
			RegisteredAnimators[animator] = nil
		end
	end)

	return registeredAnimator
end

local function GetOrSetRegisteredAnimator(animator: Animator): RegisteredAnimator
	local existingRegisteredAnimator = GetRegisteredAnimator(animator)

	if existingRegisteredAnimator then
		return existingRegisteredAnimator
	else
		return RegisterAnimator(animator)
	end
end

local function GetLoadedAnimation(registeredAnimator: RegisteredAnimator, animation: Animation): LoadedAnimation?
	return registeredAnimator.LoadedAnimations[animation.AnimationId]
end

local function PruneTracks(registeredAnimator: RegisteredAnimator)
	local playing = registeredAnimator.Animator:GetPlayingAnimationTracks()
	if #playing < TRACK_SOFT then
		return
	end

	for _, track in playing do
		local animation = track.Animation
		if not animation then
			continue
		end
		local tags = GetAnimationTags(animation)
		if next(tags) ~= nil and track.TimePosition > 0 and not track.IsPlaying then
			track:Stop(0)
		elseif next(tags) ~= nil and track.Looped == false and track.TimePosition >= track.Length - 0.05 then
			track:Stop(0)
		end
	end
end

local function LoadAnimation(registeredAnimator: RegisteredAnimator, animation: Animation): LoadedAnimation
	PruneTracks(registeredAnimator)
	local animationTrack = registeredAnimator.Animator:LoadAnimation(animation)

	local loadedAnimation = {
		Track = animationTrack,
		Animation = animation,
	}

	registeredAnimator.LoadedAnimations[animation.AnimationId] = loadedAnimation

	return loadedAnimation
end

local function GetOrLoadAnimation(registeredAnimator: RegisteredAnimator, animation: Animation): LoadedAnimation
	local loadedAnimation: LoadedAnimation? = GetLoadedAnimation(registeredAnimator, animation)

	if loadedAnimation then
		return loadedAnimation
	else
		return LoadAnimation(registeredAnimator, animation)
	end
end

local function GetRunningLoadedAnimations(
	registeredAnimator: RegisteredAnimator,
	returnTracks: boolean?
): { LoadedAnimation }
	local runningLoadedAnimations = {}

	for _, loadedAnimation: LoadedAnimation in registeredAnimator.LoadedAnimations do
		if loadedAnimation.Track.IsPlaying then
			table.insert(runningLoadedAnimations, loadedAnimation)
		end
	end

	return runningLoadedAnimations
end

local function StopAnimation(
	registeredAnimator: RegisteredAnimator,
	animation: Animation,
	animationSettings: AnimationSettings?
)
	local loadedAnimation = GetLoadedAnimation(registeredAnimator, animation)

	if loadedAnimation then
		local animationParameters = animationSettings or {} :: AnimationSettings
		loadedAnimation.Track:Stop(animationParameters.FadeTime)
	end
end

local function PlayAnimation(
	registeredAnimator: RegisteredAnimator,
	animation: Animation,
	animationSettings: AnimationSettings?
): AnimationTrack
	local loadedAnimation = GetOrLoadAnimation(registeredAnimator, animation)

	local animationParameters = animationSettings or {} :: AnimationSettings
	if type(animationParameters.Looped) == "boolean" then
		loadedAnimation.Track.Looped = animationParameters.Looped
	end
	if animationParameters.Priority then
		loadedAnimation.Track.Priority = animationParameters.Priority
	end

	loadedAnimation.Track:Play(animationParameters.FadeTime, animationParameters.Weight, animationParameters.Speed)

	return loadedAnimation.Track
end

--==========================-- Public Functions --==========================--

function AnimationHandler.GetCharacterAnimator(character: Model): Animator?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end

	local existing = humanoid:FindFirstChildOfClass("Animator")
	if existing and existing:IsA("Animator") then
		return existing
	end
	if RunService:IsClient() then
		return nil
	end

	local animator = Instance.new("Animator")
	animator.Parent = humanoid
	return animator
end

function AnimationHandler.GetPlayerAnimator(player: Player): Animator?
	local character = player.Character
	if not character then
		return nil
	end
	return AnimationHandler.GetCharacterAnimator(character)
end

function AnimationHandler.GetRunningAnimations(animator: Animator): { AnimationTrack }
	local runningAnimationTracks = {}

	local registeredAnimator = GetRegisteredAnimator(animator)
	if registeredAnimator then
		for _, loadedAnimation: LoadedAnimation in registeredAnimator.LoadedAnimations do
			if loadedAnimation.Track.IsPlaying then
				table.insert(runningAnimationTracks, loadedAnimation.Track)
			end
		end
	end

	return runningAnimationTracks
end

function AnimationHandler.IsAnimationPlaying(animator: Animator, animation: Animation): boolean
	local registeredAnimator = GetRegisteredAnimator(animator)
	if registeredAnimator then
		local loadedAnimation = registeredAnimator.LoadedAnimations[animation.AnimationId]
		if loadedAnimation and loadedAnimation.Track.IsPlaying then
			return true
		end
	end

	return false
end

function AnimationHandler.GetAnimationTrack(animator: Animator, animation: Animation): AnimationTrack?
	local registeredAnimator = GetRegisteredAnimator(animator)
	local loadedAnimation = registeredAnimator and GetLoadedAnimation(registeredAnimator, animation)

	return loadedAnimation and loadedAnimation.Track or nil
end

function AnimationHandler.PreloadAnimation(animator: Animator, animation: Animation): AnimationTrack
	local registeredAnimator = GetOrSetRegisteredAnimator(animator)

	return GetOrLoadAnimation(registeredAnimator, animation).Track
end

function AnimationHandler.StopAnimation(animator: Animator, animation: Animation, animationSettings: AnimationSettings?)
	local registeredAnimator = GetRegisteredAnimator(animator)

	if registeredAnimator then
		StopAnimation(GetOrSetRegisteredAnimator(animator), animation, animationSettings)
	end
end

function AnimationHandler.PlayAnimation(
	animator: Animator,
	animation: Animation,
	animationSettings: AnimationSettings?
): AnimationTrack
	return PlayAnimation(GetOrSetRegisteredAnimator(animator), animation, animationSettings)
end

function AnimationHandler.SetAnimationPlaying(
	animator: Animator,
	animation: Animation,
	enabled: boolean,
	animationSettings: AnimationSettings?
)
	if enabled then
		AnimationHandler.PlayAnimation(animator, animation, animationSettings)
	else
		AnimationHandler.StopAnimation(animator, animation, animationSettings)
	end
end

function AnimationHandler.StopAnimationsWithTag(
	animator: Animator,
	tagOrTagList: string | { string },
	animationSettings: AnimationSettings?
)
	local registeredAnimator = GetRegisteredAnimator(animator)
	if registeredAnimator then
		local tagList = GetTagList(tagOrTagList)

		local loadedAnimations = GetRunningLoadedAnimations(registeredAnimator)

		for _, loadedAnimation in loadedAnimations do
			if not loadedAnimation.Track.Animation then
				continue
			end

			local animationTags = GetAnimationTags(loadedAnimation.Track.Animation)

			for _, tag in tagList do
				if animationTags[tag] then
					StopAnimation(registeredAnimator, loadedAnimation.Track.Animation, animationSettings)
					break
				end
			end
		end
	end
end

function AnimationHandler.PlayAnimationsWithTag(
	animator: Animator,
	tagOrTagList: string | { string },
	animationSettings: AnimationSettings?
)
	local registeredAnimator = GetRegisteredAnimator(animator)
	if registeredAnimator then
		local tagList = GetTagList(tagOrTagList)

		for _, loadedAnimation in registeredAnimator.LoadedAnimations do
			if not loadedAnimation.Track.Animation then
				continue
			end
			if loadedAnimation.Track.IsPlaying then
				continue
			end

			local animationTags = GetAnimationTags(loadedAnimation.Track.Animation)

			for _, tag in tagList do
				if animationTags[tag] then
					PlayAnimation(registeredAnimator, loadedAnimation.Track.Animation, animationSettings)
					break
				end
			end
		end
	end
end

function AnimationHandler.AddAnimationTag(animation: Animation, tagOrTagList: string | { string })
	local tagList = GetTagList(tagOrTagList)

	local animationTags = AnimationIdTags[animation.AnimationId]

	if not animationTags then
		animationTags = {}
		AnimationIdTags[animation.AnimationId] = animationTags
	end

	for _, tag: string in tagList do
		animationTags[tag] = true
	end
end

function AnimationHandler.RemoveAnimationTag(animation: Animation, tagOrTagList: string | { string })
	local tagList = GetTagList(tagOrTagList)

	local animationTags = AnimationIdTags[animation.AnimationId]

	if animationTags then
		for _, tag: string in tagList do
			animationTags[tag] = nil

			if not next(animationTags) then
				AnimationIdTags[animation.AnimationId] = nil
				break
			end
		end
	end
end

return AnimationHandler

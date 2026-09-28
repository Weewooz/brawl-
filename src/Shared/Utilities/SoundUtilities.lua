--!strict

local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local SoundUtil = {}

local DEFAULT_ROLL_OFF_MIN_DISTANCE = 32
local DEFAULT_ROLL_OFF_MAX_DISTANCE = 64
local TEMPLATE_CLEANUP_TIME = 30

--------------------------------------------------------------------------------
--// Private Functions //--
--------------------------------------------------------------------------------

--[=[
	Returns an attachment at the given position, parented to the terrain. Intended for use as a parent for localized sounds.

	@param position Vector3? -- The position of the attachment.
	@param dependantInstance Instance? -- The instance the attachment exists for. If set, the attachment will be destroyed if the sound gets re-parented or destroyed.

	@return Attachment -- The created attachment.
]=]
local function CreateSoundPositionAttachment(position: Vector3?, dependantInstance: Instance?): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = "SoundPositionAttachment"
	attachment.Position = position or Vector3.new(0, 0, 0)
	attachment.Parent = workspace.Terrain

	if dependantInstance then
		local c
		c = dependantInstance:GetPropertyChangedSignal("Parent"):Connect(function()
			if dependantInstance.Parent ~= attachment then
				attachment:Destroy()

				if c then
					c:Disconnect()
				end
			end
		end)
	end

	return attachment
end

--------------------------------------------------------------------------------
--// Public Functions //--
--------------------------------------------------------------------------------

--[=[
	Returns a randomized volume based on the given base volume and min/max variations.

	@param baseVolume number -- The base volume to use.
	@param minVariation number -- The minimum variation to apply.
	@param maxVariation number -- The maximum variation to apply.

	@return number -- The randomized volume variation.
]=]
function SoundUtil.GetRandomizedVolumeVariation(baseVolume: number, minVariation: number, maxVariation: number): number
	local variation = math.random() * (maxVariation - minVariation) + minVariation
	return baseVolume + variation
end

--[=[
	Returns a sound instance with the given sound ID, along with default values set for RollOff properties.

	@param soundId string -- The sound ID to create.

	@return Sound -- The created sound instance.
]=]
function SoundUtil.CreateSound(soundId: string): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = 0.5
	sound.RollOffMode = Enum.RollOffMode.Linear
	sound.RollOffMinDistance = DEFAULT_ROLL_OFF_MIN_DISTANCE
	sound.RollOffMaxDistance = DEFAULT_ROLL_OFF_MAX_DISTANCE

	return sound
end

--[=[
	Returns sound parented to the given part with default values set such that it's instantly ready to play a localized sound.

	@param soundId string -- The sound ID to play.
	@param partParent BasePart -- The part to parent the sound to.
	@param destroyOnEnd boolean? -- Whether the sound is added to debris such that it destroys after it finishes playing. Defaults to false.

	@return Sound -- The created sound instance.
]=]
function SoundUtil.CreateSoundInPart(soundId: string, partParent: BasePart): Sound
	local sound = SoundUtil.CreateSound(soundId)
	sound.Parent = partParent

	return sound
end

--[=[
	Plays sound parented to the given part
	
	@param soundId string -- The sound ID to play.
	@param partParent BasePart -- The part to parent the sound to.
	@param beforePlayCallback (sound: Sound) -> ()? -- A callback function called before the sound is played. This can be used to edit or attach behavior to the sound before it plays.
	@param doNotClean: boolean? -- Whether the created instances are prevented from being automatically cleaned up after the sound finishes. Defaults to false.

	@return Sound -- The created sound instance.
]=]
function SoundUtil.PlaySoundInPart(
	soundId: string,
	partParent: BasePart,
	beforePlayCallback: (sound: Sound) -> ()?,
	doNotClean: boolean?
): Sound
	local sound = SoundUtil.CreateSoundInPart(soundId, partParent)

	if beforePlayCallback then
		beforePlayCallback(sound)
	end

	sound:Play()

	if not doNotClean then
		if not sound.IsPlaying then
			sound:Destroy()
		else
			sound.Ended:Once(function()
				sound:Destroy()
			end)
		end
	end

	return sound
end

--[=[
	Returns sound parented to an attachment at the given position.

	@param soundId string -- The sound ID to play.
	@param position Vector3 -- The position of the sound's parent attachment.

	@return Sound -- The created sound instance.
	@return Attachment -- The created attachment instance that the sound is parented to.
]=]
function SoundUtil.CreateSoundInPosition(soundId: string, position: Vector3): (Sound, Attachment)
	local sound = SoundUtil.CreateSound(soundId)
	local attachment = CreateSoundPositionAttachment(position, sound)

	sound.Parent = attachment

	return sound, attachment
end

--[=[
	Plays sound parented to an attachment at the given position.

	@param soundId string -- The sound ID to play.
	@param position Vector3 -- The position of the sound's parent attachment.
	@param beforePlayCallback (sound: Sound) -> ()? -- A callback function called before the sound is played. This can be used to edit or attach behavior to the sound before it plays.
	@param doNotClean: boolean? -- Whether the created instances are prevented from being automatically cleaned up after the sound finishes. Defaults to false.

	@return Sound -- The created sound instance.
	@return Attachment -- The created attachment instance that the sound is parented to.
]=]
function SoundUtil.PlaySoundInPosition(
	soundId: string,
	position: Vector3,
	beforePlayCallback: (sound: Sound) -> ()?,
	doNotClean: boolean?
): (Sound, Attachment)
	local sound, attachment = SoundUtil.CreateSoundInPosition(soundId, position)

	if beforePlayCallback then
		beforePlayCallback(sound)
	end

	sound:Play()

	if not doNotClean then
		if not sound.IsPlaying then
			sound:Destroy()
		else
			sound.Ended:Once(function()
				sound:Destroy()
			end)
		end
	end

	return sound, attachment
end

function SoundUtil.PlaySoundTemplate(
	soundTemplate: Sound?,
	parent: Instance?,
	configure: ((sound: Sound) -> ())?
): Sound?
	if not soundTemplate then
		return nil
	end

	local sound = soundTemplate:Clone()
	sound.Parent = parent or SoundService
	if configure then
		configure(sound)
	end
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	Debris:AddItem(sound, TEMPLATE_CLEANUP_TIME)
	sound:Play()
	return sound
end

function SoundUtil.PlayLoopedSoundTemplate(
	soundTemplate: Sound?,
	parent: Instance?,
	configure: ((sound: Sound) -> ())?
): Sound?
	if not soundTemplate then
		return nil
	end

	local sound = soundTemplate:Clone()
	sound.Looped = true
	sound.Parent = parent or SoundService
	if configure then
		configure(sound)
	end
	sound:Play()
	return sound
end

function SoundUtil.PlaySoundTemplateAtPosition(soundTemplate: Sound?, position: Vector3): Sound?
	if not soundTemplate then
		return nil
	end

	local sound = soundTemplate:Clone()
	local attachment = CreateSoundPositionAttachment(position, sound)
	sound.Parent = attachment
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	Debris:AddItem(sound, TEMPLATE_CLEANUP_TIME)
	sound:Play()
	return sound
end

return SoundUtil

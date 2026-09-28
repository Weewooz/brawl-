--!strict
local CollectionService = game:GetService("CollectionService")
local DebrisService = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Geometry = require(script.Parent.Geometry)
local Settings = require(script.Parent.Settings)
local Truss = require(script.Parent.Truss)
local Tags = require(ReplicatedStorage.Shared.Core.Tags)

local CONTACT_QUERY_PADDING = Vector3.new(0.16, 0.16, 0.16)
local BASE_CHUNK_VARIATION = 0.35
local MICRO_CHUNK_VARIATION = 0.2
local MAX_FRACTURE_STAGES = 2
local INNER_CRATER_RATIO = 0.75
local MAX_GLOBAL_DEBRIS_PARTS = 300
local FADE_RATIO = 0.35 -- Portion of DebrisLifetime spent fading out
local CHUNK_TAG = "FractureChunk"
local KEEP_WHOLE_TAG = "KeepWhole"
local DEBRIS_ATTRIBUTE = "FractureDebris"
local DEBRIS_OWNER_ATTRIBUTE = "FractureDebrisOwner"
local DRIFT = 3 -- Studs from pose before a live chunk counts as broken
local RECLAIM = 10 -- Max studs for free stray reclaim; farther deletes and consumes material
local FLOOD = 2048 -- Chunk visits before a local support flood gives up and rebuilds globally
local CLASSIC_LOOSE_PART_MINIMUM_LIFETIME = 5
local CLASSIC_LOOSE_PART_MAXIMUM_LIFETIME = 6
local CLASSIC_LOOSE_PART_FADE_DURATION = 0.2
local CLASSIC_EDGE_FORCE_SCALE = 1
local CLASSIC_SUPPORT_SLICE = 0.001 -- CPU seconds before continuing support work next frame.
local DEBRIS_LIFETIME_ATTRIBUTE = "FractureDebrisLifetime"
local RandomGenerator = Random.new(math.floor(os.clock() * 1000))
local ActiveDebrisParts = 0
local LoosePartCleanupScheduled: { [BasePart]: boolean } = {}

type Pose = {
	CFrame: CFrame,
	Size: Vector3,
}

type Chunk = {
	Id: number,
	OriginId: number,
	Part: BasePart,
	Neighbors: { [number]: true },
	NeighborWelds: { [number]: WeldConstraint },
	Stage: number,
	IsAnchor: boolean,
	HasAnchorContact: boolean,
	AnchorContact: boolean?, -- Cached contact test; external anchors never move
	IsDebris: boolean,
	KeepWhole: boolean,
	Template: BasePart, -- Nil-parented visual/property source for repair
	DestParent: Instance, -- Where restored parts are parented
}

export type Void = {
	Id: number,
	OriginId: number,
	CFrame: CFrame,
	Size: Vector3,
	Stage: number,
	IsAnchor: boolean,
	HasAnchorContact: boolean,
	Template: BasePart,
	Parent: Instance,
	Name: string,
	Neighbors: { [number]: true },
	Consumes: boolean, -- false for free reclaim; true for destroyed or far (>RECLAIM) voids
	Stray: BasePart?, -- near reclaim flyer; cleared on far delete / destroyed voids
	KeepWhole: boolean,
}

type PreparedRootState = {
	Instance: Instance,
	Settings: Settings.PreparedRootSettings,
	ChunksById: { [number]: Chunk },
	ChunksByPart: { [BasePart]: Chunk },
	LooseChunks: { [number]: Chunk },
	VoidsById: { [number]: Void },
	Poses: { [number]: Pose },
	Templates: { BasePart },
	NextChunkId: number,
	ConnectionsVersion: number,
	DestroyConnection: RBXScriptConnection?,
	IntegrityUpdateScheduled: boolean,
	Suspects: { Chunk }, -- Chunks whose support may have changed since the last resolve
	SupportResolveScheduled: boolean,
	RemovedParts: { [BasePart]: Chunk },
	RemovalConnection: RBXScriptConnection?,
	Destroyed: boolean,
	OnDestroyed: () -> (),
}

local PreparedRoot = {}
PreparedRoot.__index = PreparedRoot

export type VoidInfo = {
	Position: Vector3,
	Distance: number,
	Void: Void,
}

export type FractureRequest = {
	Position: Vector3,
	Settings: Settings.FractureSettings,
}

export type PreparedRoot = PreparedRootState & {
	DetachPart: (self: PreparedRoot, part: BasePart) -> boolean,
	GetParts: (self: PreparedRoot) -> { BasePart },
	Prepare: (self: PreparedRoot) -> { BasePart },
	FractureAt: (
		self: PreparedRoot,
		position: Vector3,
		fractureSettings: Settings.FractureSettings
	) -> { BasePart },
	FractureAtStages: (
		self: PreparedRoot,
		position: Vector3,
		fractureSettingsList: { Settings.FractureSettings }
	) -> { BasePart },
	FractureBatch: (self: PreparedRoot, fractureRequests: { FractureRequest }) -> { BasePart },
	FindVoids: (
		self: PreparedRoot,
		position: Vector3,
		radius: number,
		canRepair: ((part: BasePart) -> boolean)?,
		allowConsume: boolean?
	) -> { VoidInfo },
	PopVoid: (
		self: PreparedRoot,
		position: Vector3,
		radius: number,
		canRepair: ((part: BasePart) -> boolean)?,
		allowConsume: boolean?
	) -> Void?,
	CommitVoid: (self: PreparedRoot, void: Void) -> BasePart?,
	RepairAt: (self: PreparedRoot, position: Vector3, repairSettings: Settings.RepairSettings) -> { BasePart },
	Destroy: (self: PreparedRoot) -> (),
}

local function AddTag(instance: Instance, tagName: string)
	if not CollectionService:HasTag(instance, tagName) then
		CollectionService:AddTag(instance, tagName)
	end
end

local function RemoveTag(instance: Instance, tagName: string)
	if CollectionService:HasTag(instance, tagName) then
		CollectionService:RemoveTag(instance, tagName)
	end
end

local function CopyPartProperties(sourcePart: Part, targetPart: Part)
	targetPart.Anchored = sourcePart.Anchored
	targetPart.CanCollide = sourcePart.CanCollide
	targetPart.CanTouch = sourcePart.CanTouch
	targetPart.CanQuery = sourcePart.CanQuery
	targetPart.CastShadow = sourcePart.CastShadow
	targetPart.Color = sourcePart.Color
	targetPart.Material = sourcePart.Material
	targetPart.MaterialVariant = sourcePart.MaterialVariant
	targetPart.Transparency = sourcePart.Transparency
	targetPart.Reflectance = sourcePart.Reflectance
	targetPart.TopSurface = sourcePart.TopSurface
	targetPart.BottomSurface = sourcePart.BottomSurface
	targetPart.CollisionGroup = sourcePart.CollisionGroup
	targetPart.CustomPhysicalProperties = sourcePart.CustomPhysicalProperties
	targetPart.Massless = sourcePart.Massless
end

local function CopyPartMetadata(sourcePart: Part, targetPart: Part)
	for attributeName, attributeValue in sourcePart:GetAttributes() do
		targetPart:SetAttribute(attributeName, attributeValue)
	end

	for _, tagName in CollectionService:GetTags(sourcePart) do
		if tagName ~= CHUNK_TAG then
			AddTag(targetPart, tagName)
		end
	end

	for _, child in sourcePart:GetChildren() do
		if child:IsA("Decal") or child:IsA("Texture") then
			(child:Clone() :: Instance).Parent = targetPart
		end
	end
end

local function HasTagInHierarchy(instance: Instance, tagName: string): boolean
	local currentInstance: Instance? = instance
	while currentInstance do
		if CollectionService:HasTag(currentInstance, tagName) then
			return true
		end
		currentInstance = currentInstance.Parent
	end

	return false
end

local function CanSplit(part: BasePart): boolean
	return part:IsA("Part") and part.Shape == Enum.PartType.Block and not HasTagInHierarchy(part, KEEP_WHOLE_TAG)
end

local function CanSplitTruss(part: BasePart): boolean
	return part:IsA("TrussPart") and not HasTagInHierarchy(part, KEEP_WHOLE_TAG)
end

local function GetSplitParts(root: Instance, ignoreTag: string): { Part }
	local splitParts: { Part } = {}
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") and CanSplit(descendant) and not HasTagInHierarchy(descendant, ignoreTag) then
			table.insert(splitParts, descendant :: Part)
		end
	end

	return splitParts
end

local function GetTrussParts(root: Instance, ignoreTag: string): { TrussPart }
	local trussParts: { TrussPart } = {}
	for _, descendant in root:GetDescendants() do
		if
			descendant:IsA("TrussPart")
			and CanSplitTruss(descendant)
			and not HasTagInHierarchy(descendant, ignoreTag)
		then
			table.insert(trussParts, descendant)
		end
	end

	return trussParts
end

local function GetWholeParts(root: Instance, ignoreTag: string): { BasePart }
	local wholeParts: { BasePart } = {}
	for _, descendant in root:GetDescendants() do
		if
			descendant:IsA("BasePart")
			and not CanSplit(descendant)
			and not CanSplitTruss(descendant)
			and not HasTagInHierarchy(descendant, ignoreTag)
		then
			table.insert(wholeParts, descendant)
		end
	end

	return wholeParts
end

function PreparedRoot.new(
	root: Instance,
	prepareSettings: Settings.PreparedRootSettings,
	onDestroyed: () -> ()
): PreparedRoot
	local self: PreparedRoot = setmetatable({
		Instance = root,
		Settings = prepareSettings,
		ChunksById = {},
		ChunksByPart = {},
		LooseChunks = {},
		VoidsById = {},
		Poses = {},
		Templates = {},
		NextChunkId = 1,
		ConnectionsVersion = 0,
		DestroyConnection = nil,
		IntegrityUpdateScheduled = false,
		Suspects = {},
		SupportResolveScheduled = false,
		RemovedParts = {},
		RemovalConnection = nil,
		Destroyed = false,
		OnDestroyed = onDestroyed,
	}, PreparedRoot) :: any

	self.DestroyConnection = root.Destroying:Connect(function()
		self:Destroy()
	end)

	return self
end

function PreparedRoot.GetParts(self: PreparedRoot): { BasePart }
	local parts: { BasePart } = {}
	for _, chunk in self.ChunksById do
		if chunk.Part.Parent then
			table.insert(parts, chunk.Part)
		end
	end

	return parts
end

local function AddChunk(
	self: PreparedRoot,
	part: BasePart,
	stage: number,
	isAnchor: boolean,
	template: BasePart,
	destParent: Instance
): Chunk
	if self.Settings.BreakJointsOnImpact and self.Settings.AttachmentMode == "AnchoredSupport" then
		part.Anchored = true
	end
	local chunk: Chunk = {
		Id = self.NextChunkId,
		OriginId = self.NextChunkId,
		Part = part,
		Neighbors = {},
		NeighborWelds = {},
		Stage = stage,
		IsAnchor = isAnchor,
		HasAnchorContact = isAnchor,
		IsDebris = false,
		Template = template,
		DestParent = destParent,
		KeepWhole = HasTagInHierarchy(part, KEEP_WHOLE_TAG),
	}

	self.NextChunkId += 1
	self.ConnectionsVersion += 1
	self.Poses[chunk.Id] = {
		CFrame = part.CFrame,
		Size = part.Size,
	}
	self.ChunksById[chunk.Id] = chunk
	self.ChunksByPart[part] = chunk
	if not part.Anchored then
		self.LooseChunks[chunk.Id] = chunk
	end
	AddTag(part, CHUNK_TAG)
	part:SetAttribute(DEBRIS_ATTRIBUTE, nil)
	part:SetAttribute(DEBRIS_LIFETIME_ATTRIBUTE, nil)
	part:SetAttribute(DEBRIS_OWNER_ATTRIBUTE, nil)
	RemoveTag(part, DEBRIS_ATTRIBUTE)

	return chunk
end

local function CreateChunks(
	self: PreparedRoot,
	sourcePart: Part,
	targetSize: Vector3,
	variance: number,
	maxChunks: number,
	stage: number,
	isAnchor: boolean,
	template: Part,
	destParent: Instance?,
	axisWins: boolean?
): { Chunk }
	local destinationParent = destParent or sourcePart.Parent
	local maxAxis = self.Settings.MaxChunkAxis
	if not destinationParent or maxChunks <= 0 then
		return {}
	end

	local xSegments, ySegments, zSegments =
		Geometry.BuildPartSegments(sourcePart.Size, targetSize, variance, maxChunks, RandomGenerator, maxAxis, axisWins)
	if #xSegments * #ySegments * #zSegments <= 1 then
		return {}
	end
	local sourceCFrame = sourcePart.CFrame
	local sourceSize = sourcePart.Size
	local createdChunks: { Chunk } = {}
	local yCursor = -sourceSize.Y * 0.5

	for _, ySize in ySegments do
		local yPosition = yCursor + ySize * 0.5
		yCursor += ySize
		local xCursor = -sourceSize.X * 0.5

		for _, xSize in xSegments do
			local xPosition = xCursor + xSize * 0.5
			xCursor += xSize
			local zCursor = -sourceSize.Z * 0.5

			for _, zSize in zSegments do
				local zPosition = zCursor + zSize * 0.5
				zCursor += zSize

				local chunkPart = Instance.new("Part")
				chunkPart.Name = sourcePart.Name
				chunkPart.Size = Vector3.new(xSize, ySize, zSize)
				CopyPartProperties(template, chunkPart)
				CopyPartMetadata(template, chunkPart)
				if self.Settings.AttachmentMode == "Welded" then
					chunkPart.Anchored = isAnchor
				else
					chunkPart.Anchored = sourcePart.Anchored
				end
				chunkPart.CFrame = sourceCFrame * CFrame.new(xPosition, yPosition, zPosition)
				chunkPart.Parent = destinationParent
				table.insert(createdChunks, AddChunk(self, chunkPart, stage, isAnchor, template, destinationParent))
			end
		end
	end

	return createdChunks
end

local function ConnectChunks(chunkA: Chunk, chunkB: Chunk)
	if chunkA == chunkB or chunkA.Neighbors[chunkB.Id] then
		return
	end

	chunkA.Neighbors[chunkB.Id] = true
	chunkB.Neighbors[chunkA.Id] = true
end

local function CreateWeld(chunkA: Chunk, chunkB: Chunk)
	local existingWeld = chunkA.NeighborWelds[chunkB.Id]
	if existingWeld and existingWeld.Parent then
		return
	end
	if not chunkA.Part.Parent or not chunkB.Part.Parent then
		return
	end

	local weld = Instance.new("WeldConstraint")
	weld.Name = "DestructionWeld"
	weld.Part0 = chunkA.Part
	weld.Part1 = chunkB.Part
	weld.Parent = chunkA.Part
	chunkA.NeighborWelds[chunkB.Id] = weld
	chunkB.NeighborWelds[chunkA.Id] = weld
end

local function ScheduleLoosePartCleanup(self: PreparedRoot, part: BasePart)
	if
		not self.Settings.BreakJointsOnImpact
		or self.Destroyed
		or LoosePartCleanupScheduled[part]
		or CollectionService:HasTag(part, Tags.MapSpawn)
	then
		return
	end

	LoosePartCleanupScheduled[part] = true
	task.delay(
		RandomGenerator:NextNumber(CLASSIC_LOOSE_PART_MINIMUM_LIFETIME, CLASSIC_LOOSE_PART_MAXIMUM_LIFETIME),
		function()
			if self.Destroyed or not part.Parent or part.Anchored then
				LoosePartCleanupScheduled[part] = nil
				return
			end

			part:SetAttribute("Fade", CLASSIC_LOOSE_PART_FADE_DURATION)
			CollectionService:AddTag(part, Tags.Fade)
			task.delay(CLASSIC_LOOSE_PART_FADE_DURATION, function()
				LoosePartCleanupScheduled[part] = nil
				if part.Parent then
					part:Destroy()
				end
			end)
		end
	)
end

local function RemoveWelds(self: PreparedRoot, chunk: Chunk)
	for neighborId, weld in chunk.NeighborWelds do
		weld:Destroy()
		local neighbor = self.ChunksById[neighborId]
		if neighbor then
			neighbor.NeighborWelds[chunk.Id] = nil
			if next(neighbor.NeighborWelds) == nil then
				ScheduleLoosePartCleanup(self, neighbor.Part)
			end
		end
	end

	table.clear(chunk.NeighborWelds)
	ScheduleLoosePartCleanup(self, chunk.Part)
end

local function RemoveChunk(self: PreparedRoot, chunk: Chunk)
	if self.ChunksById[chunk.Id] ~= chunk then
		return
	end

	RemoveWelds(self, chunk)
	self.ConnectionsVersion += 1
	for neighborId in chunk.Neighbors do
		local neighbor = self.ChunksById[neighborId]
		if neighbor then
			neighbor.Neighbors[chunk.Id] = nil
		end
	end

	self.ChunksById[chunk.Id] = nil
	self.ChunksByPart[chunk.Part] = nil
	self.LooseChunks[chunk.Id] = nil
end

local function RecordVoid(self: PreparedRoot, chunk: Chunk)
	if self.VoidsById[chunk.Id] then
		return
	end

	local pose = self.Poses[chunk.Id]
	if not pose then
		return
	end

	local neighbors: { [number]: true } = {}
	for neighborId in chunk.Neighbors do
		neighbors[neighborId] = true
	end

	local part = chunk.Part
	self.VoidsById[chunk.Id] = {
		Id = chunk.Id,
		OriginId = chunk.OriginId,
		CFrame = pose.CFrame,
		Size = pose.Size,
		Stage = chunk.Stage,
		IsAnchor = chunk.IsAnchor,
		HasAnchorContact = chunk.HasAnchorContact,
		Template = chunk.Template,
		Parent = chunk.DestParent,
		Name = if part then part.Name else chunk.Template.Name,
		Neighbors = neighbors,
		Consumes = true,
		Stray = nil,
		KeepWhole = chunk.KeepWhole,
	}
end

local function IsLive(chunk: Chunk): boolean
	return chunk.Part.Parent ~= nil and chunk.Part.Anchored
end

-- Queues the surviving neighbors of a chunk that is leaving the structure. Their
-- path back to an anchor may have run through it, so their support needs a recheck.
local function AddSuspects(self: PreparedRoot, chunk: Chunk)
	for neighborId in chunk.Neighbors do
		local neighbor = self.ChunksById[neighborId]
		if neighbor and neighbor ~= chunk and IsLive(neighbor) then
			table.insert(self.Suspects, neighbor)
			if chunk.IsAnchor then
				neighbor.AnchorContact = nil
			end
		end
	end
end

local function DestroyChunk(self: PreparedRoot, chunk: Chunk)
	local part = chunk.Part
	if part and part.Parent then
		RemoveTag(part, CHUNK_TAG)
	end
	RecordVoid(self, chunk)
	AddSuspects(self, chunk)
	RemoveChunk(self, chunk)
	if part then
		part:Destroy()
	end
end

local function GetTouchingParts(self: PreparedRoot, part: BasePart): { BasePart }
	local overlapParameters = OverlapParams.new()
	overlapParameters.FilterType = Enum.RaycastFilterType.Exclude
	overlapParameters.FilterDescendantsInstances = { part }

	local touchingParts: { BasePart } = {}
	for _, nearbyPart in Workspace:GetPartBoundsInBox(part.CFrame, part.Size + CONTACT_QUERY_PADDING, overlapParameters) do
		local nearbyChunk = self.ChunksByPart[nearbyPart]
		local canAnchor = nearbyPart.Anchored
			and (
				CollectionService:HasTag(nearbyPart, self.Settings.AnchorTag)
				or not nearbyPart:IsDescendantOf(self.Instance)
			)
		if (nearbyChunk or canAnchor) and Geometry.ArePartsConnected(part, nearbyPart) then
			table.insert(touchingParts, nearbyPart)
		end
	end

	return touchingParts
end

local function ConnectNearbyChunks(self: PreparedRoot, chunk: Chunk): { BasePart }
	local touchingParts = GetTouchingParts(self, chunk.Part)
	for _, touchingPart in touchingParts do
		local touchingChunk = self.ChunksByPart[touchingPart]
		if touchingChunk then
			ConnectChunks(chunk, touchingChunk)
		end
	end

	return touchingParts
end

local function CreateWelds(self: PreparedRoot, chunks: { Chunk })
	if self.Settings.AttachmentMode ~= "Welded" then
		return
	end

	for _, chunk in chunks do
		for neighborId in chunk.Neighbors do
			local neighbor = self.ChunksById[neighborId]
			if neighbor then
				CreateWeld(chunk, neighbor)
			end
		end
	end
end

local function WeldComponent(self: PreparedRoot, chunks: { Chunk }, yieldIfNeeded: (() -> ())?)
	local componentIds: { [number]: true } = {}
	for _, chunk in chunks do
		componentIds[chunk.Id] = true
	end

	for _, chunk in chunks do
		if yieldIfNeeded then
			yieldIfNeeded()
		end
		if self.Destroyed or self.ChunksById[chunk.Id] ~= chunk then
			continue
		end
		for neighborId in chunk.Neighbors do
			local neighbor = self.ChunksById[neighborId]
			if neighbor and componentIds[neighborId] then
				CreateWeld(chunk, neighbor)
			end
		end
	end
end

local function DetachComponent(self: PreparedRoot, chunks: { Chunk }, yieldIfNeeded: (() -> ())?)
	local version = self.ConnectionsVersion
	WeldComponent(self, chunks, yieldIfNeeded)
	if yieldIfNeeded and self.ConnectionsVersion ~= version then
		for _, chunk in chunks do
			table.insert(self.Suspects, chunk)
		end
		return
	end
	-- Commit together so a repair cannot change support halfway through unanchoring.
	for _, chunk in chunks do
		if self.Destroyed or self.ChunksById[chunk.Id] ~= chunk then
			continue
		end
		chunk.Part.Anchored = false
		if not chunk.IsDebris then
			self.LooseChunks[chunk.Id] = chunk
		end
	end
	if #chunks == 1 then
		ScheduleLoosePartCleanup(self, chunks[1].Part)
	end
end

local function WeldLooseNeighbors(self: PreparedRoot, chunks: { Chunk })
	for _, chunk in chunks do
		if chunk.Part.Anchored then
			continue
		end
		for neighborId in chunk.Neighbors do
			local neighbor = self.ChunksById[neighborId]
			if neighbor and neighbor.Part.Parent and not neighbor.Part.Anchored then
				CreateWeld(chunk, neighbor)
			end
		end
	end
end

local function IsExternalAnchor(self: PreparedRoot, part: BasePart): boolean
	if not part.Anchored then
		return false
	end
	if HasTagInHierarchy(part, self.Settings.AnchorTag) then
		return true
	end

	local chunk = self.ChunksByPart[part]
	return chunk == nil and not part:IsDescendantOf(self.Instance)
end

local function HasActiveAnchorContact(self: PreparedRoot, chunk: Chunk): boolean
	if chunk.IsAnchor then
		return true
	end
	if not chunk.HasAnchorContact then
		return false
	end

	-- External anchors are static geometry and an anchored chunk never moves, so this
	-- contact test only has to hit the physics engine once per chunk.
	local cached = chunk.AnchorContact
	if cached ~= nil then
		return cached
	end

	local active = false
	for _, touchingPart in GetTouchingParts(self, chunk.Part) do
		if IsExternalAnchor(self, touchingPart) then
			active = true
			break
		end
	end

	chunk.AnchorContact = active
	return active
end

local function RecordAnchorContact(self: PreparedRoot, chunk: Chunk, touchingParts: { BasePart }?)
	if
		self.Settings.AttachmentMode == "Welded"
		or self.Settings.BreakJointsOnImpact
		or chunk.IsAnchor
		or chunk.HasAnchorContact
	then
		return
	end

	for _, touchingPart in (touchingParts or GetTouchingParts(self, chunk.Part)) :: { BasePart } do
		if IsExternalAnchor(self, touchingPart) then
			chunk.HasAnchorContact = true
			return
		end
	end
end

local function GetBottom(part: BasePart): number
	local halfSize = part.Size * 0.5
	local cframe = part.CFrame
	local radius = math.abs(cframe.XVector.Y) * halfSize.X
		+ math.abs(cframe.YVector.Y) * halfSize.Y
		+ math.abs(cframe.ZVector.Y) * halfSize.Z
	return part.Position.Y - radius
end

local function SeedStructuralAnchors(self: PreparedRoot, chunks: { Chunk })
	if
		self.Settings.AttachmentMode == "Welded"
		or self.Settings.BreakJointsOnImpact
		or not self.Settings.StructuralIntegrity
	then
		return
	end

	local visited: { [number]: true } = {}
	for _, firstChunk in chunks do
		if visited[firstChunk.Id] or not firstChunk.Part.Parent or not firstChunk.Part.Anchored then
			continue
		end

		local component = { firstChunk }
		local hasAnchor = false
		visited[firstChunk.Id] = true

		local index = 1
		while index <= #component do
			local chunk = component[index]
			index += 1
			hasAnchor = hasAnchor or chunk.IsAnchor or chunk.HasAnchorContact

			for neighborId in chunk.Neighbors do
				local neighbor = self.ChunksById[neighborId]
				if neighbor and not visited[neighborId] and neighbor.Part.Parent and neighbor.Part.Anchored then
					visited[neighborId] = true
					table.insert(component, neighbor)
				end
			end
		end

		if hasAnchor then
			continue
		end

		local lowest = math.huge
		for _, chunk in component do
			lowest = math.min(lowest, GetBottom(chunk.Part))
		end
		for _, chunk in component do
			if GetBottom(chunk.Part) <= lowest + CONTACT_QUERY_PADDING.Y then
				chunk.IsAnchor = true
				chunk.HasAnchorContact = true
			end
		end
	end
end

local function UpdateStructuralIntegrity(self: PreparedRoot)
	if self.Settings.AttachmentMode == "Welded" or not self.Settings.StructuralIntegrity then
		return
	end

	local supportedChunks: { [number]: true } = {}
	local pendingChunks: { Chunk } = {}

	for _, chunk in self.ChunksById do
		if chunk.Part.Parent and chunk.Part.Anchored and HasActiveAnchorContact(self, chunk) then
			supportedChunks[chunk.Id] = true
			table.insert(pendingChunks, chunk)
		end
	end

	local pendingIndex = 1
	while pendingIndex <= #pendingChunks do
		local chunk = pendingChunks[pendingIndex]
		pendingIndex += 1

		for neighborId in chunk.Neighbors do
			local neighbor = self.ChunksById[neighborId]
			if neighbor and neighbor.Part.Parent and neighbor.Part.Anchored and not supportedChunks[neighborId] then
				supportedChunks[neighborId] = true
				table.insert(pendingChunks, neighbor)
			end
		end
	end

	local detachedChunks: { [number]: true } = {}
	for _, firstChunk in self.ChunksById do
		if
			detachedChunks[firstChunk.Id]
			or not firstChunk.Part.Parent
			or not firstChunk.Part.Anchored
			or supportedChunks[firstChunk.Id]
		then
			continue
		end

		local component = { firstChunk }
		detachedChunks[firstChunk.Id] = true
		local componentIndex = 1
		while componentIndex <= #component do
			local chunk = component[componentIndex]
			componentIndex += 1
			for neighborId in chunk.Neighbors do
				local neighbor = self.ChunksById[neighborId]
				if
					neighbor
					and not detachedChunks[neighborId]
					and not supportedChunks[neighborId]
					and neighbor.Part.Parent
					and neighbor.Part.Anchored
				then
					detachedChunks[neighborId] = true
					table.insert(component, neighbor)
				end
			end
		end

		DetachComponent(self, component)
	end
end

local function ScheduleStructuralIntegrityUpdate(self: PreparedRoot)
	if self.IntegrityUpdateScheduled or self.Settings.AttachmentMode == "Welded" then
		return
	end

	self.IntegrityUpdateScheduled = true
	task.defer(function()
		self.IntegrityUpdateScheduled = false
		if not self.Destroyed then
			UpdateStructuralIntegrity(self)
		end
	end)
end

-- Walks the connected group of live anchored chunks containing the seed, stopping as
-- soon as it reaches an anchor. Returns the chunks visited and whether they are
-- supported, or nil support when the group is too large to settle locally.
local function FloodComponent(self: PreparedRoot, seed: Chunk): ({ Chunk }, boolean?)
	local component: { Chunk } = { seed }
	local visited: { [number]: true } = { [seed.Id] = true }

	local index = 1
	while index <= #component do
		local chunk = component[index]
		index += 1

		if HasActiveAnchorContact(self, chunk) then
			return component, true
		end
		if #component > FLOOD then
			return component, nil
		end

		for neighborId in chunk.Neighbors do
			local neighbor = self.ChunksById[neighborId]
			if neighbor and not visited[neighborId] and IsLive(neighbor) then
				visited[neighborId] = true
				table.insert(component, neighbor)
			end
		end
	end

	return component, false
end

-- Rechecks support only around the chunks that just changed. A fracture can never
-- take support away from a group it is not connected to, so the whole-map rebuild in
-- UpdateStructuralIntegrity is only needed as a fallback.
local function ResolveSuspects(self: PreparedRoot)
	local suspects = self.Suspects
	if #suspects == 0 then
		return
	end
	self.Suspects = {}

	if self.Settings.AttachmentMode == "Welded" or not self.Settings.StructuralIntegrity or self.Destroyed then
		return
	end

	local resolved: { [number]: true } = {}
	for _, suspect in suspects do
		if resolved[suspect.Id] or self.ChunksById[suspect.Id] ~= suspect or not IsLive(suspect) then
			continue
		end

		local component, supported = FloodComponent(self, suspect)
		for _, chunk in component do
			resolved[chunk.Id] = true
		end

		if supported == nil then
			ScheduleStructuralIntegrityUpdate(self)
			return
		end
		if supported then
			continue
		end

		DetachComponent(self, component)
	end
end

local function CheckClassicSupport(self: PreparedRoot)
	debug.profilebegin("ClassicDestruction.Support")
	local deadline = os.clock() + CLASSIC_SUPPORT_SLICE
	local workCount = 0
	local function yieldIfNeeded()
		workCount += 1
		if workCount % 64 == 0 and os.clock() >= deadline then
			debug.profileend()
			RunService.Heartbeat:Wait()
			debug.profilebegin("ClassicDestruction.Support")
			deadline = os.clock() + CLASSIC_SUPPORT_SLICE
		end
	end

	while not self.Destroyed and #self.Suspects > 0 do
		local suspects = self.Suspects
		self.Suspects = {}
		local checked: { [number]: true } = {}
		local version = self.ConnectionsVersion
		for _, suspect in suspects do
			if checked[suspect.Id] or self.ChunksById[suspect.Id] ~= suspect or not IsLive(suspect) then
				continue
			end
			local component = { suspect }
			local visited = { [suspect.Id] = true }
			local index = 1
			local supported = false
			while index <= #component do
				yieldIfNeeded()
				if self.Destroyed then
					debug.profileend()
					return
				end
				if self.ConnectionsVersion ~= version then
					break
				end
				local chunk = component[index]
				index += 1
				if chunk.IsAnchor then
					supported = true
					break
				end
				for neighborId in chunk.Neighbors do
					local neighbor = self.ChunksById[neighborId]
					if neighbor and not visited[neighborId] and IsLive(neighbor) then
						visited[neighborId] = true
						table.insert(component, neighbor)
					end
				end
			end
			-- A second blast or repair during a yield invalidates this connectivity search.
			if self.ConnectionsVersion ~= version then
				for _, pending in suspects do
					table.insert(self.Suspects, pending)
				end
				break
			end
			for _, chunk in component do
				checked[chunk.Id] = true
			end
			if not supported then
				DetachComponent(self, component, yieldIfNeeded)
			end
		end
	end
	debug.profileend()
end

local function ScheduleSupportResolve(self: PreparedRoot)
	if self.SupportResolveScheduled or self.Settings.AttachmentMode == "Welded" then
		return
	end

	self.SupportResolveScheduled = true
	task.defer(function()
		if not self.Destroyed then
			if self.Settings.BreakJointsOnImpact and self.Settings.StructuralIntegrity then
				CheckClassicSupport(self)
			else
				ResolveSuspects(self)
			end
		end
		self.SupportResolveScheduled = false
	end)
end

local function CleanMissingChunks(self: PreparedRoot)
	for part, chunk in self.RemovedParts do
		if not part:IsDescendantOf(self.Instance) then
			RemoveChunk(self, chunk)
		end
	end
	table.clear(self.RemovedParts)
end

function PreparedRoot.Prepare(self: PreparedRoot): { BasePart }
	if not self.RemovalConnection then
		self.RemovalConnection = self.Instance.DescendantRemoving:Connect(function(descendant)
			if descendant:IsA("BasePart") then
				local chunk = self.ChunksByPart[descendant]
				if chunk then
					self.RemovedParts[descendant] = chunk
				end
			end
		end)
	end
	local sourceParts = GetSplitParts(self.Instance, self.Settings.IgnoreTag)
	local trussParts = GetTrussParts(self.Instance, self.Settings.IgnoreTag)
	local wholeParts = GetWholeParts(self.Instance, self.Settings.IgnoreTag)
	if #sourceParts == 0 and #trussParts == 0 and #wholeParts == 0 then
		return {}
	end

	local createdChunks: { Chunk } = {}
	for _, sourcePart in trussParts do
		local isAnchor = HasTagInHierarchy(sourcePart, self.Settings.AnchorTag)
		local template = sourcePart:Clone()
		template.Parent = nil
		table.insert(self.Templates, template)

		local destinationParent = sourcePart.Parent
		local segments = Truss.Split(sourcePart, self.Settings.TrussSegmentLength, self.Settings.MaxChunksPerPart)
		if #segments > 0 and destinationParent then
			for _, segment in segments do
				if self.Settings.AttachmentMode == "Welded" then
					segment.Anchored = isAnchor
				end
				table.insert(
					createdChunks,
					AddChunk(self, segment, MAX_FRACTURE_STAGES, isAnchor, template, destinationParent)
				)
			end
			sourcePart:Destroy()
		elseif destinationParent then
			if self.Settings.AttachmentMode == "Welded" then
				sourcePart.Anchored = isAnchor
			end
			table.insert(
				createdChunks,
				AddChunk(self, sourcePart, MAX_FRACTURE_STAGES, isAnchor, template, destinationParent)
			)
		end
	end

	for _, wholePart in wholeParts do
		local isAnchor = HasTagInHierarchy(wholePart, self.Settings.AnchorTag)
		if self.Settings.AttachmentMode == "Welded" then
			wholePart.Anchored = isAnchor
		end
		local template = wholePart:Clone()
		template.Parent = nil
		table.insert(self.Templates, template)
		local destinationParent = wholePart.Parent
		if destinationParent then
			table.insert(
				createdChunks,
				AddChunk(self, wholePart, MAX_FRACTURE_STAGES, isAnchor, template, destinationParent)
			)
		end
	end

	for _, sourcePart in sourceParts do
		local isAnchor = HasTagInHierarchy(sourcePart, self.Settings.AnchorTag)
		local template = sourcePart:Clone()
		template.Parent = nil
		table.insert(self.Templates, template)

		local destParent = sourcePart.Parent
		local replacementChunks = CreateChunks(
			self,
			sourcePart,
			self.Settings.BaseChunkSize,
			BASE_CHUNK_VARIATION,
			self.Settings.MaxChunksPerPart,
			0,
			isAnchor,
			template,
			destParent
		)
		if #replacementChunks > 0 then
			for _, chunk in replacementChunks do
				table.insert(createdChunks, chunk)
			end
			sourcePart:Destroy()
		elseif destParent then
			if self.Settings.AttachmentMode == "Welded" then
				sourcePart.Anchored = isAnchor
			end
			table.insert(createdChunks, AddChunk(self, sourcePart, 0, isAnchor, template, destParent))
		end
	end

	for _, chunk in createdChunks do
		local touchingParts = ConnectNearbyChunks(self, chunk)
		RecordAnchorContact(self, chunk, touchingParts)
	end
	SeedStructuralAnchors(self, createdChunks)
	CreateWelds(self, createdChunks)
	UpdateStructuralIntegrity(self)

	local createdParts: { BasePart } = {}
	for _, chunk in createdChunks do
		table.insert(createdParts, chunk.Part)
	end
	return createdParts
end

local function CanLaunchDebris(self: PreparedRoot, chunk: Chunk, maxAxis: number): boolean
	if chunk.IsDebris or chunk.Part.Parent == nil or self.ChunksById[chunk.Id] ~= chunk then
		return false
	end
	return Geometry.FitsAxisCap(chunk.Part.Size, maxAxis)
end

local function BuildDebrisCluster(
	self: PreparedRoot,
	seed: Chunk,
	debrisCandidates: { [number]: Chunk },
	selectedChunks: { [number]: boolean },
	maximumSize: number,
	maxAxis: number
): { Chunk }
	local cluster: { Chunk } = {}
	local pendingChunks = { seed }
	local queuedChunks = { [seed.Id] = true }

	while #pendingChunks > 0 and #cluster < maximumSize do
		local pendingIndex = RandomGenerator:NextInteger(1, #pendingChunks)
		local chunk = table.remove(pendingChunks, pendingIndex)
		if not chunk then
			continue
		end
		if selectedChunks[chunk.Id] or not CanLaunchDebris(self, chunk, maxAxis) then
			continue
		end

		selectedChunks[chunk.Id] = true
		table.insert(cluster, chunk)

		for neighborId in chunk.Neighbors do
			local neighbor = debrisCandidates[neighborId]
			if neighbor and not selectedChunks[neighborId] and not queuedChunks[neighborId] then
				queuedChunks[neighborId] = true
				table.insert(pendingChunks, neighbor)
			end
		end
	end

	return cluster
end

local function WeldDebrisCluster(self: PreparedRoot, cluster: { Chunk })
	local clusterIds: { [number]: boolean } = {}
	for _, chunk in cluster do
		clusterIds[chunk.Id] = true
	end

	for _, chunk in cluster do
		for neighborId, weld in chunk.NeighborWelds do
			if clusterIds[neighborId] then
				continue
			end

			weld:Destroy()
			chunk.NeighborWelds[neighborId] = nil
			local neighbor = self.ChunksById[neighborId]
			if neighbor then
				neighbor.NeighborWelds[chunk.Id] = nil
			end
		end
	end

	WeldComponent(self, cluster)
end

local function GetDebrisVelocity(
	clusterPosition: Vector3,
	impactPosition: Vector3,
	fractureSettings: Settings.FractureSettings
): Vector3
	local outwardOffset = Vector3.new(clusterPosition.X - impactPosition.X, 0, clusterPosition.Z - impactPosition.Z)
	local outwardDirection: Vector3
	if outwardOffset.Magnitude > 0.01 then
		outwardDirection = outwardOffset.Unit
	else
		local impactDirection = Vector3.new(fractureSettings.ImpactDirection.X, 0, fractureSettings.ImpactDirection.Z)
		if impactDirection.Magnitude > 0.01 then
			outwardDirection = impactDirection.Unit
		else
			local angle = RandomGenerator:NextNumber(0, math.pi * 2)
			outwardDirection = Vector3.new(math.cos(angle), 0, math.sin(angle))
		end
	end

	return outwardDirection * fractureSettings.DebrisSpeed * RandomGenerator:NextNumber(0.8, 1.2)
		+ Vector3.new(
			RandomGenerator:NextNumber(-5, 5),
			fractureSettings.UpwardDebrisSpeed * RandomGenerator:NextNumber(0.9, 1.25),
			RandomGenerator:NextNumber(-5, 5)
		)
end

local function LaunchDebrisCluster(
	self: PreparedRoot,
	cluster: { Chunk },
	position: Vector3,
	fractureSettings: Settings.FractureSettings
)
	WeldDebrisCluster(self, cluster)

	local owner = fractureSettings.SourcePlayer
	local ownerId = if owner and owner.Parent then owner.UserId else nil

	local clusterPosition = Vector3.zero
	for _, chunk in cluster do
		local part = chunk.Part
		chunk.IsDebris = true
		self.LooseChunks[chunk.Id] = nil
		part.Anchored = false
		part.CanCollide = true
		part:SetAttribute(DEBRIS_LIFETIME_ATTRIBUTE, fractureSettings.DebrisLifetime)
		part:SetAttribute(DEBRIS_ATTRIBUTE, true)
		part:SetAttribute(DEBRIS_OWNER_ATTRIBUTE, ownerId)
		AddTag(part, DEBRIS_ATTRIBUTE)
		clusterPosition += part.Position
	end
	clusterPosition /= #cluster

	local assemblyRoot = cluster[1].Part.AssemblyRootPart or cluster[1].Part
	assemblyRoot.AssemblyLinearVelocity = GetDebrisVelocity(clusterPosition, position, fractureSettings)
	assemblyRoot.AssemblyAngularVelocity = Vector3.new(
		RandomGenerator:NextNumber(-18, 18),
		RandomGenerator:NextNumber(-18, 18),
		RandomGenerator:NextNumber(-18, 18)
	)

	local lifetime = fractureSettings.DebrisLifetime
	local fade = math.clamp(lifetime * FADE_RATIO, 0.25, lifetime * 0.5)
	local hold = math.max(lifetime - fade, 0)
	local collect = ownerId ~= nil

	for _, chunk in cluster do
		local part = chunk.Part
		-- Support is lost the moment the cluster unanchors, not when it later expires.
		AddSuspects(self, chunk)
		ActiveDebrisParts += 1
		part.Destroying:Once(function()
			ActiveDebrisParts = math.max(ActiveDebrisParts - 1, 0)
			if self.ChunksById[chunk.Id] == chunk then
				RecordVoid(self, chunk)
				RemoveChunk(self, chunk)
			end
		end)

		if not collect then
			if hold > 0 then
				task.delay(hold, function()
					if not part.Parent then
						return
					end
					TweenService:Create(part, TweenInfo.new(fade, Enum.EasingStyle.Linear), {
						Transparency = 1,
					}):Play()
				end)
			else
				TweenService:Create(part, TweenInfo.new(fade, Enum.EasingStyle.Linear), {
					Transparency = 1,
				}):Play()
			end
			DebrisService:AddItem(part, lifetime)
		else
			-- Client clones at hold; destroy shortly after so mass teardown is not mid-flight
			DebrisService:AddItem(part, hold + 0.05)
		end
	end
end

local function LaunchDebris(
	self: PreparedRoot,
	debrisCandidates: { Chunk },
	position: Vector3,
	fractureSettings: Settings.FractureSettings
)
	local debrisBudget = math.min(fractureSettings.MaxDebrisParts, MAX_GLOBAL_DEBRIS_PARTS - ActiveDebrisParts)
	if debrisBudget <= 0 then
		return
	end

	table.sort(debrisCandidates, function(chunkA, chunkB)
		return Geometry.GetDistanceToPart(chunkA.Part, position) < Geometry.GetDistanceToPart(chunkB.Part, position)
	end)

	local candidatesById: { [number]: Chunk } = {}
	for _, chunk in debrisCandidates do
		candidatesById[chunk.Id] = chunk
	end

	local selectedChunks: { [number]: boolean } = {}
	local promotedCount = 0
	local clusterSize = fractureSettings.DebrisClusterSize
	local grain = math.max(
		fractureSettings.MicroChunkSize.X,
		fractureSettings.MicroChunkSize.Y,
		fractureSettings.MicroChunkSize.Z
	)
	local maxAxis = math.min(self.Settings.MaxChunkAxis, grain * (1 + MICRO_CHUNK_VARIATION) + 0.25)
	for _, seed in debrisCandidates do
		if promotedCount >= debrisBudget then
			break
		end
		if selectedChunks[seed.Id] or not CanLaunchDebris(self, seed, maxAxis) then
			continue
		end

		local targetSize = if seed.KeepWhole then 1 else RandomGenerator:NextInteger(clusterSize.Min, clusterSize.Max)
		local cluster = BuildDebrisCluster(
			self,
			seed,
			candidatesById,
			selectedChunks,
			math.min(targetSize, debrisBudget - promotedCount),
			maxAxis
		)
		if #cluster > 0 then
			LaunchDebrisCluster(self, cluster, position, fractureSettings)
			promotedCount += #cluster
		end
	end
end

local function PushLooseParts(self: PreparedRoot, position: Vector3, settings: Settings.FractureSettings)
	-- Let physics rebuild assemblies after weld removal before applying their new velocity.
	RunService.Heartbeat:Once(function()
		if self.Destroyed then
			return
		end
		debug.profilebegin("ClassicDestruction.Push")

		local overlapParameters = OverlapParams.new()
		overlapParameters.FilterType = Enum.RaycastFilterType.Include
		overlapParameters.FilterDescendantsInstances = { self.Instance }
		local assemblyDistances: { [BasePart]: number } = {}
		for _, part in Workspace:GetPartBoundsInRadius(position, settings.Radius, overlapParameters) do
			local root = part.AssemblyRootPart or part
			if root.Anchored then
				continue
			end

			local distance = Geometry.GetDistanceToPart(part, position)
			if distance <= settings.Radius and distance < (assemblyDistances[root] or math.huge) then
				assemblyDistances[root] = distance
			end
		end

		for root, distance in assemblyDistances do
			local offset = root.AssemblyCenterOfMass - position
			local outward = if offset.Magnitude > 0.01 then offset.Unit else settings.ImpactDirection
			local proximity = 1 - math.clamp(distance / settings.Radius, 0, 1)
			local forceScale = CLASSIC_EDGE_FORCE_SCALE + (1 - CLASSIC_EDGE_FORCE_SCALE) * proximity
			local velocity = (
				(settings.ImpactDirection * 1.5 + outward * 0.5) * settings.DebrisSpeed
				+ Vector3.yAxis * settings.UpwardDebrisSpeed * 0.5
			) * forceScale
			root.AssemblyLinearVelocity += velocity
			root.AssemblyAngularVelocity += Vector3.new(
				RandomGenerator:NextNumber(-6, 6),
				RandomGenerator:NextNumber(-6, 6),
				RandomGenerator:NextNumber(-6, 6)
			)
		end
		debug.profileend()
	end)
end

function PreparedRoot.DetachPart(self: PreparedRoot, part: BasePart): boolean
	local chunk = self.ChunksByPart[part]
	if self.Destroyed or not chunk or not part.Parent then
		return false
	end
	if self.Settings.AttachmentMode ~= "Welded" then
		AddSuspects(self, chunk)
	end
	RemoveChunk(self, chunk)
	part.Anchored = false
	part.Destroying:Once(function()
		if not self.Destroyed then
			RecordVoid(self, chunk)
		end
	end)
	ScheduleSupportResolve(self)
	return true
end

local function FractureStage(
	self: PreparedRoot,
	position: Vector3,
	fractureSettings: Settings.FractureSettings,
	nearbyParts: { BasePart },
	distances: { [BasePart]: number },
	processedOrigins: { [number]: boolean }?
): { BasePart }
	local activePartCount = 0
	local stageParts: { BasePart } = {}
	for _, nearbyPart in nearbyParts do
		if self.ChunksByPart[nearbyPart] then
			activePartCount += 1
			nearbyParts[activePartCount] = nearbyPart
			if distances[nearbyPart] <= fractureSettings.Radius then
				table.insert(stageParts, nearbyPart)
			end
		end
	end
	for partIndex = #nearbyParts, activePartCount + 1, -1 do
		nearbyParts[partIndex] = nil
	end

	table.sort(stageParts, function(partA, partB)
		return distances[partA] < distances[partB]
	end)

	local fracturedParts: { BasePart } = {}
	local debrisCandidates: { Chunk } = {}
	local processedChunks = 0
	local createdChunks = 0
	local destroyedChunks = 0
	local canFracture = fractureSettings.CanFracture
	local innerRadius = fractureSettings.Radius * INNER_CRATER_RATIO
	local micro = fractureSettings.MicroChunkSize
	local fineExtent = math.max(micro.X, micro.Y, micro.Z)

	for _, nearbyPart in stageParts do
		if processedChunks >= fractureSettings.MaxPartsToFracture then
			break
		end

		local sourceChunk = self.ChunksByPart[nearbyPart]
		if
			not sourceChunk
			or (processedOrigins and processedOrigins[sourceChunk.OriginId])
			or (canFracture and not canFracture(nearbyPart))
		then
			continue
		end

		processedChunks += 1
		if processedOrigins then
			processedOrigins[sourceChunk.OriginId] = true
		end
		local sourcePart = sourceChunk.Part
		if self.Settings.BreakJointsOnImpact then
			if self:DetachPart(sourcePart) then
				sourcePart:SetAttribute(
					DEBRIS_OWNER_ATTRIBUTE,
					if fractureSettings.SourcePlayer then fractureSettings.SourcePlayer.UserId else nil
				)
				table.insert(fracturedParts, sourcePart)
			end
			continue
		end
		if sourceChunk.KeepWhole then
			if fractureSettings.MaxDebrisParts > 0 and not sourceChunk.IsDebris then
				table.insert(fracturedParts, sourcePart)
				table.insert(debrisCandidates, sourceChunk)
			end
			continue
		end

		local centerDistance = (sourcePart.Position - position).Magnitude
		if sourceChunk.Stage >= MAX_FRACTURE_STAGES then
			local surfaceDistance = distances[sourcePart]
			if surfaceDistance <= fractureSettings.Radius and destroyedChunks < fractureSettings.MaxChunksDestroyed then
				DestroyChunk(self, sourceChunk)
				destroyedChunks += 1
			elseif fractureSettings.MaxDebrisParts > 0 and not sourceChunk.IsDebris then
				table.insert(fracturedParts, sourcePart)
				table.insert(debrisCandidates, sourceChunk)
			end
			continue
		end

		local remainingChunkBudget = fractureSettings.MaxChunksCreated - createdChunks
		local sourceTemplate = sourceChunk.Template
		local chunkExtent = math.max(sourcePart.Size.X, sourcePart.Size.Y, sourcePart.Size.Z)
		local canSplit = remainingChunkBudget > 0 and sourcePart:IsA("Part") and sourceTemplate:IsA("Part")
		if centerDistance <= innerRadius and chunkExtent <= fineExtent then
			if destroyedChunks < fractureSettings.MaxChunksDestroyed then
				DestroyChunk(self, sourceChunk)
				destroyedChunks += 1
			end
			continue
		end

		if not canSplit then
			continue
		end

		local replacementChunks: { Chunk } = CreateChunks(
			self,
			sourcePart :: Part,
			micro,
			MICRO_CHUNK_VARIATION,
			remainingChunkBudget,
			sourceChunk.Stage + 1,
			sourceChunk.IsAnchor,
			sourceTemplate :: Part,
			sourceChunk.DestParent,
			false
		)
		if #replacementChunks == 0 then
			if chunkExtent <= fineExtent then
				local surfaceDistance = distances[sourcePart]
				if
					surfaceDistance <= fractureSettings.Radius
					and destroyedChunks < fractureSettings.MaxChunksDestroyed
				then
					DestroyChunk(self, sourceChunk)
					destroyedChunks += 1
				elseif fractureSettings.MaxDebrisParts > 0 and not sourceChunk.IsDebris then
					table.insert(fracturedParts, sourcePart)
					table.insert(debrisCandidates, sourceChunk)
				end
			elseif fractureSettings.MaxDebrisParts > 0 and not sourceChunk.IsDebris then
				table.insert(fracturedParts, sourcePart)
				table.insert(debrisCandidates, sourceChunk)
			end
			continue
		end

		for _, replacementChunk in replacementChunks do
			replacementChunk.OriginId = sourceChunk.OriginId
			replacementChunk.HasAnchorContact = sourceChunk.HasAnchorContact
		end

		-- Replacements may all fall inside the crater, so the old neighbors still need a recheck.
		AddSuspects(self, sourceChunk)
		RemoveChunk(self, sourceChunk)
		sourcePart:Destroy()
		createdChunks += #replacementChunks

		local survivingChunks: { Chunk } = {}
		for _, replacementChunk in replacementChunks do
			table.insert(nearbyParts, replacementChunk.Part)
			distances[replacementChunk.Part] = Geometry.GetDistanceToPart(replacementChunk.Part, position)
			local replacementExtent =
				math.max(replacementChunk.Part.Size.X, replacementChunk.Part.Size.Y, replacementChunk.Part.Size.Z)
			if
				destroyedChunks < fractureSettings.MaxChunksDestroyed
				and replacementExtent <= fineExtent
				and (replacementChunk.Part.Position - position).Magnitude <= fractureSettings.Radius
			then
				DestroyChunk(self, replacementChunk)
				destroyedChunks += 1
			else
				table.insert(survivingChunks, replacementChunk)
				table.insert(fracturedParts, replacementChunk.Part)
				table.insert(debrisCandidates, replacementChunk)
			end
		end

		for _, replacementChunk in survivingChunks do
			local touchingParts = ConnectNearbyChunks(self, replacementChunk)
			RecordAnchorContact(self, replacementChunk, touchingParts)
		end
		CreateWelds(self, survivingChunks)
		if self.Settings.AttachmentMode == "AnchoredSupport" then
			WeldLooseNeighbors(self, survivingChunks)
		end
	end

	if self.Settings.BreakJointsOnImpact then
		PushLooseParts(self, position, fractureSettings)
	else
		LaunchDebris(self, debrisCandidates, position, fractureSettings)
	end
	return fracturedParts
end

local function GetFractureCandidates(
	self: PreparedRoot,
	position: Vector3,
	radius: number
): ({ BasePart }, { [BasePart]: number })
	local overlapParameters = OverlapParams.new()
	overlapParameters.FilterType = Enum.RaycastFilterType.Include
	overlapParameters.FilterDescendantsInstances = { self.Instance }
	local nearbyParts: { BasePart } = {}
	local distances: { [BasePart]: number } = {}
	for _, nearbyPart in Workspace:GetPartBoundsInRadius(position, radius, overlapParameters) do
		if self.ChunksByPart[nearbyPart] then
			table.insert(nearbyParts, nearbyPart)
			distances[nearbyPart] = Geometry.GetDistanceToPart(nearbyPart, position)
		end
	end

	return nearbyParts, distances
end

function PreparedRoot.FractureAtStages(
	self: PreparedRoot,
	position: Vector3,
	fractureSettingsList: { Settings.FractureSettings }
): { BasePart }
	if self.Destroyed or not self.Instance:IsDescendantOf(game) then
		return {}
	end

	local maximumRadius = 0
	for _, fractureSettings in fractureSettingsList do
		if fractureSettings.MaxPartsToFracture > 0 then
			maximumRadius = math.max(maximumRadius, fractureSettings.Radius)
		end
	end
	if maximumRadius <= 0 then
		return {}
	end

	CleanMissingChunks(self)

	local fracturedParts: { BasePart } = {}
	local sharedNearbyParts: { BasePart }? = nil
	local sharedDistances: { [BasePart]: number }? = nil
	if self.Settings.AttachmentMode ~= "Welded" or self.Settings.BreakJointsOnImpact then
		sharedNearbyParts, sharedDistances = GetFractureCandidates(self, position, maximumRadius)
	end

	for _, fractureSettings in fractureSettingsList do
		if fractureSettings.Radius <= 0 or fractureSettings.MaxPartsToFracture <= 0 then
			continue
		end

		local nearbyParts: { BasePart }
		local distances: { [BasePart]: number }
		if sharedNearbyParts and sharedDistances then
			nearbyParts = sharedNearbyParts
			distances = sharedDistances
		else
			nearbyParts, distances = GetFractureCandidates(self, position, fractureSettings.Radius)
		end
		for _, fracturedPart in FractureStage(self, position, fractureSettings, nearbyParts, distances) do
			table.insert(fracturedParts, fracturedPart)
		end
	end

	ScheduleSupportResolve(self)
	return fracturedParts
end

function PreparedRoot.FractureBatch(self: PreparedRoot, fractureRequests: { FractureRequest }): { BasePart }
	if self.Destroyed or #fractureRequests == 0 or not self.Instance:IsDescendantOf(game) then
		return {}
	end

	local center = Vector3.zero
	for _, fractureRequest in fractureRequests do
		center += fractureRequest.Position
	end
	center /= #fractureRequests

	local queryRadius = 0
	for _, fractureRequest in fractureRequests do
		queryRadius =
			math.max(queryRadius, (fractureRequest.Position - center).Magnitude + fractureRequest.Settings.Radius)
	end
	if queryRadius <= 0 then
		return {}
	end

	CleanMissingChunks(self)
	local nearbyParts = GetFractureCandidates(self, center, queryRadius)
	local processedOrigins: { [number]: boolean } = {}
	local fracturedParts: { BasePart } = {}

	for _, fractureRequest in fractureRequests do
		local fractureSettings = fractureRequest.Settings
		if fractureSettings.Radius <= 0 or fractureSettings.MaxPartsToFracture <= 0 then
			continue
		end

		local distances: { [BasePart]: number } = {}
		for _, nearbyPart in nearbyParts do
			distances[nearbyPart] = Geometry.GetDistanceToPart(nearbyPart, fractureRequest.Position)
		end
		for _, fracturedPart in
			FractureStage(self, fractureRequest.Position, fractureSettings, nearbyParts, distances, processedOrigins)
		do
			table.insert(fracturedParts, fracturedPart)
		end
	end

	ScheduleSupportResolve(self)
	return fracturedParts
end

function PreparedRoot.FractureAt(
	self: PreparedRoot,
	position: Vector3,
	fractureSettings: Settings.FractureSettings
): { BasePart }
	return self:FractureAtStages(position, { fractureSettings })
end

local function HasVoidSupport(self: PreparedRoot, void: Void): boolean
	if void.IsAnchor or void.HasAnchorContact then
		return true
	end

	for neighborId in void.Neighbors do
		local neighbor = self.ChunksById[neighborId]
		if neighbor and neighbor.Part.Parent and not neighbor.IsDebris then
			return true
		end
	end

	local overlapParameters = OverlapParams.new()
	overlapParameters.FilterType = Enum.RaycastFilterType.Include
	overlapParameters.FilterDescendantsInstances = { self.Instance }
	for _, nearbyPart in Workspace:GetPartBoundsInBox(void.CFrame, void.Size + CONTACT_QUERY_PADDING, overlapParameters) do
		local nearbyChunk = self.ChunksByPart[nearbyPart]
		if nearbyChunk and not nearbyChunk.IsDebris then
			return true
		end
	end

	return false
end

-- Live chunk still sits on its write-once pose (not drifted / debris).
local function IsSettled(self: PreparedRoot, chunk: Chunk): boolean
	if chunk.IsDebris or not chunk.Part.Parent then
		return false
	end
	local pose = self.Poses[chunk.Id]
	if not pose then
		return false
	end
	return (chunk.Part.Position - pose.CFrame.Position).Magnitude <= DRIFT
end

-- Chunks reachable from base/anchors through settled (non-drifted) neighbors.
local function CollectBridged(self: PreparedRoot): { [number]: true }
	local bridged: { [number]: true } = {}
	local pending: { Chunk } = {}

	for _, chunk in self.ChunksById do
		if not IsSettled(self, chunk) then
			continue
		end
		-- Prefer base seeds; HasAnchorContact is recorded at prepare / fracture time.
		if chunk.IsAnchor or chunk.HasAnchorContact or HasActiveAnchorContact(self, chunk) then
			bridged[chunk.Id] = true
			table.insert(pending, chunk)
		end
	end

	-- No tagged base: any settled chunk can start a local bridge network.
	if #pending == 0 then
		for _, chunk in self.ChunksById do
			if IsSettled(self, chunk) then
				bridged[chunk.Id] = true
			end
		end
		return bridged
	end

	local index = 1
	while index <= #pending do
		local chunk = pending[index]
		index += 1
		for neighborId in chunk.Neighbors do
			local neighbor = self.ChunksById[neighborId]
			if neighbor and not bridged[neighborId] and IsSettled(self, neighbor) then
				bridged[neighborId] = true
				table.insert(pending, neighbor)
			end
		end
	end

	return bridged
end

-- Reclaim only when pose touches a settled bridge back to base.
local function HasBridgeSupport(self: PreparedRoot, void: Void, bridged: { [number]: true }): boolean
	if void.IsAnchor or void.HasAnchorContact then
		return true
	end

	for neighborId in void.Neighbors do
		if bridged[neighborId] then
			return true
		end
	end

	local overlapParameters = OverlapParams.new()
	overlapParameters.FilterType = Enum.RaycastFilterType.Include
	overlapParameters.FilterDescendantsInstances = { self.Instance }
	for _, nearbyPart in Workspace:GetPartBoundsInBox(void.CFrame, void.Size + CONTACT_QUERY_PADDING, overlapParameters) do
		local nearbyChunk = self.ChunksByPart[nearbyPart]
		if nearbyChunk and bridged[nearbyChunk.Id] then
			return true
		end
	end

	return false
end

-- Shared by FindVoids and PopVoid so the bridge scan runs once per repair tick.
local function CollectVoids(
	self: PreparedRoot,
	position: Vector3,
	radius: number,
	canRepair: ((part: BasePart) -> boolean)?,
	allowConsume: boolean?
): ({ VoidInfo }, { [number]: true }?)
	local voids: { VoidInfo } = {}
	if self.Destroyed or radius <= 0 then
		return voids, nil
	end

	local consume = if allowConsume == nil then true else allowConsume
	local radiusSq = radius * radius

	if consume then
		for _, void in self.VoidsById do
			if not void.Parent or not void.Template then
				continue
			end
			if canRepair and not canRepair(void.Template) then
				continue
			end

			local delta = void.CFrame.Position - position
			local distanceSq = delta:Dot(delta)
			if distanceSq > radiusSq then
				continue
			end
			if not HasVoidSupport(self, void) then
				continue
			end

			table.insert(voids, {
				Position = void.CFrame.Position,
				Distance = math.sqrt(distanceSq),
				Void = void,
			})
		end
	end

	local nearbyLooseChunks: { { Chunk: Chunk, Pose: Pose, Drift: number, DistanceSq: number } } = {}
	for chunkId, chunk in self.LooseChunks do
		if chunk.IsDebris or not chunk.Part.Parent then
			self.LooseChunks[chunkId] = nil
			continue
		end
		local pose = self.Poses[chunk.Id]
		if not pose then
			continue
		end

		local drift = (chunk.Part.Position - pose.CFrame.Position).Magnitude
		if drift <= DRIFT then
			continue
		end

		if drift > RECLAIM and not consume then
			continue
		end
		if canRepair and not canRepair(chunk.Template) then
			continue
		end
		local delta = pose.CFrame.Position - position
		local distanceSq = delta:Dot(delta)
		if distanceSq <= radiusSq then
			table.insert(nearbyLooseChunks, {
				Chunk = chunk,
				Pose = pose,
				Drift = drift,
				DistanceSq = distanceSq,
			})
		end
	end

	local bridged: { [number]: true }? = if #nearbyLooseChunks > 0 then CollectBridged(self) else nil
	local settled: { [number]: true } = bridged or {}
	for _, candidate in nearbyLooseChunks do
		local chunk = candidate.Chunk
		local pose = candidate.Pose

		local neighbors: { [number]: true } = {}
		for neighborId in chunk.Neighbors do
			neighbors[neighborId] = true
		end

		local reclaim: Void = {
			Id = chunk.Id,
			OriginId = chunk.OriginId,
			CFrame = pose.CFrame,
			Size = pose.Size,
			Stage = chunk.Stage,
			IsAnchor = chunk.IsAnchor,
			HasAnchorContact = chunk.HasAnchorContact,
			Template = chunk.Template,
			Parent = chunk.DestParent,
			Name = chunk.Part.Name,
			Neighbors = neighbors,
			Consumes = candidate.Drift > RECLAIM,
			Stray = chunk.Part,
			KeepWhole = chunk.KeepWhole,
		}

		-- Skip floated islands until a settled path from base reaches this pose.
		if not HasBridgeSupport(self, reclaim, settled) then
			continue
		end

		table.insert(voids, {
			Position = reclaim.CFrame.Position,
			Distance = math.sqrt(candidate.DistanceSq),
			Void = reclaim,
		})
	end

	table.sort(voids, function(a, b)
		if math.abs(a.Position.Y - b.Position.Y) > 0.05 then
			return a.Position.Y < b.Position.Y
		end
		return a.Distance < b.Distance
	end)

	return voids, bridged
end

function PreparedRoot.FindVoids(
	self: PreparedRoot,
	position: Vector3,
	radius: number,
	canRepair: ((part: BasePart) -> boolean)?,
	allowConsume: boolean?
): { VoidInfo }
	local voids = CollectVoids(self, position, radius, canRepair, allowConsume)
	return voids
end

function PreparedRoot.PopVoid(
	self: PreparedRoot,
	position: Vector3,
	radius: number,
	canRepair: ((part: BasePart) -> boolean)?,
	allowConsume: boolean?
): Void?
	local voidInfos, bridged = CollectVoids(self, position, radius, canRepair, allowConsume)
	local info = voidInfos[1]
	if not info then
		return nil
	end

	local void = info.Void
	local settled = bridged or CollectBridged(self)
	if void.Consumes then
		-- Ledger void from a destroyed chunk.
		if self.VoidsById[void.Id] == void then
			if not HasVoidSupport(self, void) then
				return nil
			end
			self.VoidsById[void.Id] = nil
			self.Poses[void.Id] = nil
			return void
		end

		-- Far drifted live chunk: delete stray and spend material (no fly-back).
		if not HasBridgeSupport(self, void, settled) then
			return nil
		end
		local stray = void.Stray
		if not stray or not stray.Parent then
			return nil
		end
		local chunk = self.ChunksByPart[stray]
		if not chunk or chunk.Id ~= void.Id then
			return nil
		end

		RemoveTag(stray, CHUNK_TAG)
		RemoveChunk(self, chunk)
		self.Poses[void.Id] = nil
		stray:Destroy()
		void.Stray = nil
		return void
	end

	if not HasBridgeSupport(self, void, settled) then
		return nil
	end

	local stray = void.Stray
	if not stray or not stray.Parent then
		return nil
	end
	local chunk = self.ChunksByPart[stray]
	if not chunk or chunk.Id ~= void.Id then
		return nil
	end

	RemoveTag(stray, CHUNK_TAG)
	RemoveChunk(self, chunk)
	self.Poses[void.Id] = nil

	stray.Anchored = true
	stray.CanCollide = false
	stray.CanTouch = false
	stray.CanQuery = false
	stray.AssemblyLinearVelocity = Vector3.zero
	stray.AssemblyAngularVelocity = Vector3.zero

	return void
end

function PreparedRoot.CommitVoid(self: PreparedRoot, void: Void): BasePart?
	if self.Destroyed or not void.Parent or not void.Template then
		return nil
	end
	if not void.Parent:IsDescendantOf(self.Instance) and void.Parent ~= self.Instance then
		return nil
	end

	local stray = void.Stray
	if stray then
		if stray.Parent then
			stray:Destroy()
		end
		void.Stray = nil
	end

	local chunkPart: BasePart
	if void.KeepWhole then
		chunkPart = void.Template:Clone()
	elseif void.Template:IsA("TrussPart") then
		chunkPart = Truss.CloneSegment(void.Template)
	else
		assert(void.Template:IsA("Part"), "Split chunk templates must be Parts")
		local part = Instance.new("Part")
		CopyPartProperties(void.Template, part)
		CopyPartMetadata(void.Template, part)
		chunkPart = part
	end
	chunkPart.Name = void.Name
	chunkPart.Size = void.Size
	if self.Settings.AttachmentMode == "Welded" then
		chunkPart.Anchored = void.IsAnchor
	end
	chunkPart.CFrame = void.CFrame
	chunkPart.Transparency = void.Template.Transparency
	chunkPart.Parent = void.Parent

	local chunk = AddChunk(self, chunkPart, void.Stage, void.IsAnchor, void.Template, void.Parent)
	chunk.OriginId = void.OriginId
	chunk.HasAnchorContact = void.HasAnchorContact

	for neighborId in void.Neighbors do
		local neighbor = self.ChunksById[neighborId]
		if neighbor and neighbor.Part.Parent then
			ConnectChunks(chunk, neighbor)
		end
	end
	local touchingParts = ConnectNearbyChunks(self, chunk)
	RecordAnchorContact(self, chunk, touchingParts)
	CreateWelds(self, { chunk })
	table.insert(self.Suspects, chunk)
	ResolveSuspects(self)

	return chunkPart
end

function PreparedRoot.RepairAt(
	self: PreparedRoot,
	position: Vector3,
	repairSettings: Settings.RepairSettings
): { BasePart }
	if self.Destroyed or repairSettings.Radius <= 0 or repairSettings.Count <= 0 then
		return {}
	end

	local created: { BasePart } = {}
	for _ = 1, repairSettings.Count do
		local void = self:PopVoid(position, repairSettings.Radius, repairSettings.CanRepair, true)
		if not void then
			break
		end
		local part = self:CommitVoid(void)
		if part then
			table.insert(created, part)
		end
	end
	return created
end

function PreparedRoot.Destroy(self: PreparedRoot)
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	if self.RemovalConnection then
		self.RemovalConnection:Disconnect()
		self.RemovalConnection = nil
	end
	table.clear(self.RemovedParts)

	if self.DestroyConnection then
		self.DestroyConnection:Disconnect()
		self.DestroyConnection = nil
	end

	for _, chunk in self.ChunksById do
		RemoveWelds(self, chunk)
		if chunk.Part.Parent then
			RemoveTag(chunk.Part, CHUNK_TAG)
			chunk.Part:SetAttribute(DEBRIS_ATTRIBUTE, nil)
			chunk.Part:SetAttribute(DEBRIS_LIFETIME_ATTRIBUTE, nil)
		end
	end

	for _, template in self.Templates do
		if template then
			template:Destroy()
		end
	end

	table.clear(self.ChunksById)
	table.clear(self.ChunksByPart)
	table.clear(self.LooseChunks)
	table.clear(self.VoidsById)
	table.clear(self.Poses)
	table.clear(self.Templates)
	table.clear(self.Suspects)
	self.OnDestroyed()
end

return PreparedRoot

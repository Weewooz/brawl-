--!strict

export type AttachmentMode = "AnchoredSupport" | "Welded"

-- Optional values used when initially splitting a map into chunks.
export type PrepareOptions = {
	-- Approximate size of the initial chunks created from each map part.
	BaseChunkSize: Vector3?,
	-- Soft budget for chunks created from any single map part; MaxChunkAxis wins if they conflict.
	MaxChunksPerPart: number?,
	-- Hard per-axis stud cap on each created part. Fracture grain is MicroChunkSize; this only blocks oversized slivers.
	MaxChunkAxis: number?,
	-- Approximate length of each pre-split TrussPart segment.
	TrussSegmentLength: number?,
	-- Unanchors chunk groups after they lose every connection to an anchor.
	StructuralIntegrity: boolean?,
	-- Tag identifying permanent supports; unsupported structures use their lowest layer.
	AnchorTag: string?,
	-- Keeps supported chunks anchored or joins them with physical welds.
	AttachmentMode: AttachmentMode?,
	-- Impacts detach existing chunks instead of splitting or deleting them.
	BreakJointsOnImpact: boolean?,
	-- Tag identifying map parts that should never be split.
	IgnoreTag: string?,
}

-- Optional values applied to one explosion or other destructive impact.
export type FractureOptions = {
	-- World-space distance around the impact that can be affected.
	Radius: number?,
	-- Fallback debris direction when a chunk is centered on the impact.
	ImpactDirection: Vector3?,
	-- Approximate size of the smaller chunks created by the impact.
	MicroChunkSize: Vector3?,
	-- Safety limit for existing chunks examined by one impact.
	MaxPartsToFracture: number?,
	-- Safety limit for boundary chunks created by one impact.
	MaxChunksCreated: number?,
	-- Safety limit for chunks completely removed by one impact.
	MaxChunksDestroyed: number?,
	-- Maximum surviving chunks launched as temporary physical debris.
	MaxDebrisParts: number?,
	-- Minimum and maximum neighboring parts welded into each debris assembly.
	DebrisClusterSize: NumberRange?,
	-- Outward speed applied to launched debris.
	DebrisSpeed: number?,
	-- Additional upward speed applied to launched debris.
	UpwardDebrisSpeed: number?,
	-- Seconds before launched debris is removed.
	DebrisLifetime: number?,
	-- Player who caused the fracture; tagged on debris for client collect VFX.
	SourcePlayer: Player?,
	-- Optional final check deciding whether a nearby map part may be fractured.
	CanFracture: ((part: BasePart) -> boolean)?,
}

-- Optional values applied when refilling destroyed chunk voids.
export type RepairOptions = {
	-- World-space distance around the repairer that can be filled.
	Radius: number?,
	-- Maximum voids filled by one repair call.
	Count: number?,
	-- Optional final check deciding whether a void's template part may be repaired.
	CanRepair: ((part: BasePart) -> boolean)?,
}

local DEFAULT_PREPARED_ROOT_SETTINGS = {
	BaseChunkSize = Vector3.new(5, 5, 5),
	MaxChunksPerPart = 180,
	MaxChunkAxis = 8,
	TrussSegmentLength = 4,
	StructuralIntegrity = true,
	AnchorTag = "AnchorPart",
	AttachmentMode = "AnchoredSupport" :: AttachmentMode,
	BreakJointsOnImpact = false,
	IgnoreTag = "IgnoreSplit",
}

local DEFAULT_FRACTURE_SETTINGS = {
	Radius = 5.5,
	ImpactDirection = Vector3.new(0, -1, 0),
	MicroChunkSize = Vector3.new(2, 2, 2),
	MaxPartsToFracture = 64,
	MaxChunksCreated = 160,
	MaxChunksDestroyed = 120,
	MaxDebrisParts = 12,
	DebrisClusterSize = NumberRange.new(1, 1),
	DebrisSpeed = 35,
	UpwardDebrisSpeed = 50,
	DebrisLifetime = 2.8,
	SourcePlayer = nil :: Player?,
	CanFracture = nil :: ((part: BasePart) -> boolean)?,
}

local DEFAULT_REPAIR_SETTINGS = {
	Radius = 8,
	Count = 1,
	CanRepair = nil :: ((part: BasePart) -> boolean)?,
}

-- Complete validated values stored by each prepared root.
export type PreparedRootSettings = typeof(DEFAULT_PREPARED_ROOT_SETTINGS)

-- Complete validated values used for one fracture operation.
export type FractureSettings = typeof(DEFAULT_FRACTURE_SETTINGS)

-- Complete validated values used for one repair operation.
export type RepairSettings = typeof(DEFAULT_REPAIR_SETTINGS)

local Settings = {
	Defaults = table.freeze({
		Prepare = table.freeze(table.clone(DEFAULT_PREPARED_ROOT_SETTINGS)),
		Fracture = table.freeze(table.clone(DEFAULT_FRACTURE_SETTINGS)),
		Repair = table.freeze(table.clone(DEFAULT_REPAIR_SETTINGS)),
	}),
}

local function GetFiniteNumber(value: number?, defaultValue: number): number
	if value == nil or value ~= value or math.abs(value) == math.huge then
		return defaultValue
	end

	return value
end

local function GetPositiveVector(value: Vector3?, defaultValue: Vector3): Vector3
	if
		value == nil
		or value.X ~= value.X
		or value.Y ~= value.Y
		or value.Z ~= value.Z
		or math.abs(value.X) == math.huge
		or math.abs(value.Y) == math.huge
		or math.abs(value.Z) == math.huge
	then
		return defaultValue
	end

	return Vector3.new(math.max(value.X, 0.25), math.max(value.Y, 0.25), math.max(value.Z, 0.25))
end

local function GetTag(value: string?, defaultValue: string): string
	return if value and value ~= "" then value else defaultValue
end

local function GetIntegerRange(value: NumberRange?, defaultValue: NumberRange): NumberRange
	if not value then
		return defaultValue
	end

	local minimum = math.max(math.floor(GetFiniteNumber(value.Min, defaultValue.Min)), 1)
	local maximum = math.max(math.floor(GetFiniteNumber(value.Max, defaultValue.Max)), minimum)
	return NumberRange.new(minimum, maximum)
end

function Settings.GetPreparedRootSettings(options: PrepareOptions?): PreparedRootSettings
	local prepareOptions: PrepareOptions = options or {}

	return {
		BaseChunkSize = GetPositiveVector(prepareOptions.BaseChunkSize, DEFAULT_PREPARED_ROOT_SETTINGS.BaseChunkSize),
		MaxChunksPerPart = math.max(
			math.floor(
				GetFiniteNumber(prepareOptions.MaxChunksPerPart, DEFAULT_PREPARED_ROOT_SETTINGS.MaxChunksPerPart)
			),
			1
		),
		MaxChunkAxis = math.max(
			GetFiniteNumber(prepareOptions.MaxChunkAxis, DEFAULT_PREPARED_ROOT_SETTINGS.MaxChunkAxis),
			0.25
		),
		TrussSegmentLength = math.max(
			GetFiniteNumber(prepareOptions.TrussSegmentLength, DEFAULT_PREPARED_ROOT_SETTINGS.TrussSegmentLength),
			0.25
		),
		StructuralIntegrity = if prepareOptions.StructuralIntegrity == nil
			then DEFAULT_PREPARED_ROOT_SETTINGS.StructuralIntegrity
			else prepareOptions.StructuralIntegrity,
		AnchorTag = GetTag(prepareOptions.AnchorTag, DEFAULT_PREPARED_ROOT_SETTINGS.AnchorTag),
		AttachmentMode = prepareOptions.AttachmentMode or DEFAULT_PREPARED_ROOT_SETTINGS.AttachmentMode,
		BreakJointsOnImpact = prepareOptions.BreakJointsOnImpact == true,
		IgnoreTag = GetTag(prepareOptions.IgnoreTag, DEFAULT_PREPARED_ROOT_SETTINGS.IgnoreTag),
	}
end

function Settings.GetFractureSettings(options: FractureOptions?): FractureSettings
	local fractureOptions: FractureOptions = options or {}
	local impactDirection = fractureOptions.ImpactDirection or DEFAULT_FRACTURE_SETTINGS.ImpactDirection
	if
		impactDirection.X ~= impactDirection.X
		or impactDirection.Y ~= impactDirection.Y
		or impactDirection.Z ~= impactDirection.Z
		or math.abs(impactDirection.X) == math.huge
		or math.abs(impactDirection.Y) == math.huge
		or math.abs(impactDirection.Z) == math.huge
		or impactDirection.Magnitude < 0.001
	then
		impactDirection = DEFAULT_FRACTURE_SETTINGS.ImpactDirection
	end

	return {
		Radius = math.max(GetFiniteNumber(fractureOptions.Radius, DEFAULT_FRACTURE_SETTINGS.Radius), 0),
		ImpactDirection = impactDirection.Unit,
		MicroChunkSize = GetPositiveVector(fractureOptions.MicroChunkSize, DEFAULT_FRACTURE_SETTINGS.MicroChunkSize),
		MaxPartsToFracture = math.max(
			math.floor(
				GetFiniteNumber(fractureOptions.MaxPartsToFracture, DEFAULT_FRACTURE_SETTINGS.MaxPartsToFracture)
			),
			0
		),
		MaxChunksCreated = math.max(
			math.floor(GetFiniteNumber(fractureOptions.MaxChunksCreated, DEFAULT_FRACTURE_SETTINGS.MaxChunksCreated)),
			0
		),
		MaxChunksDestroyed = math.max(
			math.floor(
				GetFiniteNumber(fractureOptions.MaxChunksDestroyed, DEFAULT_FRACTURE_SETTINGS.MaxChunksDestroyed)
			),
			0
		),
		MaxDebrisParts = math.max(
			math.floor(GetFiniteNumber(fractureOptions.MaxDebrisParts, DEFAULT_FRACTURE_SETTINGS.MaxDebrisParts)),
			0
		),
		DebrisClusterSize = GetIntegerRange(
			fractureOptions.DebrisClusterSize,
			DEFAULT_FRACTURE_SETTINGS.DebrisClusterSize
		),
		DebrisSpeed = math.max(GetFiniteNumber(fractureOptions.DebrisSpeed, DEFAULT_FRACTURE_SETTINGS.DebrisSpeed), 0),
		UpwardDebrisSpeed = math.max(
			GetFiniteNumber(fractureOptions.UpwardDebrisSpeed, DEFAULT_FRACTURE_SETTINGS.UpwardDebrisSpeed),
			0
		),
		DebrisLifetime = math.max(
			GetFiniteNumber(fractureOptions.DebrisLifetime, DEFAULT_FRACTURE_SETTINGS.DebrisLifetime),
			0
		),
		SourcePlayer = if fractureOptions.SourcePlayer and fractureOptions.SourcePlayer:IsA("Player")
			then fractureOptions.SourcePlayer
			else nil,
		CanFracture = fractureOptions.CanFracture,
	}
end

function Settings.GetRepairSettings(options: RepairOptions?): RepairSettings
	local repairOptions: RepairOptions = options or {}
	return {
		Radius = math.max(GetFiniteNumber(repairOptions.Radius, DEFAULT_REPAIR_SETTINGS.Radius), 0),
		Count = math.max(math.floor(GetFiniteNumber(repairOptions.Count, DEFAULT_REPAIR_SETTINGS.Count)), 0),
		CanRepair = repairOptions.CanRepair,
	}
end

return Settings

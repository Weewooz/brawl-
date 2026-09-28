--!strict
local PreparedRoot = require(script.PreparedRoot)
local Settings = require(script.Settings)

export type PrepareOptions = Settings.PrepareOptions
export type FractureOptions = Settings.FractureOptions
export type RepairOptions = Settings.RepairOptions
export type AttachmentMode = Settings.AttachmentMode
export type Void = PreparedRoot.Void
export type FractureBatchItem = {
	Position: Vector3,
	Options: FractureOptions?,
}

export type DynamicDestruction = {
	Defaults: typeof(Settings.Defaults),
	PrepareRoot: (root: Instance, prepareOptions: PrepareOptions?) -> { BasePart },
	DetachPart: (part: BasePart) -> boolean,
	FractureAt: (position: Vector3, fractureOptions: FractureOptions?) -> { BasePart },
	FractureAtStages: (position: Vector3, fractureOptionsList: { FractureOptions }) -> { BasePart },
	FractureBatch: (fractureBatch: { FractureBatchItem }) -> { BasePart },
	FindVoids: (
		position: Vector3,
		radius: number,
		canRepair: ((part: BasePart) -> boolean)?,
		allowConsume: boolean?
	) -> {
		{
			Position: Vector3,
			Distance: number,
		}
	},
	PopVoid: (
		position: Vector3,
		radius: number,
		canRepair: ((part: BasePart) -> boolean)?,
		allowConsume: boolean?
	) -> Void?,
	CommitVoid: (void: Void) -> BasePart?,
	RepairAt: (position: Vector3, repairOptions: RepairOptions?) -> { BasePart },
	IsPrepared: (root: Instance) -> boolean,
	Reset: (root: Instance?) -> (),
}

local DynamicDestruction = {
	Defaults = Settings.Defaults,
} :: DynamicDestruction

local PreparedRoots: { [Instance]: PreparedRoot.PreparedRoot } = {}

local function IsValidPosition(position: Vector3): boolean
	return position.X == position.X
		and position.Y == position.Y
		and position.Z == position.Z
		and math.abs(position.X) ~= math.huge
		and math.abs(position.Y) ~= math.huge
		and math.abs(position.Z) ~= math.huge
end

-- Splits a workspace model into destructible chunks.
function DynamicDestruction.PrepareRoot(root: Instance, prepareOptions: PrepareOptions?): { BasePart }
	assert(root:IsA("Model") or root:IsA("Folder"), "DynamicDestruction.PrepareRoot expects a Model or Folder")
	assert(root:IsDescendantOf(workspace), "DynamicDestruction.PrepareRoot expects a root in Workspace")

	local existingRoot = PreparedRoots[root]
	if existingRoot then
		return existingRoot:GetParts()
	end

	local preparedRoot = PreparedRoot.new(root, Settings.GetPreparedRootSettings(prepareOptions), function()
		PreparedRoots[root] = nil
	end)
	PreparedRoots[root] = preparedRoot

	local createdParts = preparedRoot:Prepare()
	if #createdParts == 0 then
		preparedRoot:Destroy()
	end
	return createdParts
end

-- Releases a prepared part intact, preserving a repair void when it is later removed.
function DynamicDestruction.DetachPart(part: BasePart): boolean
	for _, preparedRoot in PreparedRoots do
		if preparedRoot:DetachPart(part) then
			return true
		end
	end
	return false
end

-- Fractures prepared chunks around a world position.
function DynamicDestruction.FractureAt(position: Vector3, fractureOptions: FractureOptions?): { BasePart }
	if not IsValidPosition(position) then
		return {}
	end

	local fractureSettings = Settings.GetFractureSettings(fractureOptions)
	local fracturedParts: { BasePart } = {}

	for _, preparedRoot in PreparedRoots do
		for _, fracturedPart in preparedRoot:FractureAt(position, fractureSettings) do
			table.insert(fracturedParts, fracturedPart)
		end
	end

	return fracturedParts
end

-- Applies sequential fracture stages while sharing their spatial and integrity work.
function DynamicDestruction.FractureAtStages(position: Vector3, fractureOptionsList: { FractureOptions }): { BasePart }
	if not IsValidPosition(position) then
		return {}
	end

	local fractureSettingsList: { Settings.FractureSettings } = {}
	for _, fractureOptions in fractureOptionsList do
		table.insert(fractureSettingsList, Settings.GetFractureSettings(fractureOptions))
	end

	local fracturedParts: { BasePart } = {}
	for _, preparedRoot in PreparedRoots do
		for _, fracturedPart in preparedRoot:FractureAtStages(position, fractureSettingsList) do
			table.insert(fracturedParts, fracturedPart)
		end
	end

	return fracturedParts
end

function DynamicDestruction.FractureBatch(fractureBatch: { FractureBatchItem }): { BasePart }
	local fractureRequests: { PreparedRoot.FractureRequest } = {}
	for _, fractureItem in fractureBatch do
		if IsValidPosition(fractureItem.Position) then
			table.insert(fractureRequests, {
				Position = fractureItem.Position,
				Settings = Settings.GetFractureSettings(fractureItem.Options),
			})
		end
	end
	if #fractureRequests == 0 then
		return {}
	end

	local fracturedParts: { BasePart } = {}
	for _, preparedRoot in PreparedRoots do
		for _, fracturedPart in preparedRoot:FractureBatch(fractureRequests) do
			table.insert(fracturedParts, fracturedPart)
		end
	end

	return fracturedParts
end

function DynamicDestruction.FindVoids(
	position: Vector3,
	radius: number,
	canRepair: ((part: BasePart) -> boolean)?,
	allowConsume: boolean?
): {
	{
		Position: Vector3,
		Distance: number,
	}
}
	local voids: {
		{
			Position: Vector3,
			Distance: number,
		}
	} = {}

	for _, preparedRoot in PreparedRoots do
		for _, void in preparedRoot:FindVoids(position, radius, canRepair, allowConsume) do
			table.insert(voids, {
				Position = void.Position,
				Distance = void.Distance,
			})
		end
	end

	table.sort(voids, function(a, b)
		if math.abs(a.Position.Y - b.Position.Y) > 0.05 then
			return a.Position.Y < b.Position.Y
		end
		return a.Distance < b.Distance
	end)

	return voids
end

function DynamicDestruction.PopVoid(
	position: Vector3,
	radius: number,
	canRepair: ((part: BasePart) -> boolean)?,
	allowConsume: boolean?
): Void?
	for _, preparedRoot in PreparedRoots do
		local void = preparedRoot:PopVoid(position, radius, canRepair, allowConsume)
		if void then
			return void
		end
	end
	return nil
end

function DynamicDestruction.CommitVoid(void: Void): BasePart?
	for _, preparedRoot in PreparedRoots do
		local part = preparedRoot:CommitVoid(void)
		if part then
			return part
		end
	end
	return nil
end

function DynamicDestruction.RepairAt(position: Vector3, repairOptions: RepairOptions?): { BasePart }
	if
		position.X ~= position.X
		or position.Y ~= position.Y
		or position.Z ~= position.Z
		or math.abs(position.X) == math.huge
		or math.abs(position.Y) == math.huge
		or math.abs(position.Z) == math.huge
	then
		return {}
	end

	local repairSettings = Settings.GetRepairSettings(repairOptions)
	local createdParts: { BasePart } = {}

	for _, preparedRoot in PreparedRoots do
		for _, part in preparedRoot:RepairAt(position, repairSettings) do
			table.insert(createdParts, part)
		end
	end

	return createdParts
end

function DynamicDestruction.IsPrepared(root: Instance): boolean
	return PreparedRoots[root] ~= nil
end

function DynamicDestruction.Reset(root: Instance?)
	if root then
		local preparedRoot = PreparedRoots[root]
		if preparedRoot then
			preparedRoot:Destroy()
		end
		return
	end

	local preparedRoots: { PreparedRoot.PreparedRoot } = {}
	for _, preparedRoot in PreparedRoots do
		table.insert(preparedRoots, preparedRoot)
	end
	for _, preparedRoot in preparedRoots do
		preparedRoot:Destroy()
	end
end

return DynamicDestruction

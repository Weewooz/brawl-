--!strict

local CONTACT_TOLERANCE = 0.08
local OVERLAP_TOLERANCE = 0.001
local FACE_OVERLAP_TOLERANCE = 0.01
local MIN = 0.25 -- Smallest legal segment along any axis

local Geometry = {}

local function GetProjectedRadius(part: BasePart, axis: Vector3): number
	local halfSize = part.Size * 0.5
	local partCFrame = part.CFrame

	return math.abs(axis:Dot(partCFrame.XVector)) * halfSize.X
		+ math.abs(axis:Dot(partCFrame.YVector)) * halfSize.Y
		+ math.abs(axis:Dot(partCFrame.ZVector)) * halfSize.Z
end

local function GetBoxAxes(partA: BasePart, partB: BasePart): { Vector3 }
	return {
		partA.CFrame.XVector,
		partA.CFrame.YVector,
		partA.CFrame.ZVector,
		partB.CFrame.XVector,
		partB.CFrame.YVector,
		partB.CFrame.ZVector,
	}
end

local function GetBoxContact(partA: BasePart, partB: BasePart): (boolean, boolean)
	if partA == partB then
		return false, false
	end

	local centerOffset = partB.Position - partA.Position
	local axes = GetBoxAxes(partA, partB)
	local isOverlapping = true

	for _, axis in axes do
		local centerDistance = math.abs(centerOffset:Dot(axis))
		local combinedRadius = GetProjectedRadius(partA, axis) + GetProjectedRadius(partB, axis)
		if centerDistance > combinedRadius + CONTACT_TOLERANCE then
			return false, false
		end
		if combinedRadius - centerDistance <= OVERLAP_TOLERANCE then
			isOverlapping = false
		end
	end

	for axisAIndex = 1, 3 do
		for axisBIndex = 4, 6 do
			local crossAxis = axes[axisAIndex]:Cross(axes[axisBIndex])
			if crossAxis.Magnitude > 0.0001 then
				local axis = crossAxis.Unit
				local centerDistance = math.abs(centerOffset:Dot(axis))
				local combinedRadius = GetProjectedRadius(partA, axis) + GetProjectedRadius(partB, axis)
				if centerDistance > combinedRadius + CONTACT_TOLERANCE then
					return false, false
				end
				if combinedRadius - centerDistance <= OVERLAP_TOLERANCE then
					isOverlapping = false
				end
			end
		end
	end

	return true, isOverlapping
end

local function GetAxisRange(part: BasePart, axis: Vector3, localCenter: number): (number, number)
	local radius = GetProjectedRadius(part, axis)
	return localCenter - radius, localCenter + radius
end

local function GetOverlap(minimumA: number, maximumA: number, minimumB: number, maximumB: number): number
	return math.min(maximumA, maximumB) - math.max(minimumA, minimumB)
end

local function HasFaceContact(partA: BasePart, partB: BasePart): boolean
	local halfSize = partA.Size * 0.5
	local localCenter = partA.CFrame:PointToObjectSpace(partB.Position)
	local xMinimum, xMaximum = GetAxisRange(partB, partA.CFrame.XVector, localCenter.X)
	local yMinimum, yMaximum = GetAxisRange(partB, partA.CFrame.YVector, localCenter.Y)
	local zMinimum, zMaximum = GetAxisRange(partB, partA.CFrame.ZVector, localCenter.Z)

	local xDistance = math.min(math.abs(xMinimum - halfSize.X), math.abs(-halfSize.X - xMaximum))
	local yDistance = math.min(math.abs(yMinimum - halfSize.Y), math.abs(-halfSize.Y - yMaximum))
	local zDistance = math.min(math.abs(zMinimum - halfSize.Z), math.abs(-halfSize.Z - zMaximum))

	return (
		xDistance <= CONTACT_TOLERANCE
		and GetOverlap(-halfSize.Y, halfSize.Y, yMinimum, yMaximum) > FACE_OVERLAP_TOLERANCE
		and GetOverlap(-halfSize.Z, halfSize.Z, zMinimum, zMaximum) > FACE_OVERLAP_TOLERANCE
	)
		or (yDistance <= CONTACT_TOLERANCE and GetOverlap(-halfSize.X, halfSize.X, xMinimum, xMaximum) > FACE_OVERLAP_TOLERANCE and GetOverlap(
			-halfSize.Z,
			halfSize.Z,
			zMinimum,
			zMaximum
		) > FACE_OVERLAP_TOLERANCE)
		or (
			zDistance <= CONTACT_TOLERANCE
			and GetOverlap(-halfSize.X, halfSize.X, xMinimum, xMaximum) > FACE_OVERLAP_TOLERANCE
			and GetOverlap(-halfSize.Y, halfSize.Y, yMinimum, yMaximum) > FACE_OVERLAP_TOLERANCE
		)
end

function Geometry.ArePartsConnected(partA: BasePart, partB: BasePart): boolean
	local isTouching, isOverlapping = GetBoxContact(partA, partB)
	if not isTouching then
		return false
	end
	if isOverlapping then
		return true
	end

	return HasFaceContact(partA, partB) or HasFaceContact(partB, partA)
end

function Geometry.GetDistanceToPart(part: BasePart, position: Vector3): number
	local localPosition = part.CFrame:PointToObjectSpace(position)
	local halfSize = part.Size * 0.5
	local closestLocalPosition = Vector3.new(
		math.clamp(localPosition.X, -halfSize.X, halfSize.X),
		math.clamp(localPosition.Y, -halfSize.Y, halfSize.Y),
		math.clamp(localPosition.Z, -halfSize.Z, halfSize.Z)
	)

	return (part.CFrame:PointToWorldSpace(closestLocalPosition) - position).Magnitude
end

local function AxisFloor(length: number, maxAxis: number): number
	if length <= maxAxis then
		return 1
	end
	return math.ceil(length / maxAxis)
end

-- Split whenever the part is larger than the target. Round-to-nearest left 5-stud
-- voxels as a single cell against a 3.5 target, which skipped fracturing entirely.
local function AxisWant(length: number, target: number): number
	if length <= target then
		return 1
	end
	return math.ceil(length / target - 1e-6)
end

local function ClampTarget(targetSize: Vector3, maxAxis: number): Vector3
	return Vector3.new(
		math.clamp(targetSize.X, MIN, maxAxis),
		math.clamp(targetSize.Y, MIN, maxAxis),
		math.clamp(targetSize.Z, MIN, maxAxis)
	)
end

-- Finest even grid under maxAxis. Axis-wins stops at that floor; budget-wins coarsens further.
local function Solve(
	partSize: Vector3,
	targetSize: Vector3,
	maxChunks: number,
	maxAxis: number,
	axisWins: boolean
): (number, number, number)
	local floorX = AxisFloor(partSize.X, maxAxis)
	local floorY = AxisFloor(partSize.Y, maxAxis)
	local floorZ = AxisFloor(partSize.Z, maxAxis)
	local minX = if axisWins then floorX else 1
	local minY = if axisWins then floorY else 1
	local minZ = if axisWins then floorZ else 1
	local countX = math.max(floorX, AxisWant(partSize.X, targetSize.X))
	local countY = math.max(floorY, AxisWant(partSize.Y, targetSize.Y))
	local countZ = math.max(floorZ, AxisWant(partSize.Z, targetSize.Z))

	while countX * countY * countZ > maxChunks do
		local best: number? = nil
		local bestSeg = -1
		if countX > minX then
			local seg = partSize.X / (countX - 1)
			if seg > bestSeg then
				bestSeg = seg
				best = 1
			end
		end
		if countY > minY then
			local seg = partSize.Y / (countY - 1)
			if seg > bestSeg then
				bestSeg = seg
				best = 2
			end
		end
		if countZ > minZ then
			local seg = partSize.Z / (countZ - 1)
			if seg > bestSeg then
				bestSeg = seg
				best = 3
			end
		end
		if best == 1 then
			countX -= 1
		elseif best == 2 then
			countY -= 1
		elseif best == 3 then
			countZ -= 1
		else
			break
		end
	end

	return countX, countY, countZ
end

-- `count` segments that sum to `length`. Allows oversize when even length exceeds maxAxis.
local function Emit(length: number, count: number, variance: number, maxAxis: number, rng: Random): { number }
	if count <= 1 then
		return { length }
	end

	local even = length / count
	local cap = math.max(maxAxis, even)
	local lo = math.max(MIN, even * (1 - variance))
	local hi = math.min(cap, math.max(lo, even * (1 + variance)))
	local segments: { number } = {}
	local remaining = length

	for index = 1, count - 1 do
		local left = count - index
		local minThis = math.max(lo, remaining - left * cap)
		local maxThis = math.min(hi, remaining - left * MIN)
		if maxThis < minThis then
			minThis = remaining / (left + 1)
			maxThis = minThis
		end
		local size = if maxThis <= minThis then minThis else rng:NextNumber(minThis, maxThis)
		table.insert(segments, size)
		remaining -= size
	end

	table.insert(segments, remaining)
	return segments
end

function Geometry.FitsAxisCap(size: Vector3, maxAxis: number): boolean
	return size.X <= maxAxis and size.Y <= maxAxis and size.Z <= maxAxis
end

-- True when a maxAxis-legal grid fits in maxChunks. Prepare may exceed this soft budget.
function Geometry.CanSubdivide(partSize: Vector3, maxChunks: number, maxAxis: number): boolean
	return AxisFloor(partSize.X, maxAxis) * AxisFloor(partSize.Y, maxAxis) * AxisFloor(partSize.Z, maxAxis) <= maxChunks
end

function Geometry.BuildPartSegments(
	partSize: Vector3,
	targetSize: Vector3,
	variance: number,
	maxChunks: number,
	randomGenerator: Random,
	maxAxis: number,
	axisWins: boolean?
): ({ number }, { number }, { number })
	local target = ClampTarget(targetSize, maxAxis)
	local countX, countY, countZ = Solve(partSize, target, maxChunks, maxAxis, axisWins ~= false)
	return Emit(partSize.X, countX, variance, maxAxis, randomGenerator),
		Emit(partSize.Y, countY, variance, maxAxis, randomGenerator),
		Emit(partSize.Z, countZ, variance, maxAxis, randomGenerator)
end

return Geometry

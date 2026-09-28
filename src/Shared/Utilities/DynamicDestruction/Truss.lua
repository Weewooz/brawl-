--!strict

local Truss = {}

local HEIGHT_INCREMENT = 2

local function ClearChildren(trussPart: TrussPart)
	for _, child in trussPart:GetChildren() do
		if not child:IsA("Decal") and not child:IsA("Texture") then
			child:Destroy()
		end
	end
end

function Truss.CloneSegment(template: TrussPart): TrussPart
	local segment = template:Clone()
	ClearChildren(segment)
	return segment
end

local function GetSegmentHeights(totalHeight: number, targetHeight: number, maximumSegments: number): { number }
	local heightIncrementCount = math.floor(totalHeight / HEIGHT_INCREMENT)
	local remainingHeight = totalHeight - heightIncrementCount * HEIGHT_INCREMENT
	local targetIncrementCount = math.max(math.round(targetHeight / HEIGHT_INCREMENT), 1)
	local segmentCount = math.min(
		math.ceil(heightIncrementCount / targetIncrementCount),
		math.max(math.floor(maximumSegments), 1),
		heightIncrementCount
	)

	if segmentCount <= 1 then
		return { totalHeight }
	end

	local baseIncrementCount = math.floor(heightIncrementCount / segmentCount)
	local extraIncrementCount = heightIncrementCount % segmentCount
	local segmentHeights: { number } = table.create(segmentCount)
	for index = 1, segmentCount do
		local incrementCount = baseIncrementCount + if index <= extraIncrementCount then 1 else 0
		segmentHeights[index] = incrementCount * HEIGHT_INCREMENT
	end

	segmentHeights[segmentCount] += remainingHeight
	return segmentHeights
end

function Truss.Split(sourcePart: TrussPart, segmentLength: number, maximumSegments: number): { TrussPart }
	local sourceSize = sourcePart.Size
	local segmentHeights = GetSegmentHeights(sourceSize.Y, segmentLength, maximumSegments)
	if #segmentHeights <= 1 then
		return {}
	end

	local destinationParent = sourcePart.Parent
	if not destinationParent then
		return {}
	end

	local segments: { TrussPart } = {}
	local bottomPosition = -sourceSize.Y * 0.5
	for _, segmentHeight in segmentHeights do
		local segmentPosition = bottomPosition + segmentHeight * 0.5
		local segment = Truss.CloneSegment(sourcePart)
		segment.Size = Vector3.new(sourceSize.X, segmentHeight, sourceSize.Z)
		segment.CFrame = sourcePart.CFrame * CFrame.new(0, segmentPosition, 0)
		segment.Parent = destinationParent
		table.insert(segments, segment)
		bottomPosition += segmentHeight
	end

	return segments
end

return Truss

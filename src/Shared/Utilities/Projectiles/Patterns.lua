--!strict
local Patterns = {}

local function Basis(direction: Vector3): (Vector3, Vector3)
	local reference = if math.abs(direction.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis
	local right = direction:Cross(reference).Unit
	return right, right:Cross(direction).Unit
end

function Patterns.Directions(
	direction: Vector3,
	count: number,
	spreadDegrees: number,
	seed: number,
	randomness: number?
): { Vector3 }
	if spreadDegrees <= 0 then
		return { direction }
	end

	local directions = table.create(count, direction)
	local right, up = Basis(direction)
	local spread = math.tan(math.rad(spreadDegrees))
	local rotation = (seed * 2.399963229728653) % (math.pi * 2)
	local random = Random.new(seed)
	if count <= 1 then
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = spread * math.sqrt(random:NextNumber())
		local offset = right * math.cos(angle) + up * math.sin(angle)
		return { (direction + offset * distance).Unit }
	end

	local variation = math.clamp(randomness or 0, 0, 1)
	for index = 2, count do
		local spacing = math.pi * 2 / (count - 1)
		local angle = rotation + (index - 2) * spacing + random:NextNumber(-spacing, spacing) * 0.3 * variation
		local distance = spread * random:NextNumber(1 - 0.3 * variation, 1 + 0.2 * variation)
		local offset = right * math.cos(angle) + up * math.sin(angle)
		directions[index] = (direction + offset * distance).Unit
	end
	return directions
end

function Patterns.ClusterPositions(
	position: Vector3,
	normal: Vector3,
	count: number,
	radius: number,
	seed: number
): { Vector3 }
	local positions = table.create(count)
	local right, forward = Basis(normal)
	local rotation = (seed * 2.399963229728653) % (math.pi * 2)
	for index = 1, count do
		local angle = rotation + (index - 1) * math.pi * 2 / count
		local distance = radius * (if index % 2 == 0 then 0.6 else 1)
		positions[index] = position + (right * math.cos(angle) + forward * math.sin(angle)) * distance
	end
	return positions
end

function Patterns.Reflect(direction: Vector3, normal: Vector3): Vector3
	return (direction - normal * (2 * direction:Dot(normal))).Unit
end

return Patterns

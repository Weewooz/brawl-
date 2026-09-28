--!strict
-- Display pose for Tools. Handle grip is often Y-short (sideways).

export type Stand = {
	Lean: (self: Stand, model: Model) -> CFrame,
	Lay: (self: Stand, model: Model, host: CFrame) -> CFrame,
	Snap: (self: Stand, model: Model, host: CFrame) -> CFrame,
}

local Stand = {} :: Stand

local SKIP = {
	BoundingBox = true,
	Hitbox = true,
	Zone = true,
	ChestFloat = true,
	Pad = true,
}

local Turns = table.freeze({
	CFrame.identity,
	CFrame.Angles(math.pi, 0, 0),
	CFrame.Angles(math.pi * 0.5, 0, 0),
	CFrame.Angles(-math.pi * 0.5, 0, 0),
	CFrame.Angles(0, 0, math.pi * 0.5),
	CFrame.Angles(0, 0, -math.pi * 0.5),
})

local function Solid(part: BasePart): boolean
	if SKIP[part.Name] then
		return false
	end
	if part.Transparency >= 1 then
		return false
	end
	return true
end

-- Handle-local visual AABB, so yaw on the host cannot flip the tilt.
local function SizeOf(model: Model): Vector3
	local origin = model:GetPivot()
	local minX, maxX = math.huge, -math.huge
	local minY, maxY = math.huge, -math.huge
	local minZ, maxZ = math.huge, -math.huge
	local found = false
	for _, child in model:GetDescendants() do
		if not child:IsA("BasePart") or not Solid(child) then
			continue
		end
		found = true
		local rel = origin:ToObjectSpace(child.CFrame)
		local sx, sy, sz = child.Size.X, child.Size.Y, child.Size.Z
		local hx = (math.abs(rel.XVector.X) * sx + math.abs(rel.YVector.X) * sy + math.abs(rel.ZVector.X) * sz) * 0.5
		local hy = (math.abs(rel.XVector.Y) * sx + math.abs(rel.YVector.Y) * sy + math.abs(rel.ZVector.Y) * sz) * 0.5
		local hz = (math.abs(rel.XVector.Z) * sx + math.abs(rel.YVector.Z) * sy + math.abs(rel.ZVector.Z) * sz) * 0.5
		local pos = rel.Position
		minX = math.min(minX, pos.X - hx)
		maxX = math.max(maxX, pos.X + hx)
		minY = math.min(minY, pos.Y - hy)
		maxY = math.max(maxY, pos.Y + hy)
		minZ = math.min(minZ, pos.Z - hz)
		maxZ = math.max(maxZ, pos.Z + hz)
	end
	if not found then
		local _, size = model:GetBoundingBox()
		return size
	end
	return Vector3.new(maxX - minX, maxY - minY, maxZ - minZ)
end

local function Center(model: Model, host: CFrame)
	local box = model:GetBoundingBox()
	local delta = host.Position - box.Position
	if delta.Magnitude > 1e-4 then
		model:PivotTo(model:GetPivot() + delta)
	end
end

local function Rate(size: Vector3): number
	local longest = math.max(size.X, size.Y, size.Z)
	local lying = if size.Y + 0.01 < longest then 1000 else 0
	return lying - size.Y * 10 + math.max(size.X, size.Z)
end

-- If Y is shortest (on its side), roll so the barrel stays horizontal.
function Stand:Lean(model: Model): CFrame
	local size = SizeOf(model)
	local x, y, z = size.X, size.Y, size.Z
	if y - 1e-3 > math.min(x, y, z) then
		return CFrame.identity
	end
	if x < z then
		return CFrame.Angles(0, 0, math.rad(90))
	end
	return CFrame.Angles(math.rad(90), 0, 0)
end

-- Pedestal: pick the flattest barrel-along-pad pose.
function Stand:Lay(model: Model, host: CFrame): CFrame
	local best = CFrame.identity
	local bestScore = -math.huge
	for _, rot in Turns do
		model:PivotTo(host * rot)
		local score = Rate(SizeOf(model))
		if score > bestScore then
			bestScore = score
			best = rot
		end
	end
	model:PivotTo(host * best)
	Center(model, host)
	return best
end

function Stand:Snap(model: Model, host: CFrame): CFrame
	model:PivotTo(host)
	local lean = self:Lean(model)
	if lean ~= CFrame.identity then
		model:PivotTo(host * lean)
	end
	Center(model, host)
	return lean
end

return Stand

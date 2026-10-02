--!strict
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

export type Bounds = {
	MinX: number,
	MaxX: number,
	MinZ: number,
	MaxZ: number,
}

export type Zone = {
	Center: Vector3,
	Entry: Vector3,
	MobSpawns: { Vector3 },
	Gate: Part,
	FloorTop: number,
	Bounds: Bounds,
}

export type Result = {
	Model: Model,
	Zones: { Zone },
}

local Map = {}
local ZONE_X = { 0, 96, 220 }
local LEVEL_HEIGHT = 12
local WIDTH = 72
local DEPTH = 64

function Map.Build(seed: number, origin: Vector3): Result
	local templates = ServerStorage:FindFirstChild("DungeonMaps")
	if not templates then
		error("ServerStorage.DungeonMaps is missing; sync the Rojo dungeon assets", 2)
	end
	local layout = Random.new(seed):NextInteger(1, 3)
	local template = templates:FindFirstChild("Layout" .. layout)
	if not template or not template:IsA("Model") then
		error("Dungeon map layout " .. layout .. " is missing from ServerStorage.DungeonMaps", 2)
	end
	local model = template:Clone()
	model.Name = "DungeonRun"
	model:PivotTo(model:GetPivot() + origin)
	model.Parent = Workspace
	local zones: { Zone } = {}
	for index, offsetX in ZONE_X do
		local zoneModel = model:FindFirstChild("Zone" .. index)
		local gate = zoneModel and zoneModel:FindFirstChild("Gate")
		if not gate or not gate:IsA("Part") then
			model:Destroy()
			error("Dungeon layout " .. layout .. " lacks Zone" .. index .. ".Gate", 2)
		end
		local centerX = origin.X + offsetX
		local floorTop = origin.Y + (if index == 3 then LEVEL_HEIGHT else 0)
		local spawnY = floorTop + 3
		zones[index] = {
			Center = Vector3.new(centerX, spawnY, origin.Z),
			Entry = Vector3.new(centerX - WIDTH / 2 + 10, spawnY, origin.Z),
			MobSpawns = {
				Vector3.new(centerX - 12, spawnY, origin.Z),
				Vector3.new(centerX + 2, spawnY, origin.Z - 5),
				Vector3.new(centerX + 18, spawnY, origin.Z + 5),
			},
			Gate = gate,
			FloorTop = floorTop,
			Bounds = {
				MinX = centerX - WIDTH / 2,
				MaxX = centerX + WIDTH / 2,
				MinZ = origin.Z - DEPTH / 2,
				MaxZ = origin.Z + DEPTH / 2,
			},
		}
	end
	return { Model = model, Zones = zones }
end

function Map.OpenGate(result: Result, zoneIndex: number)
	local zone = result.Zones[zoneIndex]
	if not zone then
		error("Dungeon zone " .. tostring(zoneIndex) .. " does not exist", 2)
	end
	zone.Gate.CanCollide = false
	zone.Gate.CanTouch = false
	zone.Gate.Transparency = 1
	zone.Gate:SetAttribute("Open", true)
end

return Map

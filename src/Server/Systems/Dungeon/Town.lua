--!strict
local Workspace = game:GetService("Workspace")

export type Result = {
	Model: Model,
	Spawn: SpawnLocation,
	Staging: Part,
	Return: CFrame,
}

local Town = {}
local DIFFICULTIES = { "Easy", "Normal", "Hard" }

function Town.Build(onStart: (Player, string) -> ()): Result
	local model = Workspace:FindFirstChild("TemporaryDungeonTown")
	if not model or not model:IsA("Model") then
		error("Workspace.TemporaryDungeonTown is missing; sync the Rojo dungeon assets", 2)
	end
	local spawn = model:FindFirstChild("DungeonTownSpawn")
	local staging = model:FindFirstChild("PartyStagingZone")
	if not spawn or not spawn:IsA("SpawnLocation") or not staging or not staging:IsA("Part") then
		error("TemporaryDungeonTown is missing its spawn or party staging zone", 2)
	end
	for _, difficulty in DIFFICULTIES do
		local pedestal = model:FindFirstChild(difficulty .. "DungeonStart")
		local prompt = pedestal and pedestal:FindFirstChild("StartDungeon")
		if not prompt or not prompt:IsA("ProximityPrompt") then
			error("TemporaryDungeonTown is missing the " .. difficulty .. " start prompt", 2)
		end
		prompt.Triggered:Connect(function(player)
			onStart(player, difficulty)
		end)
	end
	return {
		Model = model,
		Spawn = spawn,
		Staging = staging,
		Return = CFrame.new(spawn.Position + Vector3.new(0, 3.5, 0)),
	}
end

function Town.Contains(result: Result, position: Vector3): boolean
	local center = result.Staging.Position
	local half = result.Staging.Size * 0.5
	return math.abs(position.X - center.X) <= half.X
		and math.abs(position.Z - center.Z) <= half.Z
		and position.Y >= center.Y - 4
		and position.Y <= center.Y + 16
end

return Town

--!strict
-- Batches world-space hover + yaw into one BulkMoveTo per frame.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

export type Motion = {
	Amp: number?,
	Freq: number?,
	Spin: number?,
	Phase: number?,
}

export type Rotator = {
	Add: (self: Rotator, root: PVInstance, motion: Motion?) -> (),
	Remove: (self: Rotator, root: PVInstance) -> (),
	Pause: (self: Rotator, root: PVInstance, paused: boolean) -> (),
	Spin: (self: Rotator, root: PVInstance, spin: number) -> (),
}

type Pose = {
	Amp: number,
	Freq: number,
	Spin: number,
	Phase: number,
}

type Item = {
	Root: PVInstance,
	Base: CFrame,
	Motion: Pose,
	Paused: boolean,
	Parts: { BasePart },
	Rel: { CFrame },
}

local DEFAULT: Pose = {
	Amp = 0.35,
	Freq = 1.4,
	Spin = 0.95,
	Phase = 0,
}

local MOVE = Enum.BulkMoveMode.FireCFrameChanged

local Rotator = {} :: Rotator

local Items: { [PVInstance]: Item } = {}
local Count = 0
local Clock = 0
local Hook: RBXScriptConnection?
local Parts: { BasePart } = {}
local Frames: { CFrame } = {}
local Stale: { PVInstance } = {}

local function Pack(item: Item)
	local packed = item.Parts
	local rel = item.Rel
	table.clear(packed)
	table.clear(rel)
	local origin = item.Root:GetPivot()
	local function take(part: BasePart)
		if not part.Parent then
			return
		end
		table.insert(packed, part)
		table.insert(rel, origin:ToObjectSpace(part.CFrame))
	end
	local root = item.Root
	if root:IsA("BasePart") then
		take(root)
	end
	for _, child in root:GetDescendants() do
		if child:IsA("BasePart") then
			take(child)
		end
	end
end

local function Blend(pose: Pose, motion: Motion)
	if motion.Amp ~= nil then
		pose.Amp = motion.Amp
	end
	if motion.Freq ~= nil then
		pose.Freq = motion.Freq
	end
	if motion.Spin ~= nil then
		pose.Spin = motion.Spin
	end
	if motion.Phase ~= nil then
		pose.Phase = motion.Phase
	end
end

local function Drop()
	if Hook then
		Hook:Disconnect()
		Hook = nil
	end
end

local function Flush()
	local moved = 0
	table.clear(Stale)
	for root, item in Items do
		if not root.Parent then
			table.insert(Stale, root)
			continue
		end
		if item.Paused then
			continue
		end
		local motion = item.Motion
		local base = item.Base
		local bob = math.sin((Clock + motion.Phase) * motion.Freq) * motion.Amp
		local yaw = (Clock + motion.Phase) * motion.Spin
		local pivot = CFrame.new(base.Position + Vector3.new(0, bob, 0))
			* CFrame.Angles(0, yaw, 0)
			* (base - base.Position)
		for index, part in item.Parts do
			if not part.Parent then
				continue
			end
			moved += 1
			Parts[moved] = part
			Frames[moved] = pivot * item.Rel[index]
		end
	end
	for index = #Parts, moved + 1, -1 do
		Parts[index] = nil
		Frames[index] = nil
	end
	if moved > 0 then
		Workspace:BulkMoveTo(Parts, Frames, MOVE)
	end
	for _, root in Stale do
		Rotator:Remove(root)
	end
end

local function Bind()
	if Hook then
		return
	end
	Hook = RunService.RenderStepped:Connect(function(dt)
		Clock += dt
		Flush()
	end)
end

function Rotator:Add(root: PVInstance, motion: Motion?)
	local item = Items[root]
	if item then
		if motion then
			Blend(item.Motion, motion)
		end
		Pack(item)
		return
	else
		local pose: Pose = {
			Amp = DEFAULT.Amp,
			Freq = DEFAULT.Freq,
			Spin = DEFAULT.Spin,
			Phase = DEFAULT.Phase,
		}
		if motion then
			Blend(pose, motion)
		end

		local newItem = {
			Root = root,
			Base = root:GetPivot(),
			Motion = pose,
			Paused = false,
			Parts = {},
			Rel = {},
		}
		Items[root] = newItem
		Count += 1
		Pack(newItem)
		Bind()
	end
end

function Rotator:Remove(root: PVInstance)
	if not Items[root] then
		return
	end
	Items[root] = nil
	Count -= 1
	if Count > 0 then
		return
	end
	Count = 0
	Drop()
	table.clear(Parts)
	table.clear(Frames)
end

function Rotator:Pause(root: PVInstance, paused: boolean)
	local item = Items[root]
	if item then
		item.Paused = paused
	end
end

-- Change yaw rate without popping the current angle.
function Rotator:Spin(root: PVInstance, spin: number)
	local item = Items[root]
	if not item then
		return
	end
	local pose = item.Motion
	local yaw = (Clock + pose.Phase) * pose.Spin
	pose.Spin = spin
	if math.abs(spin) < 1e-6 then
		pose.Phase = 0
		return
	end
	pose.Phase = yaw / spin - Clock
end

return Rotator

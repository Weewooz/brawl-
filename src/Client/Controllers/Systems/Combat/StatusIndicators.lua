--!strict
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Tags = require(ReplicatedStorage.Shared.Core.Tags)
local Player = Players.LocalPlayer
local INTERVAL = 0.05
local CAPACITY = 16

type Slot = {
	Gui: BillboardGui,
	Label: TextLabel,
	Character: Model?,
}

export type System = {
	Pool: Folder?,
	Slots: { Slot },
	Elapsed: number,
	Init: (self: System) -> (),
	Step: (self: System, dt: number) -> (),
}

local StatusIndicators: System = { Pool = nil, Slots = {}, Elapsed = 0 }

local function Active(character: Model, attribute: string, now: number): boolean
	local value = character:GetAttribute(attribute)
	return typeof(value) == "number" and value > now
end

local function Release(slot: Slot, pool: Folder?)
	slot.Character = nil
	slot.Gui.Enabled = false
	slot.Gui.Adornee = nil
	slot.Gui.Parent = pool
end

function StatusIndicators:Init()
	if self.Pool then
		return
	end
	local pool = ReplicatedStorage.Assets:WaitForChild("CombatStatusPool") :: Folder
	self.Pool = pool
	for index = 1, CAPACITY do
		local gui = pool:WaitForChild(tostring(index)) :: BillboardGui
		local slot: Slot = { Gui = gui, Label = gui:WaitForChild("Label") :: TextLabel, Character = nil }
		Release(slot, pool)
		table.insert(self.Slots, slot)
	end
end

function StatusIndicators:Step(dt: number)
	self.Elapsed += dt
	if self.Elapsed < INTERVAL then
		return
	end
	self.Elapsed %= INTERVAL
	local now = workspace:GetServerTimeNow()
	local eligible: { [Model]: BasePart } = {}
	local character = Player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		for _, instance in CollectionService:GetTagged(Tags.Combatant) do
			if not instance:IsA("Model") or not instance:IsDescendantOf(workspace) then
				continue
			end
			local head = instance:FindFirstChild("Head")
			local humanoid = instance:FindFirstChildOfClass("Humanoid")
			if
				head
				and head:IsA("BasePart")
				and humanoid
				and humanoid.Health > 0
				and (head.Position - root.Position).Magnitude <= 80
				and (Active(instance, "ExposedUntil", now) or Active(instance, "SlowUntil", now))
			then
				eligible[instance] = head
			end
		end
	end
	local assigned: { [Model]: boolean } = {}
	for _, slot in self.Slots do
		local target = slot.Character
		if target and eligible[target] then
			assigned[target] = true
		else
			Release(slot, self.Pool)
		end
	end
	for target in eligible do
		if assigned[target] then
			continue
		end
		for _, slot in self.Slots do
			if not slot.Character then
				slot.Character = target
				break
			end
		end
	end
	for _, slot in self.Slots do
		local target = slot.Character
		if not target then
			continue
		end
		local exposed = Active(target, "ExposedUntil", now)
		local slowed = Active(target, "SlowUntil", now)
		slot.Label.Text = if exposed and slowed then "EXPOSED  /  SLOWED" elseif exposed then "EXPOSED" else "SLOWED"
		slot.Label.TextColor3 = if exposed then Color3.fromRGB(255, 191, 114) else Color3.fromRGB(121, 217, 242)
		slot.Gui.Adornee = eligible[target]
		slot.Gui.Enabled = true
		slot.Gui.Parent = Player.PlayerGui
	end
end

return StatusIndicators

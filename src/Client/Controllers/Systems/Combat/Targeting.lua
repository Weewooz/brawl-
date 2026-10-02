--!strict
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Authority = require(ReplicatedStorage.Shared.Capture.Authority)
local Config = require(ReplicatedStorage.Shared.Combat.Config)
local Weapons = require(ReplicatedStorage.Shared.Combat.Weapons)
local Player = Players.LocalPlayer
local INTERVAL = 0.1
local CAPACITY = 5
local SELECTED_COLOR = Color3.fromRGB(255, 218, 112)
local ENEMY_COLOR = Color3.fromRGB(255, 120, 115)

type Slot = {
	Button: ImageButton,
	Reference: ObjectValue,
	Stroke: UIStroke,
	Fill: Frame,
	Selected: TextLabel,
	Fallback: TextLabel,
	DefaultImage: string,
	Target: Model?,
}

export type System = {
	Gui: ScreenGui?,
	Panel: Frame?,
	Title: TextLabel?,
	Selection: ObjectValue?,
	Marker: BillboardGui?,
	Slots: { Slot },
	Target: Model?,
	Elapsed: number,
	Init: (self: System) -> (),
	Step: (self: System, dt: number) -> (),
	Clear: (self: System) -> (),
	Select: (self: System, target: Model) -> (),
	Direction: (self: System) -> Vector3?,
}

local Targeting: System = {
	Gui = nil,
	Panel = nil,
	Title = nil,
	Selection = nil,
	Marker = nil,
	Slots = {},
	Target = nil,
	Elapsed = 0,
} :: System
local Portraits: { [number]: string } = {}
local Pending: { [number]: boolean } = {}
local Attempts: { [number]: number } = {}
local RetryAt: { [number]: number } = {}
local Sight = RaycastParams.new()
Sight.FilterType = Enum.RaycastFilterType.Exclude
Sight.RespectCanCollide = true

local function AcquireRange(): number
	local definition = Weapons.Get(Weapons.Weapon(Player.Character))
	return if definition and definition.IsRanged then definition.Range else Config.Charge.Range
end

local function Living(model: Model?): (Humanoid?, BasePart?)
	if not model or not model:IsDescendantOf(workspace) then
		return nil, nil
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, nil
	end
	return humanoid, root
end

local function Available(): boolean
	local character = Player.Character
	local humanoid = Living(character)
	local status = Player:GetAttribute("CaptureStatus")
	local gui = Targeting.Gui
	local settings = gui and gui:FindFirstChild("SettingsPanel")
	return humanoid ~= nil
		and character ~= nil
		and Authority.CanAttack(Authority.Read(character), workspace:GetServerTimeNow())
		and (status == nil or status == "Playing" or status == "Practice")
		and not GuiService.MenuIsOpen
		and UserInputService:GetFocusedTextBox() == nil
		and not (settings and settings:IsA("GuiObject") and settings.Visible)
end

local function Eligible(target: Model, range: number): (Vector3?, number)
	local character = Player.Character
	local _, root = Living(character)
	local _, targetRoot = Living(target)
	if
		not character
		or not root
		or not targetRoot
		or target == character
		or not CollectionService:HasTag(target, "Combatant")
		or not Authority.CanHit(Authority.Read(character), Authority.Read(target), workspace:GetServerTimeNow())
	then
		return nil, math.huge
	end
	local displacement = targetRoot.Position - root.Position
	local flat = Vector3.new(displacement.X, 0, displacement.Z)
	local distance = flat.Magnitude
	if distance > range or distance < 0.01 or math.abs(displacement.Y) > Config.Attack.Height then
		return nil, distance
	end
	-- Visible opponents only; selecting a portrait never reveals someone behind cover.
	local camera = workspace.CurrentCamera
	local head = target:FindFirstChild("Head")
	local visiblePosition = if head and head:IsA("BasePart") then head.Position else targetRoot.Position
	if not camera then
		return nil, distance
	end
	local _, onScreen = camera:WorldToViewportPoint(visiblePosition)
	if not onScreen then
		return nil, distance
	end
	local combatants = CollectionService:GetTagged("Combatant")
	table.insert(combatants, character)
	Sight.FilterDescendantsInstances = combatants
	local wall = workspace:Raycast(root.Position, displacement, Sight)
	if wall and not wall.Instance:IsDescendantOf(target) then
		return nil, distance
	end
	return flat.Unit, distance
end

local function Name(target: Model): string
	local player = Players:GetPlayerFromCharacter(target)
	local humanoid = target:FindFirstChildOfClass("Humanoid")
	return if player then player.DisplayName else if humanoid then humanoid.DisplayName else target.Name
end

local function Release(slot: Slot)
	slot.Target = nil
	slot.Reference.Value = nil
	slot.Button.Visible = false
	slot.Button.Image = ""
	slot.Selected.Visible = false
	slot.Fallback.Visible = false
end

local function Portrait(slot: Slot, target: Model)
	local player = Players:GetPlayerFromCharacter(target)
	local image = target:GetAttribute("Portrait")
	slot.Fallback.Text = string.sub(Name(target), 1, 2)
	slot.Fallback.Visible = player ~= nil
	slot.Button.BackgroundColor3 = Color3.fromRGB(27, 39, 54)
	if typeof(image) == "string" and image ~= "" then
		slot.Button.Image = image
		slot.Fallback.Visible = false
	elseif player and player.UserId > 0 then
		local id = player.UserId
		local cached = Portraits[id]
		if cached then
			slot.Button.Image = cached
			slot.Fallback.Visible = false
		elseif not Pending[id] and (Attempts[id] or 0) < 3 and os.clock() >= (RetryAt[id] or 0) then
			Pending[id] = true
			Attempts[id] = (Attempts[id] or 0) + 1
			task.spawn(function()
				local ok, content, ready = pcall(function()
					return Players:GetUserThumbnailAsync(
						id,
						Enum.ThumbnailType.HeadShot,
						Enum.ThumbnailSize.Size150x150
					)
				end)
				Pending[id] = nil
				RetryAt[id] = os.clock() + 2
				if ok and ready then
					Portraits[id] = content
					for _, candidate in Targeting.Slots do
						local assigned = candidate.Target
						if assigned and Players:GetPlayerFromCharacter(assigned) == player then
							candidate.Button.Image = content
							candidate.Fallback.Visible = false
						end
					end
				end
			end)
		end
	elseif not player then
		local head = target:FindFirstChild("Head")
		local face = head and head:FindFirstChildWhichIsA("Decal")
		slot.Button.Image = if face then face.Texture else slot.DefaultImage
		if head and head:IsA("BasePart") then
			slot.Button.BackgroundColor3 = head.Color
		end
	end
end

local function Layout()
	local gui, panel = Targeting.Gui, Targeting.Panel
	if not gui or not panel then
		return
	end
	local controls = gui:FindFirstChild("Controls")
	if not controls or not controls:IsA("GuiObject") then
		return
	end
	local size = gui.AbsoluteSize
	local right = controls.AbsolutePosition.X - gui.AbsolutePosition.X - 12
	panel.Position = UDim2.fromOffset(math.max(12, right - panel.AbsoluteSize.X), math.max(0, size.Y - 146))
end

local function Refresh()
	local panel, title, marker = Targeting.Panel, Targeting.Title, Targeting.Marker
	if not panel or not title or not marker then
		return
	end
	local target = Targeting.Target
	if Targeting.Selection then
		Targeting.Selection.Value = target
	end
	local head = target and target:FindFirstChild("Head")
	marker.Adornee = if head and head:IsA("BasePart") then head else nil
	marker.Enabled = marker.Adornee ~= nil
	title.Text = if target then Name(target) .. " / LOCKED" else "CHOOSE TARGET"
	title.TextColor3 = if target then SELECTED_COLOR else Color3.fromRGB(217, 225, 234)
	local count = 0
	for _, slot in Targeting.Slots do
		local assigned = slot.Target
		if not assigned then
			continue
		end
		count += 1
		if slot.Button.Image == "" then
			Portrait(slot, assigned)
		end
		local selected = assigned == target
		slot.Stroke.Color = if selected then SELECTED_COLOR else ENEMY_COLOR
		slot.Stroke.Thickness = if selected then 3 else 1.5
		slot.Selected.Visible = selected
		local humanoid = assigned:FindFirstChildOfClass("Humanoid")
		slot.Fill.Size = UDim2.fromScale(
			if humanoid then math.clamp(humanoid.Health / math.max(1, humanoid.MaxHealth), 0, 1) else 0,
			1
		)
	end
	panel.Visible = count > 0
	Layout()
end

function Targeting:Clear()
	self.Target = nil
	Refresh()
end

function Targeting:Select(target: Model)
	if target == self.Target then
		self:Clear()
	elseif Available() and Eligible(target, AcquireRange()) then
		self.Target = target
		Refresh()
	end
end

function Targeting:Direction(): Vector3?
	local target = self.Target
	if not target then
		return nil
	end
	local direction = if Available() then Eligible(target, AcquireRange() + 4) else nil
	if not direction then
		self:Clear()
	end
	return direction
end

function Targeting:Step(dt: number)
	self.Elapsed += dt
	if self.Elapsed < INTERVAL then
		return
	end
	self.Elapsed %= INTERVAL
	if not Available() then
		for _, slot in self.Slots do
			Release(slot)
		end
		self:Clear()
		return
	end
	self:Direction()
	local candidates: { { Target: Model, Distance: number } } = {}
	local assigned: { [Model]: boolean } = {}
	for _, slot in self.Slots do
		local target = slot.Target
		if target and Eligible(target, AcquireRange() + (if target == self.Target then 4 else 0)) then
			assigned[target] = true
		else
			Release(slot)
		end
	end
	for _, instance in CollectionService:GetTagged("Combatant") do
		if instance:IsA("Model") and not assigned[instance] then
			local direction, distance = Eligible(instance, AcquireRange())
			if direction then
				table.insert(candidates, { Target = instance, Distance = distance })
			end
		end
	end
	table.sort(candidates, function(left, right)
		return if left.Distance == right.Distance
			then left.Target.Name < right.Target.Name
			else left.Distance < right.Distance
	end)
	for _, candidate in candidates do
		for _, slot in self.Slots do
			if not slot.Target then
				slot.Target = candidate.Target
				slot.Reference.Value = candidate.Target
				slot.Button.Visible = true
				Portrait(slot, candidate.Target)
				break
			end
		end
	end
	Refresh()
end

function Targeting:Init()
	if self.Gui then
		return
	end
	local gui = Player:WaitForChild("PlayerGui"):WaitForChild("CombatControls") :: ScreenGui
	local panel = gui:WaitForChild("Targets") :: Frame
	self.Gui = gui
	self.Panel = panel
	self.Title = panel:WaitForChild("Title") :: TextLabel
	self.Selection = panel:WaitForChild("Selection") :: ObjectValue
	self.Marker = gui:WaitForChild("TargetMarker") :: BillboardGui
	for index = 1, CAPACITY do
		local button = panel:WaitForChild(tostring(index)) :: ImageButton
		local slot: Slot = {
			Button = button,
			Reference = button:WaitForChild("Target") :: ObjectValue,
			Stroke = button:WaitForChild("Stroke") :: UIStroke,
			Fill = button:WaitForChild("Health"):WaitForChild("Fill") :: Frame,
			Selected = button:WaitForChild("Selected") :: TextLabel,
			Fallback = button:WaitForChild("Fallback") :: TextLabel,
			DefaultImage = button.Image,
			Target = nil,
		}
		table.insert(self.Slots, slot)
		Release(slot)
		button.Activated:Connect(function()
			if slot.Target then
				self:Select(slot.Target)
			end
		end)
	end
	Player.CharacterRemoving:Connect(function()
		for _, slot in self.Slots do
			Release(slot)
		end
		self:Clear()
	end)
	Players.PlayerRemoving:Connect(function(player)
		Portraits[player.UserId] = nil
		Attempts[player.UserId] = nil
		RetryAt[player.UserId] = nil
	end)
	self:Clear()
end

return Targeting

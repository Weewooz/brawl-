--!strict
local Config = require(game:GetService("ReplicatedStorage").Shared.Combat.Config)
local Weapons = require(game:GetService("ReplicatedStorage").Shared.Combat.Weapons)

type Slot = {
	Button: TextButton,
	Icon: GuiObject,
	Artwork: { ImageLabel },
	Title: TextLabel,
	Cost: TextLabel,
	Ring: { Frame },
	Color: Color3,
	Stroke: UIStroke?,
}

export type System = {
	Slots: { [string]: Slot },
	Bind: (self: System, buttons: { [string]: TextButton }) -> (),
	Update: (self: System, name: string, ready: boolean, remaining: number, active: boolean) -> (),
	Weapon: (self: System, id: string) -> (),
}

local Controls: System = { Slots = {} } :: System
local COLORS = { Ready = Color3.fromRGB(232, 205, 150), Waiting = Color3.fromRGB(127, 113, 97) }
local DURATIONS = {
	Attack = Config.Attack.Cooldown,
	Dash = Config.DashCooldown,
}
local COSTS = {
	Attack = "",
	Dash = tostring(Config.Stamina.Dash),
	Block = tostring(Config.Stamina.BlockPerSecond) .. "/s",
	Sprint = tostring(Config.Stamina.SprintPerSecond) .. "/s",
}

function Controls:Weapon(id: string)
	local definition = Weapons.Get(id)
	if not definition then
		return
	end
	for name, slot in self.Slots do
		local skill = definition.Skills[name]
		if name == "Attack" then
			DURATIONS[name] = definition.Attack.Cooldown
			slot.Title.Text = if definition.IsRanged then "DRAW" else "SLASH"
			slot.Cost.Text = if definition.Attack.Stamina > 0 then tostring(definition.Attack.Stamina) else ""
		elseif skill then
			DURATIONS[name] = skill.Cooldown
			slot.Title.Text = string.upper(skill.Name)
			slot.Cost.Text = tostring(skill.Stamina)
		end
		-- Melee artwork must not misrepresent the ranged actions.
		slot.Icon.Visible = not definition.IsRanged or (name ~= "Attack" and skill == nil)
	end
end

function Controls:Bind(buttons: { [string]: TextButton })
	for name, button in buttons do
		local ring: { Frame } = {}
		local folder = button:WaitForChild("CooldownRing")
		for index = 1, 32 do
			table.insert(ring, folder:WaitForChild(tostring(index)) :: Frame)
		end
		local cost = button:WaitForChild("Cost") :: TextLabel
		cost.Text = COSTS[name] or ""
		local container = button:FindFirstChild("Container")
		local icon = (if container then container:WaitForChild("Icon") else button:WaitForChild("Icon")) :: GuiObject
		local artwork: { ImageLabel } = {}
		if icon:IsA("ImageLabel") then
			table.insert(artwork, icon)
		end
		for _, image in icon:GetDescendants() do
			if image:IsA("ImageLabel") then
				table.insert(artwork, image)
			end
		end
		self.Slots[name] = {
			Button = button,
			Icon = icon,
			Artwork = artwork,
			Title = button:WaitForChild("Title") :: TextLabel,
			Cost = cost,
			Ring = ring,
			Color = button.BackgroundColor3,
			Stroke = button:FindFirstChildOfClass("UIStroke"),
		}
	end
	self:Weapon("Katana")
end

function Controls:Update(name: string, ready: boolean, remaining: number, active: boolean)
	local slot = self.Slots[name]
	if not slot then
		return
	end
	slot.Button.BackgroundColor3 = if active then slot.Color:Lerp(COLORS.Ready, 0.2) else slot.Color
	for _, image in slot.Artwork do
		image.ImageTransparency = if ready or active then 0 else 0.62
	end
	slot.Title.TextColor3 = if ready or active then COLORS.Ready else COLORS.Waiting
	slot.Cost.TextColor3 = if ready then COLORS.Ready else COLORS.Waiting
	if slot.Stroke then
		slot.Stroke.Color = if active
			then Color3.fromRGB(255, 226, 154)
			elseif ready then COLORS.Ready
			else COLORS.Waiting
	end
	local duration = DURATIONS[name] or 1
	local segments = math.ceil(math.clamp(remaining / duration, 0, 1) * #slot.Ring)
	for index, segment in slot.Ring do
		segment.Visible = remaining > 0 and index <= segments
	end
end

return Controls

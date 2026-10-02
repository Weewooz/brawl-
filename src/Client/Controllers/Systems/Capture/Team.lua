--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Client = require(ReplicatedStorage.Shared.Network.Client)
local Player = Players.LocalPlayer

type Slot = { Frame: Frame, Portrait: ImageLabel, Name: TextLabel, State: TextLabel, Fill: Frame }
type Ping = { Part: BasePart, Gui: BillboardGui, Icon: TextLabel, Until: number }
type Member = {
	Name: string,
	Character: Model?,
	Player: Player?,
	RespawnAt: number,
	Key: string,
	Health: number?,
	MaxHealth: number?,
}
type Entry = { Source: string, Skill: string, Damage: number, Effect: string }
export type View = {
	Gui: ScreenGui,
	Strip: Frame,
	Pings: Frame,
	Recap: Frame,
	Title: TextLabel,
	Rows: { TextLabel },
	Slots: { Slot },
	Markers: { Ping },
	Home: Instance,
	Entries: { Entry },
	RequestAt: number,
	Ping: (self: View, kind: string) -> (),
	Step: (self: View, now: number, active: boolean, team: string) -> (),
}

local Team = {}
Team.__index = Team
local Portraits: { [number]: string } = {}
local Loading: { [number]: boolean } = {}
local SYMBOLS: { [string]: string } = { Attack = "ATTACK", Defend = "DEFEND", Regroup = "REGROUP" }
local COLORS: { [string]: Color3 } = {
	Attack = Color3.fromRGB(255, 166, 109),
	Defend = Color3.fromRGB(125, 215, 246),
	Regroup = Color3.fromRGB(241, 220, 156),
}

local function Number(instance: Instance, attribute: string): number
	local value = instance:GetAttribute(attribute)
	return if typeof(value) == "number" then value else 0
end

local function Portrait(player: Player): string
	local id = player.UserId
	if not Portraits[id] and not Loading[id] then
		Loading[id] = true
		task.spawn(function()
			local ok, url = pcall(function()
				return Players:GetUserThumbnailAsync(id, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
			end)
			Portraits[id] = if ok then url else ""
			Loading[id] = nil
		end)
	end
	return Portraits[id] or ""
end

local function Release(view: View, marker: Ping)
	marker.Until = 0
	marker.Gui.Enabled = false
	marker.Part.Parent = view.Home
end

local function ReceivePing(view: View, kind: string, position: Vector3, sender: string, untilAt: number)
	if not SYMBOLS[kind] or untilAt <= Workspace:GetServerTimeNow() then
		return
	end
	local chosen = view.Markers[1]
	for _, marker in view.Markers do
		if marker.Until <= Workspace:GetServerTimeNow() then
			chosen = marker
			break
		elseif chosen and marker.Until < chosen.Until then
			chosen = marker
		end
	end
	if not chosen then
		return
	end
	chosen.Part.Position = position + Vector3.yAxis * 1.5
	chosen.Part.Parent = Workspace
	chosen.Gui.Adornee = chosen.Part
	chosen.Gui.Enabled = true
	chosen.Icon.Text = SYMBOLS[kind] .. "\n" .. sender
	chosen.Icon.TextColor3 = COLORS[kind]
	chosen.Until = untilAt
end

function Team.new(gui: ScreenGui): View
	local strip = gui:WaitForChild("TeamStrip") :: Frame
	local recap = gui:WaitForChild("Recap") :: Frame
	local home = ReplicatedStorage.Assets:WaitForChild("PingMarkerPool")
	local self: View = setmetatable({
		Gui = gui,
		Strip = strip,
		Pings = gui:WaitForChild("Pings") :: Frame,
		Recap = recap,
		Title = recap:WaitForChild("Title") :: TextLabel,
		Rows = {},
		Slots = {},
		Markers = {},
		Home = home,
		Entries = {},
		RequestAt = 0,
	}, Team) :: View
	for index = 1, 5 do
		local frame = strip:WaitForChild(tostring(index)) :: Frame
		table.insert(self.Slots, {
			Frame = frame,
			Portrait = frame:WaitForChild("Portrait") :: ImageLabel,
			Name = frame:WaitForChild("Name") :: TextLabel,
			State = frame:WaitForChild("State") :: TextLabel,
			Fill = frame:WaitForChild("Track"):WaitForChild("Fill") :: Frame,
		})
	end
	for index = 1, 4 do
		table.insert(self.Rows, recap:WaitForChild(tostring(index)) :: TextLabel)
	end
	for _, instance in home:GetChildren() do
		if instance:IsA("BasePart") then
			local marker: Ping = {
				Part = instance,
				Gui = instance:WaitForChild("BillboardGui") :: BillboardGui,
				Icon = instance:WaitForChild("BillboardGui"):WaitForChild("Icon") :: TextLabel,
				Until = 0,
			}
			Release(self, marker)
			table.insert(self.Markers, marker)
		end
	end
	for kind in SYMBOLS do
		local button = self.Pings:WaitForChild(kind) :: TextButton
		button.Activated:Connect(function()
			self:Ping(kind)
		end)
	end
	Client.Capture.Pinged.On(function(kind, position, sender, untilAt)
		ReceivePing(self, kind, position, sender, untilAt)
	end)
	Client.Combat.DeathRecap.On(function(data)
		table.clear(self.Entries)
		if typeof(data) ~= "table" then
			return
		end
		for _, entry in data do
			if #self.Entries >= 4 then
				break
			end
			if
				typeof(entry) == "table"
				and typeof(entry.Source) == "string"
				and typeof(entry.Skill) == "string"
				and typeof(entry.Damage) == "number"
				and typeof(entry.Effect) == "string"
			then
				table.insert(self.Entries, entry)
			end
		end
	end)
	Player.CharacterAdded:Connect(function()
		table.clear(self.Entries)
	end)
	return self
end

function Team:Ping(kind: string)
	local self: View = self
	local now = Workspace:GetServerTimeNow()
	if now < self.RequestAt then
		return
	end
	local character = Player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local arena = Workspace:FindFirstChild("CaptureArena")
	local point = arena and arena:FindFirstChild("Point")
	local source = if kind == "Regroup" then root else point
	if source and source:IsA("BasePart") then
		self.RequestAt = now + 1.5
		Client.Capture.Ping.Fire(kind, source.Position)
	end
end

function Team:Step(now: number, active: boolean, team: string)
	local self: View = self
	self.Strip.Visible = active
	local character = Player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local alive = humanoid ~= nil and humanoid.Health > 0
	local capture = ReplicatedStorage:FindFirstChild("CaptureState")
	local phase = capture and capture:GetAttribute("Phase")
	self.Pings.Visible = active and alive and (phase == "Active" or phase == "Overtime")
	self.Recap.Visible = #self.Entries > 0 and not alive
	self.Title.Text = "LAST HITS / 12 SECONDS"
	for index, row in self.Rows do
		local entry = self.Entries[index]
		row.Visible = entry ~= nil
		if entry then
			row.Text = string.format(
				"%s  •  %s  %.1f%s",
				entry.Source,
				entry.Skill,
				entry.Damage,
				if entry.Effect ~= "" then " / " .. entry.Effect else ""
			)
		end
	end
	for _, marker in self.Markers do
		if marker.Until > 0 and (not active or marker.Until <= now) then
			Release(self, marker)
		end
	end
	if not active then
		return
	end
	local members: { Member } = {}
	for _, member in Players:GetPlayers() do
		if member:GetAttribute("CaptureStatus") == "Playing" and member:GetAttribute("CaptureTeam") == team then
			table.insert(members, {
				Name = member.DisplayName,
				Character = member.Character,
				Player = member,
				RespawnAt = Number(member, "CaptureRespawnAt"),
				Key = "0" .. string.format("%012d", member.UserId),
			})
		end
	end
	local state = ReplicatedStorage:FindFirstChild("CaptureState")
	if state then
		for index = 1, 5 do
			local prefix = team .. "Bot" .. index
			local name = state:GetAttribute(prefix .. "Name")
			if typeof(name) == "string" and name ~= "" then
				table.insert(members, {
					Name = name,
					Character = nil,
					Player = nil,
					RespawnAt = Number(state, prefix .. "RespawnAt"),
					Key = "1" .. index,
					Health = Number(state, prefix .. "Health"),
					MaxHealth = Number(state, prefix .. "MaxHealth"),
				})
			end
		end
	end
	table.sort(members, function(left, right)
		return left.Key < right.Key
	end)
	for index, slot in self.Slots do
		local member = members[index]
		slot.Frame.Visible = member ~= nil
		if not member then
			continue
		end
		local model = member.Character
		local health = model and model:FindFirstChildOfClass("Humanoid")
		local living = health ~= nil
			and health.Health > 0
			and model ~= nil
			and model:GetAttribute("CaptureActive") ~= false
		local amount = if health then health.Health else member.Health or 0
		local maximum = if health then health.MaxHealth else member.MaxHealth or 100
		if member.Health ~= nil then
			living = member.Health > 0 and member.RespawnAt <= now
		end
		slot.Name.Text = member.Name
		local botPortrait = slot.Portrait:GetAttribute("BotPortrait")
		slot.Portrait.Image = if member.Player
			then Portrait(member.Player)
			elseif typeof(botPortrait) == "string" then botPortrait
			else ""
		slot.Portrait.ImageTransparency = if living then 0 else 0.65
		slot.State.Text = if member.RespawnAt > now
			then tostring(math.ceil(member.RespawnAt - now)) .. "s"
			elseif living then ""
			else "DOWN"
		slot.Fill.Size = UDim2.fromScale(if living then math.clamp(amount / math.max(1, maximum), 0, 1) else 0, 1)
	end
end

return Team

--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Client = require(ReplicatedStorage.Shared.Network.Client)
local AudioUtilities = require(ReplicatedStorage.Shared.Utilities.AudioUtilities)
local Rules = require(ReplicatedStorage.Shared.Capture.Rules)
local TeamHUD = require(script.Team)

export type System = {
	Init: (self: System) -> (),
	Start: (self: System) -> (),
}

type Marker = {
	Gui: BillboardGui,
	Home: Instance,
	Label: TextLabel,
	Fill: Frame,
	Player: Player?,
}

type View = {
	Gui: ScreenGui,
	Score: Frame,
	Azure: TextLabel,
	Coral: TextLabel,
	Timer: TextLabel,
	Phase: TextLabel,
	Objective: Frame,
	Title: TextLabel,
	Detail: TextLabel,
	Fill: Frame,
	Lobby: Frame,
	LobbyTitle: TextLabel,
	Description: TextLabel,
	Play: TextButton,
	Practice: TextButton,
	ExitPractice: TextButton?,
	Result: Frame,
	ResultTitle: TextLabel,
	ResultDetail: TextLabel,
	Replay: TextButton,
	Leave: TextButton,
	Respawn: Frame,
	RespawnTitle: TextLabel,
	Countdown: TextLabel,
	Team: TextLabel,
	Feedback: TextLabel,
	Direction: TextLabel,
}

local System = {} :: System
local Player = Players.LocalPlayer
local COLORS = {
	Azure = Color3.fromRGB(77, 193, 255),
	Coral = Color3.fromRGB(255, 115, 109),
	Neutral = Color3.fromRGB(155, 168, 185),
	Contested = Color3.fromRGB(255, 215, 110),
}
local INTERVAL = 0.1
local State: Folder?
local View: View?
local Point: BasePart?
local Rings: { BasePart } = {}
local Markers: { Marker } = {}
local Connections: { RBXScriptConnection } = {}
local LastPhase: string? = nil
local LastOwner: string? = nil
local LastRound = -1
local LastKills = 0
local LastAssists = 0
local FeedbackUntil = 0
local RequestAt = 0
local TeamView: TeamHUD.View? = nil

local function String(instance: Instance, name: string): string
	local value = instance:GetAttribute(name)
	return if typeof(value) == "string" then value else ""
end

local function Number(instance: Instance, name: string): number
	local value = instance:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

local function Color(team: string): Color3
	return if team == "Azure" then COLORS.Azure elseif team == "Coral" then COLORS.Coral else COLORS.Neutral
end

local function Clock(seconds: number): string
	local remaining = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", math.floor(remaining / 60), remaining % 60)
end

local function Cue(name: string)
	local character = Player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		AudioUtilities.PlayAtPart(name, root, 0.65)
	end
end

local function Feedback(text: string, color: Color3, now: number)
	local view = View
	if view then
		view.Feedback.Text = text
		view.Feedback.TextColor3 = color
		FeedbackUntil = now + 2.5
	end
end

local function Release(marker: Marker)
	marker.Player = nil
	marker.Gui.Enabled = false
	marker.Gui.Adornee = nil
	marker.Gui.Parent = marker.Home
end

local function SyncMarkers(active: boolean, team: string)
	local view = View
	if not view then
		return
	end
	local eligible: { [Player]: BasePart } = {}
	if active then
		for _, player in Players:GetPlayers() do
			if player == Player or String(player, "CaptureStatus") ~= "Playing" then
				continue
			end
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local head = character and character:FindFirstChild("Head")
			if humanoid and humanoid.Health > 0 and head and head:IsA("BasePart") then
				eligible[player] = head
			end
		end
	end
	local assigned: { [Player]: boolean } = {}
	for _, marker in Markers do
		local player = marker.Player
		if player and eligible[player] then
			assigned[player] = true
		else
			Release(marker)
		end
	end
	for player in eligible do
		if not assigned[player] then
			for _, marker in Markers do
				if not marker.Player then
					marker.Player = player
					break
				end
			end
		end
	end
	for _, marker in Markers do
		local player = marker.Player
		if not player then
			continue
		end
		local head = eligible[player]
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not head or not humanoid then
			Release(marker)
			continue
		end
		local playerTeam = String(player, "CaptureTeam")
		local allied = playerTeam == team
		marker.Gui.Adornee = head
		marker.Gui.Parent = view.Gui.Parent
		marker.Gui.Enabled = true
		marker.Label.Text = (if allied then "ALLY  " else "ENEMY  ") .. player.DisplayName
		marker.Label.TextColor3 = Color(playerTeam)
		marker.Fill.BackgroundColor3 = Color(playerTeam)
		marker.Fill.Size = UDim2.fromScale(math.clamp(humanoid.Health / math.max(1, humanoid.MaxHealth), 0, 1), 1)
	end
end

local function SyncWorld(owner: string, captureTeam: string, progress: number, contested: boolean)
	local ownerColor = Color(owner)
	if Point then
		Point.Color = if contested then COLORS.Contested else ownerColor
	end
	local filled = math.floor(progress * #Rings + 0.5)
	for index, ring in Rings do
		local capturing = captureTeam ~= "" and index <= filled
		ring.Color = if capturing then Color(captureTeam) else COLORS.Neutral
		ring.Transparency = if capturing then 0.1 else 0.55
	end
end

local function PlaceDirection(
	view: View,
	position: Vector2,
	half: Vector2,
	minimum: Vector2,
	maximum: Vector2
): Vector2?
	local obstacles: { { Min: Vector2, Max: Vector2 } } = {}
	local horizontal = { position.X }
	local vertical = { position.Y }
	local function reserve(gui: GuiObject)
		if not gui.Visible then
			return
		end
		local origin = gui.AbsolutePosition - view.Gui.AbsolutePosition
		local padding = half + Vector2.new(12, 12)
		local bounds = { Min = origin - padding, Max = origin + gui.AbsoluteSize + padding }
		table.insert(obstacles, bounds)
		table.insert(horizontal, bounds.Min.X)
		table.insert(horizontal, bounds.Max.X)
		table.insert(vertical, bounds.Min.Y)
		table.insert(vertical, bounds.Max.Y)
	end
	reserve(view.Score)
	reserve(view.Objective)
	reserve(view.Feedback)
	if TeamView then
		reserve(TeamView.Strip)
		reserve(TeamView.Pings)
	end
	if view.ExitPractice then
		reserve(view.ExitPractice)
	end
	local combat = view.Gui.Parent:FindFirstChild("CombatControls")
	local controls = combat and combat:FindFirstChild("Controls")
	if combat and combat:IsA("ScreenGui") and combat.Enabled and controls and controls:IsA("GuiObject") then
		reserve(controls)
		local targets = combat:FindFirstChild("Targets")
		if targets and targets:IsA("GuiObject") then
			reserve(targets)
		end
	end
	local best: Vector2? = nil
	local distance = math.huge
	for _, x in horizontal do
		for _, y in vertical do
			if x < minimum.X or x > maximum.X or y < minimum.Y or y > maximum.Y then
				continue
			end
			local blocked = false
			for _, bounds in obstacles do
				if x > bounds.Min.X and x < bounds.Max.X and y > bounds.Min.Y and y < bounds.Max.Y then
					blocked = true
					break
				end
			end
			local candidate = Vector2.new(x, y)
			local offset = (candidate - position).Magnitude
			if not blocked and offset < distance then
				best = candidate
				distance = offset
			end
		end
	end
	return best
end

local function SyncDirection(active: boolean, owner: string, contested: boolean)
	local view = View
	if not view then
		return
	end
	local camera = Workspace.CurrentCamera
	local character = Player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local point = Point
	if
		not active
		or not camera
		or not root
		or not root:IsA("BasePart")
		or not humanoid
		or humanoid.Health <= 0
		or not point
	then
		view.Direction.Visible = false
		return
	end
	local distance = (root.Position - point.Position).Magnitude
	local projected, onScreen = camera:WorldToViewportPoint(point.Position)
	view.Direction.Visible = not onScreen or distance > 25
	if not view.Direction.Visible then
		return
	end
	local size = view.Gui.AbsoluteSize
	local position = Vector2.new(projected.X, projected.Y) - view.Gui.AbsolutePosition
	if projected.Z < 0 then
		position = size - position
	end
	local half = view.Direction.AbsoluteSize * 0.5
	local left = math.min(half.X + 12, size.X * 0.5)
	local top = math.max(half.Y + 12, math.min(150, size.Y * 0.3))
	local bottom = math.max(top, size.Y - math.min(180, size.Y * 0.36) - half.Y)
	local minimum = Vector2.new(left, top)
	local maximum = Vector2.new(math.max(left, size.X - left), bottom)
	local clamped =
		Vector2.new(math.clamp(position.X, left, math.max(left, size.X - left)), math.clamp(position.Y, top, bottom))
	local clear = PlaceDirection(view, clamped, half, minimum, maximum)
	if not clear then
		view.Direction.Visible = false
		return
	end
	view.Direction.Position = UDim2.fromOffset(clear.X, clear.Y)
	view.Direction.Text = "POINT " .. tostring(math.ceil(distance))
	view.Direction.TextColor3 = if contested then COLORS.Contested else Color(owner)
end

local function Sync(now: number)
	local state = State
	local view = View
	if not state or not view then
		return
	end
	local phase = String(state, "Phase")
	local status = String(Player, "CaptureStatus")
	local team = String(Player, "CaptureTeam")
	local owner = String(state, "Owner")
	local captureTeam = String(state, "CaptureTeam")
	local progress = math.clamp(Number(state, "CaptureProgress"), 0, 1)
	local contested = state:GetAttribute("Contested") == true
	local participating = status == "Playing"
	local queued = status == "Queued"
	local practicing = status == "Practice"
	local result = participating and phase == "Results"
	local active = participating and (phase == "Active" or phase == "Overtime" or phase == "Countdown")
	local round = Number(state, "Round")
	local kills = Number(Player, "CaptureKills")
	local assists = Number(Player, "CaptureAssists")
	local respawnAt = Number(Player, "CaptureRespawnAt")
	local message = String(state, "Message")
	local playerMessage = String(Player, "CaptureMessage")
	local newRound = LastRound ~= round

	view.Gui.Enabled = true
	view.Score.Visible = participating or queued
	view.Objective.Visible = active
	view.Lobby.Visible = not participating and not practicing
	view.Practice.Visible = practicing
	if view.ExitPractice then
		view.ExitPractice.Visible = state:GetAttribute("PracticeBots") == true and (participating or queued)
		view.ExitPractice.Text = "LEAVE PRACTICE"
	end
	view.Result.Visible = result
	view.Respawn.Visible = active and respawnAt > now
	view.Team.Visible = participating and team ~= ""
	view.Team.Text = string.upper(team) .. " TEAM"
	view.Team.TextColor3 = Color(team)
	view.Azure.Text = tostring(Number(state, "AzureScore"))
	view.Coral.Text = tostring(Number(state, "CoralScore"))
	view.Timer.Text = if phase == "Overtime" then "OVERTIME" else Clock(Number(state, "EndsAt") - now)
	view.Phase.Text = if phase == "Waiting"
		then "WAITING FOR OPPONENTS"
		elseif phase == "Countdown" then "GET READY"
		elseif phase == "Results" then "ROUND COMPLETE"
		else "CONTROL / FIRST TO " .. tostring(Rules.TargetScore)
	view.LobbyTitle.Text = if queued then "YOU'RE IN THE QUEUE" else "CAPTURE POINT"
	view.Description.Text = if playerMessage ~= ""
		then playerMessage
		elseif queued and message ~= "" then message
		elseif queued then "Waiting for opponents. The round starts when both teams are ready."
		else string.format("5 vs 5. Hold the point to score. First team to %d wins.", Rules.TargetScore)
	view.Play.Text = if queued then "LEAVE QUEUE" else "PLAY CAPTURE"
	view.RespawnTitle.Text = "BACK IN THE FIGHT"
	view.Countdown.Text = tostring(math.max(0, math.ceil(respawnAt - now)))
	view.Fill.Size = UDim2.fromScale(progress, 1)
	view.Fill.BackgroundColor3 = if contested then COLORS.Contested else Color(captureTeam)
	view.Title.TextColor3 = if contested then COLORS.Contested else Color(owner)
	if phase == "Countdown" then
		view.Title.Text = "ROUND STARTS IN " .. tostring(math.max(0, math.ceil(Number(state, "EndsAt") - now)))
		view.Detail.Text = "Reach the marked point. Stay together."
	elseif contested then
		view.Title.Text = "POINT CONTESTED"
		view.Detail.Text = "Clear enemies from the ring to score."
	elseif owner ~= "" and progress < 1 then
		view.Title.Text = if owner == team then "POINT UNDER ATTACK" else "NEUTRALIZING ENEMY POINT"
		view.Detail.Text = if owner == team
			then "Return to the ring to defend."
			else "Stay inside to remove enemy control."
	elseif owner == "" and captureTeam ~= "" and progress > 0 then
		view.Title.Text = if captureTeam == team then "CAPTURING POINT" else "ENEMY CAPTURING"
		view.Detail.Text = string.format(
			"%d%%  |  %s",
			math.floor(progress * 100),
			if captureTeam == team then "Stay inside the ring." else "Enter the ring to contest."
		)
	elseif owner ~= "" then
		view.Title.Text = if owner == team then "YOUR TEAM CONTROLS THE POINT" else "ENEMY CONTROLS THE POINT"
		view.Detail.Text = if owner == team
			then "Defend the point to keep scoring."
			else "Enter the ring to stop enemy scoring."
	else
		view.Title.Text = "CAPTURE THE POINT"
		view.Detail.Text = "Stand inside the ring to take control."
	end
	local character = Player.Character
	local protectedUntil = if character then Number(character, "CaptureProtectedUntil") else 0
	if active and protectedUntil > now then
		view.Detail.Text = string.format("PROTECTED %ds  |  Attacks locked", math.ceil(protectedUntil - now))
	end

	if result then
		local winner = String(state, "Winner")
		view.ResultTitle.Text = if winner == "" or winner == "Draw"
			then "DRAW"
			elseif winner == team then "VICTORY"
			else "DEFEAT"
		view.ResultTitle.TextColor3 = Color(winner)
		view.ResultDetail.Text = string.format(
			"%d eliminations  |  %d assists\n%d seconds on the objective",
			kills,
			assists,
			math.floor(Number(Player, "CaptureObjective"))
		)
		view.Replay.Text = string.format("NEXT ROUND IN %d", math.max(0, math.ceil(Number(state, "EndsAt") - now)))
	end
	if not newRound and LastPhase ~= nil then
		if result and LastPhase ~= "Results" then
			local winner = String(state, "Winner")
			if winner == "Azure" or winner == "Coral" then
				Cue(if winner == team then "VictoryCue" else "DefeatCue")
			end
		elseif active and owner ~= "" and LastOwner ~= owner then
			Feedback(if owner == team then "POINT SECURED" else "POINT LOST", Color(owner), now)
			Cue("CaptureCue")
		elseif active and kills > LastKills then
			Feedback("ELIMINATION", Color(team), now)
		elseif active and assists > LastAssists then
			Feedback("ASSIST", Color(team), now)
		end
	end
	if newRound or not active then
		FeedbackUntil = 0
	end
	view.Feedback.Visible = active and now < FeedbackUntil
	LastPhase = phase
	LastOwner = owner
	LastRound = round
	LastKills = kills
	LastAssists = assists
	SyncWorld(owner, captureTeam, progress, contested)
	if TeamView then
		TeamView:Step(now, active, team)
	end
	SyncMarkers(active, team)
	SyncDirection(participating and (phase == "Active" or phase == "Overtime"), owner, contested)
end

local function Request(join: boolean)
	local now = os.clock()
	if now < RequestAt then
		return
	end
	RequestAt = now + 0.5
	Client.Capture.Request.Fire(join)
end

function System:Init() end

function System:Start()
	if View then
		return
	end
	local playerGui = Player:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("CaptureHUD") :: ScreenGui
	TeamView = TeamHUD.new(gui)
	local score = gui:WaitForChild("Score") :: Frame
	local objective = gui:WaitForChild("Objective") :: Frame
	local lobby = gui:WaitForChild("Lobby") :: Frame
	local result = gui:WaitForChild("Result") :: Frame
	local respawn = gui:WaitForChild("Respawn") :: Frame
	View = {
		Gui = gui,
		Score = score,
		Azure = score:WaitForChild("Azure") :: TextLabel,
		Coral = score:WaitForChild("Coral") :: TextLabel,
		Timer = score:WaitForChild("Timer") :: TextLabel,
		Phase = score:WaitForChild("Phase") :: TextLabel,
		Objective = objective,
		Title = objective:WaitForChild("Title") :: TextLabel,
		Detail = objective:WaitForChild("Detail") :: TextLabel,
		Fill = objective:WaitForChild("Track"):WaitForChild("Fill") :: Frame,
		Lobby = lobby,
		LobbyTitle = lobby:WaitForChild("Title") :: TextLabel,
		Description = lobby:WaitForChild("Description") :: TextLabel,
		Play = lobby:WaitForChild("Play") :: TextButton,
		Practice = gui:WaitForChild("Practice") :: TextButton,
		ExitPractice = gui:FindFirstChild("ExitPractice") :: TextButton?,
		Result = result,
		ResultTitle = result:WaitForChild("Title") :: TextLabel,
		ResultDetail = result:WaitForChild("Detail") :: TextLabel,
		Replay = result:WaitForChild("Play") :: TextButton,
		Leave = result:WaitForChild("Leave") :: TextButton,
		Respawn = respawn,
		RespawnTitle = respawn:WaitForChild("Title") :: TextLabel,
		Countdown = respawn:WaitForChild("Countdown") :: TextLabel,
		Team = gui:WaitForChild("Team") :: TextLabel,
		Feedback = gui:WaitForChild("Feedback") :: TextLabel,
		Direction = gui:WaitForChild("Direction") :: TextLabel,
	}
	State = ReplicatedStorage:WaitForChild("CaptureState") :: Folder
	local arena = Workspace:WaitForChild("CaptureArena")
	Point = arena:WaitForChild("Point") :: BasePart
	for _, instance in arena:WaitForChild("Rings"):GetChildren() do
		if instance:IsA("BasePart") then
			table.insert(Rings, instance)
		end
	end
	table.sort(Rings, function(left, right)
		return (tonumber(left.Name) or 0) < (tonumber(right.Name) or 0)
	end)
	local pool = ReplicatedStorage.Assets:WaitForChild("TeamMarkerPool")
	for _, instance in pool:GetChildren() do
		if instance:IsA("BillboardGui") then
			local marker: Marker = {
				Gui = instance,
				Home = pool,
				Label = instance:WaitForChild("Label") :: TextLabel,
				Fill = instance:WaitForChild("Health"):WaitForChild("Fill") :: Frame,
				Player = nil,
			}
			Release(marker)
			table.insert(Markers, marker)
		end
	end
	local view = View :: View
	if view.ExitPractice then
		table.insert(
			Connections,
			view.ExitPractice.Activated:Connect(function()
				Request(false)
			end)
		)
	end
	table.insert(
		Connections,
		view.Practice.Activated:Connect(function()
			Request(true)
		end)
	)
	table.insert(
		Connections,
		view.Play.Activated:Connect(function()
			Request(String(Player, "CaptureStatus") ~= "Queued")
		end)
	)
	table.insert(
		Connections,
		view.Replay.Activated:Connect(function()
			Request(true)
		end)
	)
	table.insert(
		Connections,
		view.Leave.Activated:Connect(function()
			Request(false)
		end)
	)
	local elapsed = 0
	table.insert(
		Connections,
		RunService.Heartbeat:Connect(function(deltaTime)
			elapsed += deltaTime
			if elapsed >= INTERVAL then
				elapsed %= INTERVAL
				Sync(Workspace:GetServerTimeNow())
			end
		end)
	)
	table.insert(
		Connections,
		script.Destroying:Connect(function()
			for _, connection in Connections do
				connection:Disconnect()
			end
			table.clear(Connections)
			for _, marker in Markers do
				Release(marker)
			end
		end)
	)
	Sync(Workspace:GetServerTimeNow())
end

return System

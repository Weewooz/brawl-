--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Teams = game:GetService("Teams")
local Workspace = game:GetService("Workspace")

local Rules = require(ReplicatedStorage.Shared.Capture.Rules)
local Server = require(ReplicatedStorage.Shared.Network.Server)
local Status = require(script.Parent.Combat.Status)
local Skills = require(script.Parent.Combat.Skills)
local Outcomes = require(script.Outcomes)
local Bots = require(script.Bots)

type Member = {
	Team: Rules.Team,
	Slot: number,
	Objective: number,
}
type Connections = {
	Character: RBXScriptConnection,
	Died: RBXScriptConnection?,
}
export type System = {
	Init: (self: System) -> (),
	Start: (self: System) -> (),
	Join: (self: System, player: Player) -> boolean,
	Leave: (self: System, player: Player) -> (),
	Step: (self: System, dt: number) -> (),
}

local System = {} :: System
local Members: { [Player]: Member } = {}
local ConnectionsByPlayer: { [Player]: Connections } = {}
local Requests: { [Player]: number } = {}
local RejoinAt: { [Player]: number } = {}
local State = Rules.New(0)
local Arena: Model
local Point: BasePart
local Lobby: BasePart
local PracticeSpawn: BasePart?
local Replicated: Folder
local Round = 0
local Ready = false
local Accumulator = 0
local UPDATE = 0.1

local function Active(): boolean
	return State.Phase == "Active" or State.Phase == "Overtime"
end

local function Counts(): (number, number)
	local azure, coral = 0, 0
	for _, member in Members do
		if member.Team == "Azure" then
			azure += 1
		else
			coral += 1
		end
	end
	return azure, coral
end

local function Practice(): boolean
	return Bots.Enabled() or (RunService:IsStudio() and Arena:GetAttribute("PracticeEnabled") == true)
end

local function Occupancy(): Bots.Occupancy
	local occupied: Bots.Occupancy = { Azure = {}, Coral = {} }
	for _, member in Members do
		occupied[member.Team][member.Slot] = true
	end
	return occupied
end

local function Enough(): boolean
	local azure, coral = Counts()
	return (azure > 0 and coral > 0) or (Practice() and azure + coral > 0)
end

local function Message(): string
	if State.Phase == "Waiting" then
		return "Join the queue • waiting for opponents"
	end
	if State.Phase == "Countdown" then
		return "Prepare to capture the point"
	end
	if State.Phase == "Results" then
		return if State.Winner == "Draw" then "Round drawn" else State.Winner .. " wins"
	end
	if State.Phase == "Overtime" then
		return "Overtime • keep the point contested"
	end
	if State.Contested then
		return "Point contested • eliminate opponents"
	end
	if State.Owner == "" then
		return "Stand on the point to capture"
	end
	return State.Owner .. " controls the point"
end

local function Publish()
	for _, key in
		{
			"Phase",
			"AzureScore",
			"CoralScore",
			"Owner",
			"CaptureTeam",
			"CaptureProgress",
			"Contested",
			"EndsAt",
			"Winner",
		}
	do
		local value = (State :: any)[key]
		if Replicated:GetAttribute(key) ~= value then
			Replicated:SetAttribute(key, value)
		end
	end
	local azure, coral = Counts()
	local azureBots, coralBots = Bots.Counts()
	Replicated:SetAttribute("AzurePlayers", azure + azureBots)
	Replicated:SetAttribute("CoralPlayers", coral + coralBots)
	Replicated:SetAttribute("AzureBots", azureBots)
	Replicated:SetAttribute("CoralBots", coralBots)
	Replicated:SetAttribute("PracticeBots", Bots.Enabled())
	Bots.Publish(Replicated)
	Replicated:SetAttribute("Round", Round)
	Replicated:SetAttribute("Message", Message())
end

local function StopCombat(character: Model)
	Status.CancelDash(character)
	Skills.Cancel(character)
	Status.ClearEffects(character)
	for _, attribute in
		{
			"StunnedUntil",
			"StaggeredUntil",
			"ControlDisabledUntil",
			"RootedUntil",
			"ConfusedUntil",
			"CaptureResolveUntil",
		}
	do
		character:SetAttribute(attribute, 0)
	end
	Status.SetBlocking(character, false)
	Status.SetSprinting(character, false)
end

local function Position(player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return
	end
	local member = Members[player]
	local playing = member ~= nil and Active()
	local practicing = RunService:IsStudio() and member == nil
	local destination = Lobby
	if practicing and PracticeSpawn then
		destination = PracticeSpawn
	end
	if member and (playing or State.Phase == "Countdown") then
		local teamSpawns = Arena.Spawns:FindFirstChild(member.Team)
		local spawn = teamSpawns and teamSpawns:FindFirstChild(tostring(member.Slot))
		if spawn and spawn:IsA("BasePart") then
			destination = spawn
		end
	end
	character:SetAttribute("CaptureTeam", if member then member.Team else nil)
	-- Training rigs are outside Capture; keep practice characters outside its combat authority too.
	character:SetAttribute("CaptureActive", if practicing then nil else playing)
	character:SetAttribute(
		"CaptureProtectedUntil",
		if practicing then nil elseif playing then Workspace:GetServerTimeNow() + Rules.ProtectionSeconds else 0
	)
	-- Capture protection owns its exact duration, independent of the default spawn location.
	local forceField = character:FindFirstChildOfClass("ForceField")
	if forceField then
		forceField:Destroy()
	end
	StopCombat(character)
	character:PivotTo(destination.CFrame)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	player:SetAttribute("CaptureRespawnAt", 0)
end

local function CharacterAdded(player: Player, character: Model)
	character:SetAttribute("CaptureActive", false)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if player.Character ~= character or not humanoid or not humanoid:IsA("Humanoid") or not root then
		return
	end
	local connections = ConnectionsByPlayer[player]
	if not connections then
		return
	end
	if connections.Died then
		connections.Died:Disconnect()
	end
	connections.Died = humanoid.Died:Connect(function()
		if player.Character ~= character then
			return
		end
		if Members[player] and Active() then
			Outcomes.Finish(character, Workspace:GetServerTimeNow())
			player:SetAttribute("CaptureRespawnAt", Workspace:GetServerTimeNow() + Rules.RespawnSeconds)
		end
		character:SetAttribute("CaptureActive", false)
	end)
	Position(player, character)
end

local function Reload(player: Player)
	task.spawn(function()
		if player.Parent ~= Players then
			return
		end
		local ok, message = pcall(function()
			player:LoadCharacterAsync()
		end)
		if not ok then
			warn("[Capture] Character reload failed for " .. player.Name .. ": " .. tostring(message))
		end
	end)
end

local function BeginRound(now: number)
	Round += 1
	State = Rules.New(now)
	Bots.Begin(Occupancy(), now)
	for player, member in Members do
		member.Objective = 0
		player:SetAttribute("CaptureStatus", "Playing")
		player:SetAttribute("CaptureRound", Round)
		player:SetAttribute("CaptureKills", 0)
		player:SetAttribute("CaptureAssists", 0)
		player:SetAttribute("CaptureObjective", 0)
		if player.Character then
			player.Character:SetAttribute("CaptureActive", false)
		end
		Reload(player)
	end
end

local function Finish(now: number, winner: string)
	State.Phase = "Results"
	State.Winner = winner
	State.EndsAt = now + Rules.ResultsSeconds
	Bots.Stop()
	for player in Members do
		player:SetAttribute("CaptureRespawnAt", 0)
		if player.Character then
			player.Character:SetAttribute("CaptureActive", false)
			StopCombat(player.Character)
			Outcomes.Clear(player.Character)
		end
	end
end

function System:Join(player: Player): boolean
	if not Ready or player.Parent ~= Players then
		return false
	end
	if Members[player] then
		return true
	end
	local remaining = (RejoinAt[player] or 0) - Workspace:GetServerTimeNow()
	if remaining > 0 then
		player:SetAttribute("CaptureMessage", "Rejoin available in " .. math.ceil(remaining) .. "s")
		return false
	end
	RejoinAt[player] = nil
	local azure, coral = Counts()
	if azure + coral >= Rules.Capacity * 2 then
		player:SetAttribute("CaptureMessage", "Match is full • try again when a slot opens")
		return false
	end
	local team: Rules.Team = if azure <= coral then "Azure" else "Coral"
	local used: { [number]: boolean } = {}
	for _, member in Members do
		if member.Team == team then
			used[member.Slot] = true
		end
	end
	local slot = 1
	while used[slot] do
		slot += 1
	end
	Members[player] = { Team = team, Slot = slot, Objective = 0 }
	player.Team = Teams:FindFirstChild(team) :: Team
	player.Neutral = false
	player:SetAttribute("CaptureTeam", team)
	player:SetAttribute("CaptureStatus", if Active() then "Playing" else "Queued")
	player:SetAttribute("CaptureRound", Round)
	player:SetAttribute("CaptureKills", 0)
	player:SetAttribute("CaptureAssists", 0)
	player:SetAttribute("CaptureObjective", 0)
	player:SetAttribute("CaptureMessage", "")
	if Active() then
		Bots.Sync(Occupancy(), Workspace:GetServerTimeNow())
		Reload(player)
	elseif player.Character then
		Position(player, player.Character)
	end
	Publish()
	return true
end

function System:Leave(player: Player)
	if Members[player] and Active() then
		RejoinAt[player] = Workspace:GetServerTimeNow() + Rules.RespawnSeconds
	end
	Members[player] = nil
	if Active() then
		Bots.Sync(Occupancy(), Workspace:GetServerTimeNow())
	end
	player.Team = nil
	player.Neutral = true
	player:SetAttribute("CaptureTeam", nil)
	player:SetAttribute("CaptureStatus", if RunService:IsStudio() then "Practice" else "Lobby")
	player:SetAttribute("CaptureRespawnAt", 0)
	player:SetAttribute("CaptureMessage", "")
	if player.Character then
		Outcomes.Clear(player.Character)
		Position(player, player.Character)
	end
	if Ready then
		Publish()
	end
end

function System:Step(dt: number)
	if not Ready then
		return
	end
	Accumulator += dt
	if Accumulator < UPDATE then
		return
	end
	local elapsed = Accumulator
	Accumulator = 0
	local now = Workspace:GetServerTimeNow()
	if State.Phase == "Waiting" then
		if Enough() then
			State.Phase = "Countdown"
			State.EndsAt = now + Rules.CountdownSeconds
			for player in Members do
				player:SetAttribute("CaptureStatus", "Queued")
				if player.Character then
					Position(player, player.Character)
				end
			end
		end
	elseif State.Phase == "Countdown" then
		if not Enough() then
			State.Phase = "Waiting"
			State.EndsAt = 0
		elseif now >= State.EndsAt then
			BeginRound(now)
		end
	elseif State.Phase == "Results" then
		if now >= State.EndsAt then
			State = Rules.New(now)
			State.Phase = "Waiting"
			State.EndsAt = 0
			for player in Members do
				player:SetAttribute("CaptureStatus", "Queued")
				if player.Character then
					Position(player, player.Character)
				end
			end
		end
	else
		if not Enough() then
			local azure, coral = Counts()
			Finish(now, if azure > 0 then "Azure" else if coral > 0 then "Coral" else "Draw")
		else
			Bots.Step(now, State.Owner)
			local azure, coral = Bots.PointCounts(now)
			for player, member in Members do
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if
					not character
					or character:GetAttribute("CaptureActive") ~= true
					or not humanoid
					or humanoid.Health <= 0
					or not root
					or not root:IsA("BasePart")
					or (character:GetAttribute("CaptureProtectedUntil") or 0) > now
				then
					continue
				end
				local offset = root.Position - Point.Position
				if math.abs(offset.Y) <= Rules.Height and Vector2.new(offset.X, offset.Z).Magnitude <= Rules.Radius then
					if member.Team == "Azure" then
						azure += 1
					else
						coral += 1
					end
					member.Objective += elapsed
					player:SetAttribute("CaptureObjective", math.floor(member.Objective))
				end
			end
			Rules.Step(State, elapsed, now, azure, coral)
			if State.Phase == "Results" then
				Finish(now, State.Winner)
			end
		end
	end
	Publish()
end

function System:Init()
	local arena = Workspace:FindFirstChild("CaptureArena")
	local state = ReplicatedStorage:FindFirstChild("CaptureState")
	assert(arena and arena:IsA("Model"), "[Capture] Author Workspace.CaptureArena in Studio before enabling Capture")
	assert(
		state and state:IsA("Folder"),
		"[Capture] Author ReplicatedStorage.CaptureState in Studio before enabling Capture"
	)
	Arena = arena
	Bots.Init(Arena)
	Replicated = state
	Point = Arena:FindFirstChild("Point") :: BasePart
	Lobby = Arena:FindFirstChild("Lobby") :: BasePart
	if RunService:IsStudio() then
		local spawn = Arena:FindFirstChild("PracticeSpawn")
		assert(spawn and spawn:IsA("BasePart"), "[Capture] Missing authored PracticeSpawn for Studio testing")
		PracticeSpawn = spawn
	end
	assert(
		Point and Point:IsA("BasePart") and Lobby and Lobby:IsA("BasePart"),
		"[Capture] Point and Lobby parts are required"
	)
	for _, team in { "Azure", "Coral" } do
		assert(Teams:FindFirstChild(team), "[Capture] Missing authored Team " .. team)
		local spawns = Arena:FindFirstChild("Spawns")
		local folder = spawns and spawns:FindFirstChild(team)
		for index = 1, Rules.Capacity do
			local spawn = folder and folder:FindFirstChild(tostring(index))
			assert(spawn and spawn:IsA("BasePart"), "[Capture] Missing authored spawn " .. team .. "/" .. index)
		end
	end
	Players.RespawnTime = Rules.RespawnSeconds
	State.Phase = "Waiting"
	State.EndsAt = 0
	Ready = true
	local function bind(player: Player)
		if ConnectionsByPlayer[player] then
			return
		end
		ConnectionsByPlayer[player] = {
			Character = player.CharacterAdded:Connect(function(character)
				CharacterAdded(player, character)
			end),
			Died = nil,
		}
		player.Neutral = true
		player:SetAttribute("CaptureStatus", if RunService:IsStudio() then "Practice" else "Lobby")
		player:SetAttribute("CaptureKills", 0)
		player:SetAttribute("CaptureAssists", 0)
		player:SetAttribute("CaptureObjective", 0)
		player:SetAttribute("CaptureRespawnAt", 0)
		if player.Character then
			task.spawn(CharacterAdded, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(bind)
	Players.PlayerRemoving:Connect(function(player)
		self:Leave(player)
		local connections = ConnectionsByPlayer[player]
		if connections then
			connections.Character:Disconnect()
			if connections.Died then
				connections.Died:Disconnect()
			end
		end
		ConnectionsByPlayer[player] = nil
		Requests[player] = nil
		RejoinAt[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		bind(player)
	end
	Server.Capture.Request.On(function(player, join)
		local now = Workspace:GetServerTimeNow()
		if (Requests[player] or 0) > now then
			return
		end
		Requests[player] = now + 0.5
		if join then
			self:Join(player)
		else
			self:Leave(player)
		end
	end)
	Publish()
end

function System:Start()
	RunService.Heartbeat:Connect(function(dt)
		self:Step(dt)
	end)
end

return System

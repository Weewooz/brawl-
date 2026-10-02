--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TextChatService = game:GetService("TextChatService")
local Workspace = game:GetService("Workspace")

local Combat = require(ServerScriptService.Systems.Combat)
local Map = require(script.Map)
local Mobs = require(script.Mobs)
local Town = require(script.Town)

type MemberStatus = "Active" | "Downed" | "Eliminated"
type Difficulty = {
	Name: string,
	Waves: number,
	BaseMobs: number,
	Health: number,
	Damage: number,
}
type Member = {
	Status: MemberStatus,
	Character: Model,
	Humanoid: Humanoid,
	Revives: number,
	Generation: number,
	Marker: Part?,
	Died: RBXScriptConnection?,
	WalkSpeed: number,
	JumpPower: number,
	JumpHeight: number,
}
type Run = {
	Id: number,
	Slot: number,
	Active: boolean,
	Difficulty: Difficulty,
	Map: Map.Result,
	Players: { Player },
	Members: { [Player]: Member },
	Mobs: { Mobs.Actor },
	Zone: number,
	Wave: number,
	Remaining: number,
	Spawning: boolean,
	GateOpen: boolean,
}

export type System = {
	Init: (self: System) -> (),
	Start: (self: System) -> (),
	StartRun: (self: System, player: Player, difficulty: string) -> (boolean, string),
	DownPlayer: (self: System, player: Player, character: Model) -> boolean,
	Revive: (self: System, target: Player, helper: Player) -> boolean,
	Eliminate: (self: System, run: Run, player: Player) -> (),
	FinishRun: (self: System, run: Run, message: string) -> (),
	StartWave: (self: System, run: Run) -> (),
	OnMobDied: (self: System, run: Run, actor: Mobs.Actor) -> (),
	CompleteWave: (self: System, run: Run) -> (),
}

local System = {} :: System
local DIFFICULTIES: { [string]: Difficulty } = {
	Easy = { Name = "Easy", Waves = 2, BaseMobs = 2, Health = 70, Damage = 5 },
	Normal = { Name = "Normal", Waves = 3, BaseMobs = 3, Health = 100, Damage = 8 },
	Hard = { Name = "Hard", Waves = 4, BaseMobs = 4, Health = 135, Damage = 12 },
}
local DOWNED_SECONDS = 30
local REVIVE_PROTECTION = 3
local WAVE_PAUSE = 2
local UPDATE_INTERVAL = 0.25
local START_COOLDOWN = 3
local MAX_PARTY = 8
local Runs: { [number]: Run } = {}
local RunsByPlayer: { [Player]: Run } = {}
local Slots: { [number]: boolean } = {}
local NextStartAt: { [Player]: number } = {}
local NextId = 0
local TownMap: Town.Result?

local function GetLiving(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	return character, humanoid, root
end

local function SetMessage(players: { Player }, message: string)
	for _, player in players do
		if player.Parent == Players then
			player:SetAttribute("DungeonMessage", message)
		end
	end
end

local function ShowNotice(player: Player, message: string)
	if player.Parent ~= Players then
		return
	end
	player:SetAttribute("DungeonState", "Notice")
	player:SetAttribute("DungeonMessage", message)
	task.delay(5, function()
		if
			player.Parent == Players
			and player:GetAttribute("DungeonState") == "Notice"
			and player:GetAttribute("DungeonMessage") == message
		then
			player:SetAttribute("DungeonState", nil)
			player:SetAttribute("DungeonMessage", nil)
		end
	end)
end

local function SetRunAttributes(run: Run)
	for _, player in run.Players do
		if player.Parent == Players then
			player:SetAttribute("DungeonZone", run.Zone)
			player:SetAttribute("DungeonWave", run.Wave)
			player:SetAttribute("DungeonDifficulty", run.Difficulty.Name)
			player:SetAttribute("DungeonPartySize", #run.Players)
		end
	end
end

local function InZone(zone: Map.Zone, position: Vector3): boolean
	local bounds = zone.Bounds
	return position.X >= bounds.MinX
		and position.X <= bounds.MaxX
		and position.Z >= bounds.MinZ
		and position.Z <= bounds.MaxZ
		and math.abs(position.Y - zone.FloorTop) <= 12
end

local function GetTargets(run: Run): { BasePart }
	local targets: { BasePart } = {}
	local zone = run.Map.Zones[run.Zone]
	for _, player in run.Players do
		local state = run.Members[player]
		if state and state.Status == "Active" then
			local character, _, root = GetLiving(player)
			if character == state.Character and root and InZone(zone, root.Position) then
				table.insert(targets, root)
			end
		end
	end
	return targets
end

local function AllocateSlot(): number
	local slot = 1
	while Slots[slot] do
		slot += 1
	end
	Slots[slot] = true
	return slot
end

local function ResolveParty(leader: Player): ({ Player }?, string?)
	local town = TownMap
	if not town then
		return nil, "The town is still loading."
	end
	local _, _, leaderRoot = GetLiving(leader)
	if not leaderRoot then
		return nil, "You need a living character to start a run."
	end
	if RunsByPlayer[leader] then
		return nil, "You are already in a dungeon run."
	end
	if not Town.Contains(town, leaderRoot.Position) then
		return nil, "Stand in the blue town zone to start a run."
	end
	local members: { Player } = {}
	for _, player in Players:GetPlayers() do
		local _, _, root = GetLiving(player)
		if root and Town.Contains(town, root.Position) and not RunsByPlayer[player] then
			table.insert(members, player)
		end
	end
	table.sort(members, function(a, b)
		return a.UserId < b.UserId
	end)
	if #members > MAX_PARTY then
		return nil, `The staging zone supports up to {MAX_PARTY} players.`
	end
	return members, nil
end

local function ClearMarker(member: Member)
	local marker = member.Marker
	member.Marker = nil
	if marker then
		marker:Destroy()
	end
end

local function ResetPlayer(player: Player, run: Run)
	local member = run.Members[player]
	if member then
		ClearMarker(member)
		if member.Died then
			member.Died:Disconnect()
			member.Died = nil
		end
		member.Character:SetAttribute("DungeonRunId", nil)
		member.Character:SetAttribute("DungeonDowned", nil)
		member.Humanoid.PlatformStand = false
		member.Humanoid.WalkSpeed = member.WalkSpeed
		member.Humanoid.JumpPower = member.JumpPower
		member.Humanoid.JumpHeight = member.JumpHeight
	end
	RunsByPlayer[player] = nil
	player:SetAttribute("DungeonState", nil)
	player:SetAttribute("DungeonZone", nil)
	player:SetAttribute("DungeonWave", nil)
	player:SetAttribute("DungeonDifficulty", nil)
	player:SetAttribute("DungeonPartySize", nil)
	player:SetAttribute("DungeonMessage", nil)
	local town = TownMap
	if town and player.Parent == Players then
		player.RespawnLocation = town.Spawn
		local character, _, _ = GetLiving(player)
		if character then
			character:PivotTo(town.Return)
		else
			task.defer(function()
				if player.Parent == Players then
					player:LoadCharacter()
				end
			end)
		end
	end
end

function System:FinishRun(run: Run, message: string)
	if not run.Active then
		return
	end
	run.Active = false
	Runs[run.Id] = nil
	Slots[run.Slot] = nil
	for _, actor in run.Mobs do
		Mobs.Remove(actor, Combat)
	end
	table.clear(run.Mobs)
	for _, player in run.Players do
		ResetPlayer(player, run)
		ShowNotice(player, message)
	end
	run.Map.Model:Destroy()
	print(`[Dungeon] Run {run.Id} ended: {message}`)
end

function System:Eliminate(run: Run, player: Player)
	local member = run.Members[player]
	if not run.Active or not member or member.Status == "Eliminated" then
		return
	end
	member.Status = "Eliminated"
	member.Generation += 1
	ClearMarker(member)
	member.Character:SetAttribute("DungeonRunId", nil)
	member.Character:SetAttribute("DungeonDowned", nil)
	player:SetAttribute("DungeonState", "Eliminated")
	player:SetAttribute("DungeonMessage", "You were eliminated. The party can continue.")
	local town = TownMap
	if town and player.Parent == Players then
		player.RespawnLocation = town.Spawn
		local character, _, _ = GetLiving(player)
		if character then
			character:PivotTo(town.Return)
		end
	end
	for _, teammate in run.Players do
		local state = run.Members[teammate]
		if state and state.Status ~= "Eliminated" then
			return
		end
	end
	self:FinishRun(run, "The whole party was eliminated")
end

function System:Revive(target: Player, helper: Player): boolean
	local run = RunsByPlayer[target]
	if not run or not run.Active or RunsByPlayer[helper] ~= run then
		return false
	end
	local member = run.Members[target]
	local helperState = run.Members[helper]
	if not member or member.Status ~= "Downed" or member.Revives <= 0 or not helperState then
		return false
	end
	if target == helper or helperState.Status ~= "Active" then
		return false
	end
	local _, _, helperRoot = GetLiving(helper)
	local marker = member.Marker
	if not helperRoot or not marker or (helperRoot.Position - marker.Position).Magnitude > 12 then
		return false
	end
	member.Revives -= 1
	member.Generation += 1
	member.Status = "Active"
	ClearMarker(member)
	member.Character:SetAttribute("DungeonDowned", nil)
	member.Humanoid.PlatformStand = false
	member.Humanoid.WalkSpeed = member.WalkSpeed
	member.Humanoid.JumpPower = member.JumpPower
	member.Humanoid.JumpHeight = member.JumpHeight
	member.Humanoid.Health = math.max(1, member.Humanoid.MaxHealth * 0.5)
	local protection = ReplicatedStorage.Assets.DungeonReviveProtection:Clone() :: ForceField
	protection.Parent = member.Character
	task.delay(REVIVE_PROTECTION, function()
		protection:Destroy()
	end)
	target:SetAttribute("DungeonState", "Active")
	SetMessage(run.Players, target.Name .. " was revived.")
	return true
end

function System:DownPlayer(player: Player, character: Model): boolean
	local run = RunsByPlayer[player]
	local member = run and run.Members[player]
	if not run or not run.Active or not member or member.Status ~= "Active" or member.Character ~= character then
		return false
	end
	member.Status = "Downed"
	member.Generation += 1
	local generation = member.Generation
	character:SetAttribute("DungeonDowned", true)
	member.Humanoid.Health = 1
	member.Humanoid.PlatformStand = true
	member.Humanoid.WalkSpeed = 0
	member.Humanoid.JumpPower = 0
	member.Humanoid.JumpHeight = 0
	player:SetAttribute("DungeonState", "Downed")
	SetMessage(run.Players, player.Name .. " is downed. Revive within 30 seconds.")
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local marker = ReplicatedStorage.Assets.DungeonReviveMarker:Clone() :: Part
		marker.Position = root.Position + Vector3.new(0, 3, 0)
		marker.Parent = run.Map.Model
		member.Marker = marker
		local prompt = marker:FindFirstChild("Revive") :: ProximityPrompt
		prompt.ObjectText = player.DisplayName
		prompt.Triggered:Connect(function(helper)
			self:Revive(player, helper)
		end)
	end
	task.delay(DOWNED_SECONDS, function()
		if run.Active and member.Status == "Downed" and member.Generation == generation then
			self:Eliminate(run, player)
		end
	end)
	return true
end

function System:OnMobDied(run: Run, actor: Mobs.Actor)
	if not run.Active then
		return
	end
	run.Remaining = math.max(0, run.Remaining - 1)
	task.delay(2, function()
		if actor.Model.Parent then
			Mobs.Remove(actor, Combat)
		end
	end)
	if run.Spawning or run.Remaining > 0 then
		return
	end
	self:CompleteWave(run)
end

function System:CompleteWave(run: Run)
	if not run.Active or run.Spawning or run.Remaining > 0 or run.GateOpen then
		return
	end
	if run.Wave < run.Difficulty.Waves then
		SetMessage(run.Players, `Wave {run.Wave} cleared. Next wave incoming.`)
		task.delay(WAVE_PAUSE, function()
			if run.Active and run.Remaining == 0 and not run.GateOpen then
				self:StartWave(run)
			end
		end)
	else
		run.GateOpen = true
		Map.OpenGate(run.Map, run.Zone)
		if run.Zone == 3 then
			self:FinishRun(run, "Dungeon completed")
		else
			SetMessage(run.Players, `Zone {run.Zone} clear. Walk through the open gate.`)
		end
	end
end

function System:StartWave(run: Run)
	if not run.Active or run.Spawning then
		return
	end
	run.Spawning = true
	run.Wave += 1
	SetRunAttributes(run)
	SetMessage(run.Players, `Zone {run.Zone}, wave {run.Wave} of {run.Difficulty.Waves}`)
	local count = math.min(12, run.Difficulty.BaseMobs + run.Zone + run.Wave - 2 + #run.Players - 1)
	local zone = run.Map.Zones[run.Zone]
	local health = run.Difficulty.Health + (run.Zone - 1) * 20
	local damage = run.Difficulty.Damage + (run.Zone - 1) * 2
	local spawned = 0
	for index = 1, count do
		if not run.Active then
			break
		end
		local spawn = zone.MobSpawns[(index - 1) % #zone.MobSpawns + 1]
		local offset = Vector3.new(math.floor((index - 1) / #zone.MobSpawns) * 3, 0, 0)
		local actor = Mobs.Spawn(run.Map.Model, spawn + offset, run.Id, run.Zone, health, damage, Combat)
		if actor then
			if not run.Active then
				Mobs.Remove(actor, Combat)
				break
			end
			table.insert(run.Mobs, actor)
			run.Remaining += 1
			spawned += 1
			actor.Humanoid.Died:Connect(function()
				self:OnMobDied(run, actor)
			end)
		end
	end
	run.Spawning = false
	if not run.Active then
		return
	end
	if spawned == 0 then
		self:FinishRun(run, "Could not spawn dungeon mobs")
	elseif run.Remaining == 0 then
		self:CompleteWave(run)
	end
end

function System:StartRun(player: Player, difficulty: string): (boolean, string)
	local selected = DIFFICULTIES[difficulty]
	if not selected then
		return false, "Difficulty must be Easy, Normal, or Hard."
	end
	if (NextStartAt[player] or 0) > os.clock() then
		return false, "Wait a moment before starting another run."
	end
	local party, reason = ResolveParty(player)
	if not party or #party == 0 then
		return false, reason or "No eligible players are in the staging zone."
	end
	NextStartAt[player] = os.clock() + START_COOLDOWN
	local slot = AllocateSlot()
	NextId += 1
	local id = NextId
	local seed = os.time() + id * 977
	local ok, generated = pcall(Map.Build, seed, Vector3.new(1000 + slot * 400, 0, 0))
	if not ok then
		Slots[slot] = nil
		warn("[Dungeon] Map generation failed: " .. tostring(generated))
		return false, "Dungeon map generation failed."
	end
	local map = generated :: Map.Result
	map.Model.Name = `DungeonRun{id}`
	map.Model:SetAttribute("Seed", seed)
	local run: Run = {
		Id = id,
		Slot = slot,
		Active = true,
		Difficulty = selected,
		Map = map,
		Players = party,
		Members = {},
		Mobs = {},
		Zone = 1,
		Wave = 0,
		Remaining = 0,
		Spawning = false,
		GateOpen = false,
	}
	Runs[id] = run
	for index, memberPlayer in party do
		local character, humanoid, _ = GetLiving(memberPlayer)
		if character and humanoid then
			local member: Member = {
				Status = "Active",
				Character = character,
				Humanoid = humanoid,
				Revives = 1,
				Generation = 0,
				Marker = nil,
				Died = nil,
				WalkSpeed = humanoid.WalkSpeed,
				JumpPower = humanoid.JumpPower,
				JumpHeight = humanoid.JumpHeight,
			}
			run.Members[memberPlayer] = member
			RunsByPlayer[memberPlayer] = run
			character:SetAttribute("DungeonRunId", id)
			memberPlayer:SetAttribute("DungeonState", "Active")
			member.Died = humanoid.Died:Connect(function()
				self:Eliminate(run, memberPlayer)
			end)
			local row = math.floor((index - 1) / 4)
			local column = (index - 1) % 4
			local entry = map.Zones[1].Entry + Vector3.new(row * 4, 0, (column - 1.5) * 4)
			character:PivotTo(CFrame.new(entry))
		end
	end
	SetRunAttributes(run)
	self:StartWave(run)
	print(`[Dungeon] Run {id} started at seed {seed} with {#party} player(s), {difficulty}`)
	return true, `Started {difficulty} dungeon with {#party} player(s).`
end

function System:Init()
	Combat:SetLethalHandler(function(player, character)
		return self:DownPlayer(player, character)
	end)
end

function System:Start()
	TownMap = Town.Build(function(player, difficulty)
		local ok, message = self:StartRun(player, difficulty)
		if not ok then
			ShowNotice(player, message)
		end
	end)
	local town = TownMap :: Town.Result
	local function setupPlayer(player: Player)
		player.RespawnLocation = town.Spawn
		local function placeInTown(character: Model)
			local root = character:WaitForChild("HumanoidRootPart", 5)
			if root and not RunsByPlayer[player] and player.Parent == Players then
				character:PivotTo(town.Return)
			end
		end
		player.CharacterAdded:Connect(placeInTown)
		if player.Character then
			task.defer(placeInTown, player.Character)
		end
	end
	Players.PlayerAdded:Connect(setupPlayer)
	for _, player in Players:GetPlayers() do
		setupPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		NextStartAt[player] = nil
		local run = RunsByPlayer[player]
		if run then
			self:Eliminate(run, player)
			RunsByPlayer[player] = nil
		end
	end)
	local command = TextChatService:WaitForChild("DungeonCommand") :: TextChatCommand
	command.Triggered:Connect(function(source, text)
		local player = Players:GetPlayerByUserId(source.UserId)
		if not player then
			return
		end
		local argument = string.match(text, "^%S+%s+(%S+)") or "Normal"
		local difficulty = string.upper(string.sub(argument, 1, 1)) .. string.lower(string.sub(argument, 2))
		local ok, message = self:StartRun(player, difficulty)
		if not ok then
			ShowNotice(player, message)
		end
	end)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < UPDATE_INTERVAL then
			return
		end
		elapsed = 0
		local now = Workspace:GetServerTimeNow()
		for _, run in Runs do
			if not run.Active then
				continue
			end
			if run.GateOpen and run.Zone < 3 then
				local nextZone = run.Map.Zones[run.Zone + 1]
				for _, player in run.Players do
					local state = run.Members[player]
					local _, _, root = GetLiving(player)
					if state and state.Status == "Active" and root and InZone(nextZone, root.Position) then
						run.Zone += 1
						run.Wave = 0
						run.GateOpen = false
						self:StartWave(run)
						break
					end
				end
			else
				local targets = GetTargets(run)
				for _, actor in run.Mobs do
					Mobs.Step(actor, targets, Combat, now)
				end
			end
		end
	end)
end

return System

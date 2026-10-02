--!strict
--[[
	Profile — authoritative player data.

	ProfileStore persistence + Blink replication:
	  Synced — full profile once on load, with Private top-level keys stripped
	  Delta  — deferred shadow-diff (scalars + collection ops), see Diff.luau

	Mutate through Update/Add/Remove (auto-replicates) or Get(player, true)
	followed by Replicate. Private template fields never reach the client:
	the shadow is seeded from the stripped clone, so they cannot leak through
	either channel.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Signal = require(ReplicatedStorage.Packages.Signal)
local Utils = require(ReplicatedStorage.Shared.Core.Utils)
local Server = require(ReplicatedStorage.Shared.Network.Server)
local ProfileStore = require(ServerScriptService.ServerPackages.ProfileStore)
local Template = require(ReplicatedStorage.Shared.Core.Profile.Template)
local Diff = require(script.Diff)

local LIVE = true -- Force the live DataStore while testing in Studio
local SAVED = LIVE or not RunService:IsStudio()
local TIMEOUT = 5 -- Seconds before Get warns about a missing profile
local RETRIES = 5 -- MessageAsync attempts before giving up

local DataStore = ProfileStore.New(`DATA_{Template.Version}`, Template.Template)
local Profiles: { [Player]: ProfileStore.Profile<Template.Profile> } = {}
local Shadows: { [Player]: { [string]: any } } = {}
local Tasks: { [string]: thread } = {}
local Dirty: { [Player]: { [string]: boolean } } = {}
local Version: { [Player]: number } = {}
local Cache: { [Player]: { Copy: Template.Profile, Version: number } } = {}

export type Profile = Template.Profile

export type System = {
	Init: (self: System) -> (),
	Start: (self: System) -> (),

	Load: (self: System, player: Player) -> (),
	Release: (self: System, player: Player) -> (),
	Message: (self: System, key: string, message: any) -> any,
	Handle: (self: System, player: Player, message: any, profile: Profile) -> boolean,

	Get: (self: System, player: Player, editable: boolean?, replicate: boolean?) -> Profile?,
	IsLoaded: (self: System, player: Player) -> boolean,
	Update: (self: System, player: Player, path: string, key: string, value: any) -> (),
	Add: (self: System, player: Player, path: string, key: string, value: any) -> (),
	Remove: (self: System, player: Player, path: string, key: string) -> (),
	Replicate: (self: System, player: Player) -> (),
	Reset: (self: System, player: Player) -> (),
	Wipe: (self: System, player: Player) -> (),

	Template: Profile,
	Loaded: Signal.Signal<Player, Profile>,
	Releasing: Signal.Signal<Player, Profile>,
	Received: Signal.Signal<Player, Profile, any>,
}

local System = {} :: System
System.Template = Template.Template
System.Releasing = Signal.new()
System.Received = Signal.new()

do -- Loaded replays already-loaded profiles to late connectors (boot-order safety)
	local signal = Signal.new()
	local connect = signal.Connect
	signal.Connect = function(self, callback)
		for player, profile in pairs(Profiles) do
			task.spawn(callback, player, profile.Data)
		end
		return connect(self, callback)
	end
	System.Loaded = signal :: any
end

--==========================-- Private Functions --==========================--

-- Returns the top-level key from a dot-separated path (e.g. "Inventory.Weapons" -> "Inventory")
local function Key(path: string): string
	return path:match("^([^%.]+)") or path
end

-- Deep clone with Private top-level keys removed; safe to send to the client
local function Strip(data: Profile): { [string]: any }
	local clone = Utils.Clone(data :: any, true)
	for key in pairs(Template.Private) do
		clone[key] = nil
	end
	return clone
end

local function Mark(player: Player, topKey: string)
	if not Template.Private[topKey] then
		if not Dirty[player] then
			Dirty[player] = {}
		end
		Dirty[player][topKey] = true
	end
	Version[player] = (Version[player] or 0) + 1
end

--==========================-- Public Functions --==========================--

function System:Init() end

function System:Start()
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			self:Load(player)
		end)
	end

	Players.PlayerAdded:Connect(function(player: Player)
		self:Load(player)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		self:Release(player)
	end)

	-- Playtime accumulates silently; the client gets it with the next delta or session
	task.spawn(function()
		while true do
			local delta = task.wait(1)
			for _, profile in pairs(Profiles) do
				profile.Data.Stats.Seconds += delta
			end
		end
	end)
end

function System:Load(player: Player)
	local store = if SAVED then DataStore else DataStore.Mock
	local profile = store:StartSessionAsync(`{player.UserId}`, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if profile == nil then
		player:Kick(`Profile load fail - Please rejoin`)
		return
	end

	profile:AddUserId(player.UserId) -- GDPR compliance
	profile:Reconcile()

	profile.OnSessionEnd:Connect(function()
		Profiles[player] = nil
		Shadows[player] = nil
		Dirty[player] = nil
		Version[player] = nil
		Cache[player] = nil
		player:Kick(`Profile session end - Please rejoin`)
	end)

	if player.Parent ~= Players then
		profile:EndSession()
		return
	end

	Profiles[player] = profile :: any
	Version[player] = 0

	local stats = profile.Data.Stats
	local now = os.time()
	if stats.First <= 0 then
		stats.First = now
	end
	stats.Last = now
	stats.Joins += 1

	profile:MessageHandler(function(message: any, processed: () -> ())
		if self:Handle(player, message, profile.Data) then
			processed()
		end
	end)

	-- Push the stripped profile once and seed the shadow from the same clone,
	-- so Private keys can never enter the diff
	local stripped = Strip(profile.Data)
	Server.Profile.Synced.Fire(player, stripped, Template.Version)
	Shadows[player] = Utils.Clone(stripped, true)
	self.Loaded:Fire(player, profile.Data)
end

function System:Release(player: Player)
	local profile = Profiles[player]
	if profile then
		self.Releasing:Fire(player, profile.Data)
		profile:EndSession()
	end
	Profiles[player] = nil
	Shadows[player] = nil
	Dirty[player] = nil
	Version[player] = nil
	Cache[player] = nil
end

-- Replace live data with a fresh template and end the session (forces rejoin)
function System:Reset(player: Player)
	local profile = Profiles[player]
	if not profile then
		return
	end
	profile.Data = Utils.Clone(Template.Template :: any, true) :: Profile
	self:Replicate(player)
	self:Release(player)
end

-- Replace live data with a fresh template but keep the session open
function System:Wipe(player: Player)
	local profile = Profiles[player]
	if not profile then
		return
	end
	profile.Data = Utils.Clone(Template.Template :: any, true) :: Profile
	Dirty[player] = nil
	Version[player] = (Version[player] or 0) + 1
	Cache[player] = nil

	local stripped = Strip(profile.Data)
	Server.Profile.Synced.Fire(player, stripped, Template.Version)
	Shadows[player] = Utils.Clone(stripped, true)
	self.Loaded:Fire(player, profile.Data)
end

-- Sends a ProfileStore message to the given session key (player UserId as string)
function System:Message(key: string, message: any): any
	local lastError: any
	for attempt = 1, RETRIES do
		local ok, result = pcall(function()
			return DataStore:MessageAsync(key, message)
		end)
		if ok then
			return result
		end
		lastError = result
		if attempt < RETRIES then
			task.wait(1 * attempt)
		end
	end
	warn(`[Profile] MessageAsync failed after {RETRIES} attempts for key "{key}": {tostring(lastError)}`)
	return nil
end

-- ATTENTION: game-specific message types go here (add a branch and return true).
-- Unknown messages return false so ProfileStore retries instead of dropping them.
function System:Handle(player: Player, message: any, profile: Profile): boolean
	if typeof(message) ~= "table" then
		return false
	end

	self.Received:Fire(player, profile, message)

	return false
end

function System:IsLoaded(player: Player): boolean
	return Profiles[player] ~= nil
end

-- Frozen cached copy by default; editable=true returns the live table
-- (pass replicate=true to schedule a diff after in-place edits)
function System:Get(player: Player, editable: boolean?, replicate: boolean?): Profile?
	if not Profiles[player] then
		local done = Signal.new()
		local loadedConn
		local leavingConn
		loadedConn = self.Loaded:Connect(function(firedPlayer: Player)
			if firedPlayer == player then
				loadedConn:Disconnect()
				done:Fire()
			end
		end)
		leavingConn = player.AncestryChanged:Connect(function()
			if not player:IsDescendantOf(Players) then
				leavingConn:Disconnect()
				loadedConn:Disconnect()
				done:Fire()
			end
		end)
		local timeoutWarn = task.delay(TIMEOUT, function()
			warn(`[Profile] Infinite yield while getting {player.Name}'s profile (Server)`)
		end)
		done:Wait()
		done:Destroy()
		task.cancel(timeoutWarn)
		leavingConn:Disconnect()
		if not Profiles[player] then
			return nil
		end
	end

	local profile = Profiles[player]
	if not editable then
		local version = Version[player] or 0
		local cache = Cache[player]
		if cache and cache.Version == version then
			return cache.Copy
		end
		local copy = Utils.Clone(profile.Data :: any, true) :: Template.Profile
		Utils.Freeze(copy :: any, true)
		Cache[player] = { Copy = copy, Version = version }
		return copy
	end

	if replicate then
		self:Replicate(player)
	end
	return profile.Data :: Template.Profile
end

-- Coalesced diff: one deferred push per player regardless of write count
function System:Replicate(player: Player)
	local name = "SYNC PROFILE:" .. tostring(player.UserId)
	if Tasks[name] then
		return
	end

	Tasks[name] = task.defer(function()
		xpcall(function()
			local profile = Profiles[player]
			local shadow = Shadows[player]
			if not profile or not shadow then
				return
			end

			local keys: { [string]: boolean } = {}
			local dirtyKeys = Dirty[player]
			if dirtyKeys and next(dirtyKeys) then
				for key in pairs(dirtyKeys) do
					keys[key] = true
				end
				Dirty[player] = {}
			else
				-- Shadow keys cover every public top-level field (seeded stripped),
				-- so Private data is excluded from full scans by construction
				for key in pairs(shadow) do
					keys[key] = true
				end
			end

			Diff.Push(player, profile.Data :: any, shadow, keys)
		end, function(err: string)
			task.spawn(error, err)
		end)

		Tasks[name] = nil
	end)
end

--// CRUD helpers — mutate the live profile entry and schedule a deferred diff

-- Top-level writes use path "=": Update(player, "=", "Level", 2)
function System:Update(player: Player, path: string, key: string, value: any)
	local profile = self:Get(player, true)
	if not profile then
		return
	end

	if path == "=" then
		local current = (profile :: any)[key]
		local ok = typeof(current) == typeof(value)
		-- Allow first-time writes when Reconcile never set the key
		if not ok and current == nil then
			local valueType = typeof(value)
			ok = valueType == "table" or valueType == "number" or valueType == "string" or valueType == "boolean"
		end
		if not ok then
			warn(`[Profile] Update: type mismatch for top-level "{key}" for {player.Name}`)
			return
		end
		(profile :: any)[key] = value
		Mark(player, key)
		self:Replicate(player)
		return
	end

	local collection = Utils.Nested(profile, path)
	if not collection then
		warn(`[Profile] Update: path "{path}" not found for {player.Name}`)
		return
	end
	-- Missing keys (nil) must be assignable; otherwise nested first-time
	-- writes silently no-op (typeof(nil) never matches the value type)
	local existing = collection[key]
	if existing == nil or typeof(existing) == typeof(value) then
		collection[key] = value
		Mark(player, Key(path))
		self:Replicate(player)
	end
end

function System:Add(player: Player, path: string, key: string, value: any)
	local profile = Profiles[player]
	if not profile then
		return
	end
	local collection = Utils.Nested(profile.Data, path)
	if not collection then
		warn(`[Profile] Add: path "{path}" not found for {player.Name}`)
		return
	end
	collection[key] = value
	Mark(player, Key(path))
	self:Replicate(player)
end

function System:Remove(player: Player, path: string, key: string)
	local profile = Profiles[player]
	if not profile then
		return
	end
	local collection = Utils.Nested(profile.Data, path)
	if not collection then
		warn(`[Profile] Remove: path "{path}" not found for {player.Name}`)
		return
	end
	collection[key] = nil
	Mark(player, Key(path))
	self:Replicate(player)
end

return System

--!strict
--[[
	Profile (client) — local cache of the server profile.

	Receives Blink Profile.Synced (full, Private-stripped) and Profile.Delta
	(scalar patches or collection ops), applies them to Data, and fires
	Observer path signals. Never yields at require time — consumers use
	Subscribe (replay included) or the Loaded signal instead of blocking.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Packages.Signal)
local Client = require(ReplicatedStorage.Shared.Network.Client)
local Template = require(ReplicatedStorage.Shared.Core.Profile.Template)
local Observer = require(script.Observer)

local Paths = Template.Paths
local Event = Template.Event

export type System = {
	Init: (self: System) -> (),
	Start: (self: System) -> (),

	Observer: Observer.Type,
	Subscribe: (self: System, path: string, callback: (value: any) -> ()) -> Signal.Connection?,
	Get: (self: System, path: string?) -> any,

	Template: typeof(Template),
	Data: Template.Profile?,
	Version: number,
	Loaded: Signal.Signal<Template.Profile>,
}

local System = {} :: System
System.Template = Template
System.Observer = Observer
System.Data = nil
System.Version = 0
System.Loaded = Signal.new()

--==========================-- Private Functions --==========================--

-- Navigates a dot-path inside the local cache; nil-safe
local function Navigate(root: any, path: string): any
	local current: any = root
	for part in string.gmatch(path, "[^%.]+") do
		if type(current) ~= "table" then
			return nil
		end
		current = current[part]
	end
	return current
end

-- Converts a collection table into Added ops so subscribers always receive
-- the same format regardless of initial sync vs incremental delta
local function Ops(path: string, collection: { [string]: any }): { any }
	local ops: { any } = {}
	for entryKey, entryValue in pairs(collection) do
		table.insert(ops, { Path = path, Event = Event.Added, Key = entryKey, Value = entryValue })
	end
	return ops
end

--==========================-- Public Functions --==========================--

function System:Init()
	-- Full initial sync pushed by the server on profile load
	Client.Profile.Synced.On(function(data: Template.Profile, version: number)
		self.Data = data
		self.Version = version

		for key: string, value in pairs(data :: any) do
			if Paths.TOP[key] and type(value) == "table" then
				Observer.Fire(key, Ops(key, value))
			else
				Observer.Fire(key, value)
			end

			-- Also fire registered sub-collection paths (e.g. "Inventory.Weapons")
			if Paths.SUB[key] and type(value) == "table" then
				for subKey, subPath in pairs(Paths.SUB[key]) do
					local subValue = value[subKey]
					if type(subValue) == "table" then
						Observer.Fire(subPath, Ops(subPath, subValue))
					end
				end
			end
		end

		Observer.Fire("Changed", {})
		self.Loaded:Fire(data)
	end)

	Client.Profile.Delta.On(function(delta: any, isCollection: boolean)
		local data = self.Data
		if not data then
			return
		end

		if isCollection then
			-- Apply each op to the local cache and group by path for signal firing
			local opsPerPath: { [string]: { any } } = {}

			for _, op in ipairs(delta) do
				local target = Navigate(data, op.Path)
				if type(target) == "table" then
					if op.Event == Event.Added or op.Event == Event.Changed then
						target[op.Key] = op.Value
					elseif op.Event == Event.Removed then
						target[op.Key] = nil
					end
				end

				if not opsPerPath[op.Path] then
					opsPerPath[op.Path] = {}
				end
				table.insert(opsPerPath[op.Path], op)
			end

			for path, pathOps in pairs(opsPerPath) do
				Observer.Fire(path, pathOps)
			end
		else
			for key, value in pairs(delta) do
				if Paths.SUB[key] then
					-- This key has collection sub-keys — merge scalar sub-keys only.
					-- Replacing the whole table would wipe collection entries that
					-- weren't included in this delta (they travel as collection ops).
					for subKey, subValue in pairs(value :: any) do
						(data :: any)[key][subKey] = subValue
					end
				else
					(data :: any)[key] = value
				end
				Observer.Fire(key, value)
			end
		end

		Observer.Fire("Changed", {})
	end)
end

function System:Start() end

-- Replay-on-subscribe: registers the callback and, if data already arrived,
-- fires the current value immediately so late-subscribing GUI never sees stale state
function System:Subscribe(path: string, callback: (value: any) -> ()): Signal.Connection?
	local conn = Observer.Subscribe(path, callback)

	if self.Data then
		local value = Navigate(self.Data, path)
		if value ~= nil then
			if Paths.ALL[path] and type(value) == "table" then
				task.spawn(callback, Ops(path, value))
			else
				task.spawn(callback, value)
			end
		end
	end

	return conn
end

-- Returns the whole profile cache, or the value at the given dot-path
function System:Get(path: string?): any
	if path and self.Data then
		return Navigate(self.Data, path)
	end
	return self.Data
end

return System

--!strict
--[[
	Diff — shadow compare engine for the Profile system.

	Compares live profile data against the player's shadow copy for the given
	top-level keys, fires Blink Profile.Delta (scalars, then collection ops),
	and updates the shadow to match what was sent. Private keys never appear
	here — the shadow is seeded from a stripped clone, and the caller excludes
	them from the key set.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Utils = require(ReplicatedStorage.Shared.Core.Utils)
local Server = require(ReplicatedStorage.Shared.Network.Server)
local Template = require(ReplicatedStorage.Shared.Core.Profile.Template)

local Paths = Template.Paths
local Event = Template.Event
local Equal = Utils.Equal
local Get = Utils.Nested

export type Op = {
	Path: string,
	Event: string,
	Key: string,
	Value: any?,
}

local Diff = {}

-- Collects Added/Changed/Removed ops for one collection path
local function Differentiate(path: string, live: { [string]: any }, shadow: { [string]: any }, out: { Op })
	for entryKey, entryValue in pairs(live) do
		if shadow[entryKey] == nil then
			table.insert(out, { Path = path, Event = Event.Added, Key = entryKey, Value = entryValue })
		elseif not Equal(entryValue, shadow[entryKey]) then
			table.insert(out, { Path = path, Event = Event.Changed, Key = entryKey, Value = entryValue })
		end
	end
	for entryKey in pairs(shadow) do
		if live[entryKey] == nil then
			table.insert(out, { Path = path, Event = Event.Removed, Key = entryKey })
		end
	end
end

-- Walks/creates a dot-path inside the shadow so ops can be applied to it
local function Ensure(root: any, path: string): { [string]: any }
	local current: any = root
	for part in string.gmatch(path, "[^%.]+") do
		if type(current[part]) ~= "table" then
			current[part] = {}
		end
		current = current[part]
	end
	return current
end

-- Diffs the given top-level keys, fires deltas, and syncs the shadow
function Diff.Push(player: Player, live: { [string]: any }, shadow: { [string]: any }, keys: { [string]: boolean })
	local scalarDelta: { [string]: any } = {}
	local hasScalars = false
	local fullReplace: { [string]: boolean } = {}
	local collectionEvents: { Op } = {}

	for key in pairs(keys) do
		local liveValue = live[key]
		local shadowKey = shadow[key]
		if Equal(liveValue, shadowKey) then
			continue
		end

		if Paths.TOP[key] then
			Differentiate(Paths.TOP[key], liveValue :: any, shadowKey or {}, collectionEvents)
		elseif Paths.SUB[key] then
			local collectionSubs = Paths.SUB[key]
			local scalarChanges: { [string]: any } = {}
			local hasScalarChanges = false

			for subKey, subValue in pairs(liveValue :: any) do
				local collectionPath = collectionSubs[subKey]
				if collectionPath and type(subValue) == "table" then
					local shadowSub = shadowKey and shadowKey[subKey]
					Differentiate(collectionPath, subValue, shadowSub or {}, collectionEvents)
				else
					local shadowSubKey = shadowKey and shadowKey[subKey]
					if not Equal(subValue, shadowSubKey) then
						scalarChanges[subKey] = subValue
						hasScalarChanges = true
					end
				end
			end

			-- Detect sub-keys present in shadow but removed from live
			local hasRemovals = false
			if shadowKey then
				for subKey, shadowSubValue in pairs(shadowKey) do
					if (liveValue :: any)[subKey] == nil then
						local collectionPath = collectionSubs[subKey]
						if collectionPath and type(shadowSubValue) == "table" then
							Differentiate(collectionPath, {}, shadowSubValue, collectionEvents)
						end
						hasRemovals = true
					end
				end
			end

			if hasRemovals then
				scalarDelta[key] = liveValue
				fullReplace[key] = true
				hasScalars = true
			elseif hasScalarChanges then
				scalarDelta[key] = scalarChanges
				hasScalars = true
			end
		else
			scalarDelta[key] = liveValue
			hasScalars = true
		end
	end

	if hasScalars then
		Server.Profile.Delta.Fire(player, scalarDelta, false)

		for key, value in pairs(scalarDelta) do
			if Paths.SUB[key] and not fullReplace[key] then
				local shadowKey = shadow[key]
				if not shadowKey then
					shadowKey = {}
					shadow[key] = shadowKey
				end
				for subKey, subValue in pairs(value :: any) do
					shadowKey[subKey] = type(subValue) == "table" and Utils.Clone(subValue, true) or subValue
				end
			else
				shadow[key] = type(value) == "table" and Utils.Clone(value, true) or value
			end
		end
	end

	if #collectionEvents > 0 then
		Server.Profile.Delta.Fire(player, collectionEvents, true)

		local opsByPath: { [string]: { Op } } = {}
		for _, op in ipairs(collectionEvents) do
			local list = opsByPath[op.Path]
			if not list then
				list = {}
				opsByPath[op.Path] = list
			end
			table.insert(list, op)
		end
		for path, ops in pairs(opsByPath) do
			local shadowCollection = Get(shadow, path) or Ensure(shadow, path)
			for _, op in ipairs(ops) do
				if op.Event == Event.Added or op.Event == Event.Changed then
					shadowCollection[op.Key] = type(op.Value) == "table" and Utils.Clone(op.Value, true) or op.Value
				elseif op.Event == Event.Removed then
					shadowCollection[op.Key] = nil
				end
			end
		end
	end
end

return Diff

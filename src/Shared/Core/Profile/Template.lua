--!strict
--[[
	Template — single source of truth for the player profile.

	Markers (see Schema.lua) replace the old hand-written PATHS array and
	Observer Directory:
	  Collection(t) — diffed as Added/Changed/Removed ops via Profile.Delta
	  Private(t)    — server-only; stripped from Synced, never diffed

	Adding a synced collection or hiding a field is a one-line template edit;
	paths, subscribable names, and defaults derive from this table.
]]

local Schema = require(script.Parent.Schema)

local Collection = Schema.Collection
local Private = Schema.Private

local VERSION = 1 -- ProfileStore `DATA_<VERSION>`; bump to isolate saves

local Event = table.freeze({
	Added = "Added",
	Removed = "Removed",
	Changed = "Changed",
})
export type Event = typeof(Event)

export type Stats = {
	First: number, -- Unix time of first join
	Last: number, -- Unix time of most recent join
	Joins: number,
	Seconds: number, -- Total playtime
}

export type Template = {
	Stats: Stats,
	Flags: { [string]: boolean }, -- Example Collection; replace per game
	PURCHASED_ID_CACHE: { [string]: boolean },
}

local Template = {
	Stats = {
		First = 0,
		Last = 0,
		Joins = 0,
		Seconds = 0,
	},
	Flags = Collection({}),
	PURCHASED_ID_CACHE = Private({}),
} :: Template

-- One-time walk: records marked paths, strips the markers from the table above
local Meta = Schema.Build(Template :: any)

export type Profile = typeof(Template)

return {
	Version = VERSION,
	Event = Event,
	Template = Template,
	Paths = Meta.Paths,
	Private = Meta.Private,
	Valid = Meta.Valid,
}

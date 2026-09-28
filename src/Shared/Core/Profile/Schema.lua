--!strict
--[[
	Schema — template markers and one-time walk.

	Wrap template fields at their definition site:
	  Collection(t) — diffed as Added/Changed/Removed ops and sent via Profile.Delta
	  Private(t)    — server-only; stripped from Synced and never diffed (top-level only)

	Build() records each marked node's dot-path, unwraps the markers, and returns
	derived indexes. Replaces the hand-written PATHS array, PATHS.lua, and the
	Observer Directory — the template is the single source of truth.
]]

local MARK = "__MARK" -- Sentinel key set on marked template tables, removed by Build

export type Paths = {
	TOP: { [string]: string }, -- Top-level collection key -> path
	SUB: { [string]: { [string]: string } }, -- Top key -> sub key -> full path
	ALL: { [string]: string }, -- Every collection path
}

export type Meta = {
	Paths: Paths,
	Private: { [string]: boolean }, -- Top-level keys that never leave the server
	Valid: { [string]: boolean }, -- Every subscribable dot-path (for typo warnings)
}

local Schema = {}

-- Marks a table as a diffable collection (dynamic keys; client receives ops)
function Schema.Collection(entry: { [any]: any }): any
	entry[MARK] = "Collection"
	return entry
end

-- Marks a top-level table as server-only (never synced to the client)
function Schema.Private(entry: { [any]: any }): any
	entry[MARK] = "Private"
	return entry
end

-- Walks the template once: records marked paths, unwraps markers in place
function Schema.Build(template: { [string]: any }): Meta
	local meta: Meta = {
		Paths = { TOP = {}, SUB = {}, ALL = {} },
		Private = {},
		Valid = { Changed = true }, -- Global catch-all fired on every Synced/Delta
	}

	local function walk(node: { [any]: any }, path: string?, depth: number, hidden: boolean)
		for key, value in pairs(node) do
			if key == MARK then
				continue
			end

			local full = if path then `{path}.{key}` else tostring(key)

			-- Observer only fires top and second-level paths; deeper ones never signal
			if not hidden and depth <= 2 then
				meta.Valid[full] = true
			end

			if type(value) ~= "table" then
				continue
			end

			local mark = value[MARK]
			value[MARK] = nil

			if mark == "Private" then
				assert(depth == 1, `[Schema] Private("{full}") must be a top-level field`)
				meta.Private[full] = true
				meta.Valid[full] = nil
				walk(value, full, depth + 1, true)
			elseif mark == "Collection" then
				assert(depth <= 2, `[Schema] Collection("{full}") nests too deep — top or second level only`)
				if not hidden then
					if depth == 1 then
						meta.Paths.TOP[full] = full
					else
						local top = path :: string
						if not meta.Paths.SUB[top] then
							meta.Paths.SUB[top] = {}
						end
						meta.Paths.SUB[top][key] = full
					end
					meta.Paths.ALL[full] = full
				end
				-- Collection contents are player data (dynamic keys), not schema —
				-- recurse only to strip stray markers, without recording paths.
				walk(value, full, depth + 1, true)
			else
				walk(value, full, depth + 1, hidden)
			end
		end
	end

	walk(template, nil, 1, false)

	table.freeze(meta.Private)
	table.freeze(meta.Valid)
	table.freeze(meta.Paths.TOP)
	table.freeze(meta.Paths.SUB)
	table.freeze(meta.Paths.ALL)

	return meta
end

return Schema

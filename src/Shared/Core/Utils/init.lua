--!strict

local function Clone(t: { [any]: any }, deep: boolean?): { [any]: any }
	if not deep then
		return table.clone(t)
	end

	local function deepCopy(tbl: { [any]: any }): { [any]: any }
		local copy = table.clone(tbl)
		for k, v in copy do
			if type(v) == "table" then
				copy[k] = deepCopy(v)
			end
		end
		return copy
	end

	return deepCopy(t)
end

local function Freeze(t: { [any]: any }, deep: boolean?)
	if not deep then
		table.freeze(t)
		return
	end

	if not table.isfrozen(t) then
		table.freeze(t)
	end

	for _, v in t do
		if type(v) == "table" and not table.isfrozen(v) then
			Freeze(v, true)
		end
	end
end

local function Nested(root: any, path: string): { [string]: any }?
	local current: any = root
	for part in string.gmatch(path, "[^%.]+") do
		if type(current) ~= "table" then
			return nil
		end
		current = current[part]
	end
	return if type(current) == "table" then current :: { [string]: any } else nil
end

local Match: (any, any, any) -> boolean
local Same: (any, any) -> boolean

function Match(table1: any, table2: any, key: any): boolean
	if table2[key] == nil then
		return false
	end

	if typeof(table1[key]) ~= typeof(table2[key]) then
		return false
	end

	if typeof(table1[key]) == "table" then
		return Same(table1[key], table2[key])
	end

	return table1[key] == table2[key]
end

function Same(table1: any, table2: any): boolean
	if not table1 or not table2 then
		return false
	end

	for key in table1 do
		if not Match(table1, table2, key) then
			return false
		end
	end

	for key in table2 do
		if not Match(table2, table1, key) then
			return false
		end
	end

	return true
end

local function Equal(a: any, b: any): boolean
	if type(a) ~= type(b) then
		return false
	end
	if type(a) == "table" then
		return Same(a, b)
	end
	return a == b
end

return {
	Clone = Clone,
	Freeze = Freeze,
	Nested = Nested,
	Equal = Equal,

	Lerp = require(script.Lerp),
	Formatter = require(script.Formatter),
	Numba = require(script.Numba),
}

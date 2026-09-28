--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local Profile = require(ServerScriptService.Systems.Profile)

local function Tree(value: any, indent: number): string
	local pad = string.rep("  ", indent)

	if type(value) ~= "table" then
		if type(value) == "string" then
			return `"{value}"`
		end
		return tostring(value)
	end

	local keys = {}
	for k in pairs(value) do
		table.insert(keys, k)
	end

	if #keys == 0 then
		return "{}"
	end

	table.sort(keys, function(a, b)
		local na, nb = type(a) == "number", type(b) == "number"
		if na and nb then
			return (a :: number) < (b :: number)
		end
		if na then
			return true
		end
		if nb then
			return false
		end
		return tostring(a) < tostring(b)
	end)

	local lines = {}
	for _, k in ipairs(keys) do
		local child = Tree(value[k], indent + 1)
		local label = type(k) == "number" and `[{k}]` or tostring(k)
		if string.sub(child, 1, 1) == "\n" then
			table.insert(lines, `{pad}  {label}:{child}`)
		else
			table.insert(lines, `{pad}  {label}: {child}`)
		end
	end

	return "\n" .. table.concat(lines, "\n")
end

return function(context, mode: number)
	local player = context.Executor
	local data = Profile:Get(player, false)
	if not data then
		return `No profile loaded for {player.Name}.`
	end

	mode = math.floor(mode)
	if mode ~= 1 then
		print(`[PrintProfile] {player.Name}:`, data)
		return `Printed {player.Name}'s profile to Output.`
	end

	context:Reply(`Profile for {player.Name}:`)
	local keys = {}
	for k in pairs(data :: any) do
		table.insert(keys, k)
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)

	for _, key in ipairs(keys) do
		local branch = Tree((data :: any)[key], 0)
		if string.sub(branch, 1, 1) == "\n" then
			context:Reply(`{key}:{branch}`)
		else
			context:Reply(`{key}: {branch}`)
		end
	end

	return ""
end

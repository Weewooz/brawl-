--!strict
--[[
	Framework — Lightweight system-lifecycle framework.

	Lifecycle:
	  1. Register systems with Framework:Add(folder). Each ModuleScript whose name
	     matches Features.lua is validated (must be Enabled). Duplicate names under
	     a deep Add keep the shallowest ModuleScript (world systems beat nested UI).
	  2. Call Framework:Start() to boot. Systems run in two ordered phases:
	       Init  — called sequentially in ascending Priority order.
	       Start  — called in parallel (task.spawn) after all setups succeed.
	     If any Init fails, the entire startup is aborted and Start is skipped.
	  3. Framework.Loaded fires after all Start calls have been dispatched.
	  4. Framework.Started() returns a Promise that resolves once loading completes.

	Priority:
	  Lower number = earlier execution. Default is 10. Configured per-system
	  in Features.lua under Client / Server tables.

	Error handling:
	  Both phases use xpcall + debug.traceback so failures produce full stack
	  traces prefixed with "[Framework]" for easy filtering in Output.
	  Set Features.DebugLog = true for skipped-registration and timing messages.

	API:
	  Framework:Add(storage, deep?)  — register systems from a Folder/Model
	  Framework:Start()              — returns Promise; runs Init then Start
	  Framework.Started()            — returns Promise that resolves when loading is done
	  Framework.Loaded               — Signal that fires once after startup completes
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Promise = require(ReplicatedStorage.Packages.Promise)
local Signal = require(ReplicatedStorage.Packages.Signal)
local Features = require(ReplicatedStorage.Shared.Core.Framework.Features)

local SERVER = RunService:IsServer()
local CONTEXT = SERVER and "Server" or "Client"

export type System = {
	Name: string?,
	Init: (System) -> (),
	Start: (System) -> (),
	Priority: number?,
}

local DEFAULT_PRIORITY = 10

local function Debugging(): boolean
	return Features.Debug == true
end

export type Framework = {
	_Systems: { [string]: System },

	Loaded: Signal.Signal<nil>,

	Add: (self: Framework, storage: Folder | Model, deep: boolean?) -> (),

	Start: (self: Framework) -> Promise.Promise,
	Started: () -> (),
}

local Framework = {} :: Framework
Framework._Systems = {}
Framework.Loaded = Signal.new()

local STARTED: boolean = false
local COMPLETED: boolean = false

local function Traceback(err: any): string
	return debug.traceback(tostring(err), 2)
end

-- Hops from storage to the ModuleScript. Direct children are 0.
local function Depth(object: Instance, root: Instance): number
	local depth = 0
	local current: Instance? = object.Parent
	while current and current ~= root do
		depth += 1
		current = current.Parent
	end
	return depth
end

function Framework:Add(storage: Folder | Model, deep: boolean?)
	if STARTED then
		error("[Framework] Cannot add systems — Framework has already started", 2)
	end

	local group = SERVER and Features.Server or Features.Client
	local pending: { { Name: string, Object: ModuleScript, Priority: number, Depth: number } } = {}
	local listed: { [string]: number } = {}
	local array: { Instance } = deep and storage:GetDescendants() or storage:GetChildren()
	for _, object: Instance in array do
		if not object:IsA("ModuleScript") then
			continue
		end

		local featureGroup = group[object.Name]
		if not featureGroup then
			if Debugging() then
				warn(
					("[Framework] Cannot add system '%s' — feature is not defined in Features.%s"):format(
						object.Name,
						CONTEXT
					)
				)
			end
			continue
		elseif featureGroup.Enabled == false then
			if Debugging() then
				warn(("[Framework] Cannot add system '%s' — feature is disabled"):format(object.Name))
			end
			continue
		elseif self._Systems[object.Name] then
			warn(("[Framework] Cannot add system '%s' — already registered"):format(object.Name))
			continue
		elseif listed[object.Name] then
			local prior = pending[listed[object.Name]]
			local depth = Depth(object, storage)
			local keep = if depth < prior.Depth then object else prior.Object
			local drop = if keep == object then prior.Object else object
			warn(
				("[Framework] Multiple ModuleScripts named '%s'; using %s, ignoring %s"):format(
					object.Name,
					keep:GetFullName(),
					drop:GetFullName()
				)
			)
			if keep == object then
				prior.Object = object
				prior.Depth = depth
			end
			continue
		end

		listed[object.Name] = #pending + 1
		table.insert(pending, {
			Name = object.Name,
			Object = object,
			Priority = featureGroup.Priority or DEFAULT_PRIORITY,
			Depth = Depth(object, storage),
		})
	end

	table.sort(pending, function(a, b)
		if a.Priority ~= b.Priority then
			return a.Priority < b.Priority
		end
		return a.Name < b.Name
	end)

	for _, entry in pending do
		local loadOk, loaded = pcall(require, entry.Object)
		if not loadOk then
			warn(("[Framework] Failed to load system '%s':\n%s"):format(entry.Name, tostring(loaded)))
			continue
		end
		if typeof(loaded) ~= "table" or typeof((loaded :: any).Init) ~= "function" then
			warn(
				("[Framework] Cannot add system '%s' — module has no Init (%s)"):format(
					entry.Name,
					entry.Object:GetFullName()
				)
			)
			continue
		end
		local system = loaded :: System
		if not system.Name then
			system.Name = entry.Name
		end
		system.Priority = entry.Priority
		self._Systems[entry.Name] = system
	end
end

function Framework:Start(): Promise.Promise
	if STARTED then
		return Promise.Reject("[Framework] Already started")
	end
	STARTED = true

	local systemList: { { Name: string, System: System, Priority: number } } = {}

	for name, system: System in pairs(self._Systems) do
		table.insert(systemList, {
			Name = name,
			System = system,
			Priority = system.Priority :: number,
		})
	end

	table.sort(systemList, function(a, b)
		return a.Priority < b.Priority
	end)

	return Promise.new(function(Resolve)
		local setupFailed = false

		for _, data in ipairs(systemList) do
			local name = data.Name
			local system = data.System

			if typeof(system.Init) == "function" then
				debug.setmemorycategory(name .. " (Init)")

				local startTime = if Debugging() then os.clock() else nil

				local ok, err = xpcall(function()
					system:Init()
				end, Traceback)
				if not ok then
					setupFailed = true
					warn(("[Framework] Init failed for '%s':\n%s"):format(name, tostring(err)))
				elseif startTime and Debugging() then
					warn(("[Framework] Init '%s' (%.1fms)"):format(name, (os.clock() - startTime) * 1000))
				end
			end
		end

		if setupFailed then
			warn("[Framework] Startup aborted — one or more Init calls failed. Start will not run.")
			return
		end

		Resolve()
	end):Then(function()
		for _, data in ipairs(systemList) do
			local system = data.System
			local name = data.Name

			if typeof(system.Start) == "function" then
				task.spawn(function()
					debug.setmemorycategory(name .. " (Start)")

					local startTime = if Debugging() then os.clock() else nil

					local ok, err = xpcall(function()
						system:Start()
					end, Traceback)
					if not ok then
						warn(("[Framework] Start failed for '%s':\n%s"):format(name, tostring(err)))
					elseif startTime and Debugging() then
						warn(("[Framework] Start '%s' (%.1fms)"):format(name, (os.clock() - startTime) * 1000))
					end
				end)
			end
		end

		COMPLETED = true
		self.Loaded:Fire()
	end)
end

function Framework.Started()
	if COMPLETED then
		return Promise.Resolve()
	end
	return Promise.new(function(Resolve)
		Framework.Loaded:Once(function()
			Resolve()
		end)
	end)
end

return Framework

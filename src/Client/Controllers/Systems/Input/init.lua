--!strict
local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")

local Request = require(script.Request)

local ATTRIBUTE = "CONTROL_ENABLED"
local CONTEXTS = "InputContexts"
local MOVEMENT = { "CharacterContext", "Character" }
local WAIT = 5 -- Timed wait so Roblox does not emit infinite-yield warnings

export type System = {
	Init: (self: System) -> (),
	Start: (self: System) -> (),
}

local System = {} :: System

local Player = Players.LocalPlayer
local Warned = false
local Cached: InputContext? = nil
local Controls: any = nil
local Locks: { [string]: boolean } = {}
local Bound = false

local function Find(parent: Instance): InputContext?
	local folder = parent:FindFirstChild(CONTEXTS)
	if not folder then
		return nil
	end

	for _, name in MOVEMENT do
		local context = folder:FindFirstChild(name)
		if context and context:IsA("InputContext") then
			return context
		end
	end

	return nil
end

local function ResolveContext(): InputContext?
	if Cached and Cached.Parent then
		return Cached
	end

	local scripts = Player:FindFirstChild("PlayerScripts")
	if scripts then
		local module = scripts:FindFirstChild("PlayerModule")
		if module then
			local context = Find(module)
			if context then
				Cached = context
				return context
			end
		end
	end

	local playerModule = StarterPlayer:FindFirstChild("PlayerModule")
	if playerModule then
		local context = Find(playerModule)
		if context then
			Cached = context
			return context
		end
	end

	local context = Find(Player)
	if context then
		Cached = context
		return context
	end

	return nil
end

local function ResolveControls(): any
	if Controls then
		return Controls
	end

	local scripts = Player:FindFirstChild("PlayerScripts")
	local module = scripts and scripts:FindFirstChild("PlayerModule")
	if not module then
		return nil
	end

	local ok, controls = pcall(function()
		return require(module):GetControls()
	end)
	if ok and controls then
		Controls = controls
		return controls
	end

	return nil
end

local function Apply(enabled: boolean)
	local context = ResolveContext()
	if context then
		context.Enabled = enabled
		return
	end

	local controls = ResolveControls()
	if not controls then
		return
	end

	if enabled then
		if controls.Enable then
			controls:Enable()
		end
	elseif controls.Disable then
		controls:Disable()
	end
end

local function Sync()
	local attribute = Player:GetAttribute(ATTRIBUTE) ~= false
	local locked = next(Locks) ~= nil
	Apply(attribute and not locked)
end

local function Lock(key: string)
	if key == "" then
		return
	end
	Locks[key] = true
	Sync()
	if next(Locks) and ResolveContext() == nil and ResolveControls() == nil then
		task.defer(Sync)
	end
end

local function Unlock(key: string)
	if key == "" then
		return
	end
	Locks[key] = nil
	Sync()
	if next(Locks) == nil then
		task.defer(Sync)
	end
end

local function EnsureContext(): InputContext?
	local playerModule = StarterPlayer:WaitForChild("PlayerModule", WAIT)
	if not playerModule then
		return nil
	end

	local folder = playerModule:WaitForChild(CONTEXTS, WAIT)
	if not folder then
		return nil
	end

	for _, name in MOVEMENT do
		local context = folder:WaitForChild(name, WAIT)
		if context and context:IsA("InputContext") then
			return context
		end
	end

	return nil
end

local function Bind()
	if Bound then
		return
	end
	Bound = true

	Request.Lock:Callback(Lock)
	Request.Unlock:Callback(Unlock)

	Player:GetAttributeChangedSignal(ATTRIBUTE):Connect(Sync)

	Player.CharacterAdded:Connect(function()
		task.defer(Sync)
	end)

	task.spawn(function()
		local playerModule = StarterPlayer:WaitForChild("PlayerModule", WAIT)
		if playerModule then
			playerModule.ChildAdded:Connect(function(child)
				if child.Name == CONTEXTS then
					Cached = nil
					task.defer(Sync)
				end
			end)
		end

		local context = EnsureContext()
		if context then
			Cached = context
			Sync()
			return
		end

		if ResolveControls() then
			Sync()
			return
		end

		if not Warned then
			Warned = true
			warn("[Input] CharacterContext and PlayerModule controls unavailable")
		end
	end)
end

function System:Init()
	Bind()
end

function System:Start() end

return System

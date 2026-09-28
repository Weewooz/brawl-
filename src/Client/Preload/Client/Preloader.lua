--!strict
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local Players = game:GetService("Players")
local Player = Players.LocalPlayer

local Packages = ReplicatedStorage:WaitForChild("Packages", 120)
if not Packages then
	error("[Preloader] ReplicatedStorage.Packages was not ready in time")
end

local Future = require(Packages.Future)
local Signal = require(Packages.Signal)

local DEBUGGING = false

export type Preloader = {
	__index: Preloader,
	Load: (self: Preloader) -> typeof(Future.new(function() end)),
	Destroy: (self: Preloader) -> (),

	Items: { Instance },
	Loaded: Signal.Signal<Instance>,
}
local Class: Preloader = {} :: Preloader
Class.__index = Class

function Class:Load()
	self.Loaded = Signal.new()

	local assets = ReplicatedFirst:FindFirstChild("Preload")
	self.Items = assets and assets:GetChildren() or {}

	return Future.new(function()
		local startTime = os.clock()
		for _, item in pairs(self.Items) do
			if item:IsA("GuiObject") then
				ContentProvider:PreloadAsync({ item })
			end
			self.Loaded:Fire(item)

			task.wait()
		end
		local deltaTime = os.clock() - startTime

		local playerGui = Player:WaitForChild("PlayerGui")
		for _, item in pairs(self.Items) do
			item.Parent = StarterGui
			local new = item:Clone()

			new.Parent = playerGui
		end

		if DEBUGGING then
			warn("Preloading took", deltaTime, "seconds to load", #self.Items, "assets.")
		end
	end)
end

function Class:Destroy()
	self.Items = {}
	self.Loaded:DisconnectAll()
end

return Class

--!strict
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fade = require(ReplicatedStorage:WaitForChild("Client"):WaitForChild("Modules"):WaitForChild("Fade"))
local Preloader = require(script.Preloader)

ReplicatedFirst:RemoveDefaultLoadingScreen()
Fade.Bind()

Preloader:Load():After(function()
	print("✅ | Preloaded Assets!")
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end

	local framework = require(ReplicatedStorage.Shared.Core.Framework)
	framework:Add(ReplicatedStorage.Client.Controllers.Systems, true)

	framework
		:Start()
		:Then(function()
			print("⭕| Client loaded!")
		end)
		:Catch(warn)
		:Await()
end)

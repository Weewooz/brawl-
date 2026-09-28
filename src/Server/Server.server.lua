--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Framework = require(ReplicatedStorage.Shared.Core.Framework)
Framework:Add(ServerScriptService.Systems, true)

Framework:Start()
	:Then(function()
		print("⭕| Server loaded!")
	end)
	:Catch(warn)
	:Await()

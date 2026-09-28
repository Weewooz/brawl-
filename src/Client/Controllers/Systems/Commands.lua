--!strict
--[[
	Commands (client) — requires CmdrClient after the server parents it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type System = {
	Init: (self: System) -> (),
	Start: (self: System) -> (),
}

local System = {} :: System

function System:Init()
	local Cmdr = require(ReplicatedStorage:WaitForChild("CmdrClient") :: any) :: any
	Cmdr:SetActivationKeys({ Enum.KeyCode.F2 })
end

function System:Start() end

return System

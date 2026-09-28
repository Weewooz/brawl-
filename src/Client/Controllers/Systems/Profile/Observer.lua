--!strict
--[[
	Observer — per-path signals for profile updates.

	No name directory: signals are created lazily for any dot-path string
	(e.g. "Currencies", "Inventory.Weapons", "Changed"). Template.Valid — derived
	from the template walk — warns about typos in Studio, replacing the
	safety the hand-written Directory used to provide.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Signal = require(ReplicatedStorage.Packages.Signal)
local Template = require(ReplicatedStorage.Shared.Core.Profile.Template)

type Signal = Signal.Signal<any>
type Connection = Signal.Connection

export type Type = {
	Subscribe: (path: string, callback: (value: any) -> ()) -> Connection?,
	Fire: (path: string, value: any) -> (),
}

local Signals: { [string]: Signal } = {}

local Observer = {} :: Type

Observer.Subscribe = function(path: string, callback: (value: any) -> ()): Connection?
	if typeof(callback) ~= "function" then
		return nil
	end
	if RunService:IsStudio() and not Template.Valid[path] then
		warn(`[Profile] Subscribed to unknown path "{path}"`)
	end

	local signal = Signals[path]
	if not signal then
		signal = Signal.new()
		Signals[path] = signal
	end
	return signal:Connect(callback)
end

-- Fires only if someone subscribed; unwatched paths cost nothing
Observer.Fire = function(path: string, value: any)
	local signal = Signals[path]
	if signal then
		signal:Fire(value)
	end
end

return Observer

--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Packages.Signal)

export type Channel<T> = {
	Callback: (self: Channel<T>, callback: (T) -> ()) -> Signal.Connection,
	Invoke: (self: Channel<T>, args: T) -> (),
}

local function Channel<T>(): Channel<T>
	local signal = Signal.new()
	return {
		Callback = function(_, callback: (T) -> ())
			return signal:Connect(callback)
		end,
		Invoke = function(_, args: T)
			signal:Fire(args)
		end,
	}
end

-- Keyed movement locks: CharacterContext stays disabled while any key is held.
local Request = {
	Lock = Channel() :: Channel<string>,
	Unlock = Channel() :: Channel<string>,
}

return Request

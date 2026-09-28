--!strict
local Players = game:GetService("Players")

local PlayerUtilities = {}

function PlayerUtilities.ListenPlayerAdded(callback: (player: Player) -> ())
	Players.PlayerAdded:Connect(function(player: Player)
		callback(player)
	end)

	for _, player: Player in Players:GetPlayers() do
		callback(player)
	end
end

function PlayerUtilities.ListenCharacterAdded(callback: (character: Model, player: Player) -> ())
	PlayerUtilities.ListenPlayerAdded(function(player: Player)
		player.CharacterAdded:Connect(function(character: Model)
			callback(character, player)
		end)

		if player.Character then
			callback(player.Character, player)
		end
	end)
end

return PlayerUtilities

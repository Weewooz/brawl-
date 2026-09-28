--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local Profile = require(ServerScriptService.Systems.Profile)

return function(context)
	local player = context.Executor
	if not Profile:Get(player, false) then
		return `No profile loaded for {player.Name}.`
	end

	Profile:Reset(player)
	return `Reset profile for {player.Name} (session ended).`
end

--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local Notifications = require(ServerScriptService.Systems.Notifications)

return function(context, text: string, duration: number?)
	Notifications:Show(context.Executor, text, {
		Duration = duration,
	})
	return "Displayed the notification."
end

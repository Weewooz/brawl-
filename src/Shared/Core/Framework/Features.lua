--!strict

export type Flags = {
	--- Verbose output: skipped registrations, phase timings. Failures always warn.
	Debug: boolean?,
	Client: {
		[string]: {
			Enabled: boolean,
			Priority: number,
		},
	},
	Server: {
		[string]: {
			Enabled: boolean,
			Priority: number,
		},
	},
}

-- Keys must match ModuleScript names under Client.Controllers.Systems (client)
-- and ServerScriptService.Systems (server). See Framework:Add in entry scripts.
return {
	Debug = false,
	Client = {
		Profile = { Enabled = true, Priority = 1 },
		Camera = { Enabled = true, Priority = 3 },
		Combat = { Enabled = true, Priority = 4 },
		Dungeon = { Enabled = true, Priority = 5 },
		Capture = { Enabled = true, Priority = 5 },
		Input = { Enabled = true, Priority = 3 },
		Cooldowns = { Enabled = true, Priority = 3 },
		Commands = { Enabled = true, Priority = 3 },
		Latency = { Enabled = true, Priority = 5 },
		Reconnection = { Enabled = true, Priority = 5 },
	},
	Server = {
		Notifications = { Enabled = true, Priority = 1 },
		Profile = { Enabled = true, Priority = 1 },
		Combat = { Enabled = true, Priority = 3 },
		Dungeon = { Enabled = true, Priority = 4 },
		Capture = { Enabled = true, Priority = 4 },
		Commands = { Enabled = true, Priority = 3 },
		Latency = { Enabled = true, Priority = 5 },
		Reconnection = { Enabled = true, Priority = 5 },
	},
} :: Flags

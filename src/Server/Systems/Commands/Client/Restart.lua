--!strict
return {
	Name = "RestartServer",
	Description = "Teleport everyone to a fresh server and shut this one down.",
	Group = "Admin",
	Args = {
		{
			Type = "number",
			Name = "Delay",
			Description = "Seconds to wait before teleporting.",
			Optional = true,
		},
	},
}

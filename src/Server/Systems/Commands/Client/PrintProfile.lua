--!strict
return {
	Name = "printprofile",
	Description = "Dump your profile (0 = Output print, 1 = Cmdr tree).",
	Group = "Admin",
	Args = {
		{
			Type = "number",
			Name = "Mode",
			Description = "0 = Studio Output, 1 = Cmdr tree.",
			Optional = true,
			Default = 0,
		},
	},
}

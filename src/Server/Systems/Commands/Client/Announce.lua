--!strict
return {
	Name = "Announce",
	Description = "Show a notification to yourself.",
	Group = "Admin",
	Args = {
		{
			Type = "string",
			Name = "Text",
			Description = "Notification text. Use quotes for spaces.",
		},
		{
			Type = "number",
			Name = "Duration",
			Description = "How long the notification remains visible.",
			Optional = true,
		},
	},
}

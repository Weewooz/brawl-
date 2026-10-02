--!strict

export type Palette = {
	Amber: string,
	Black: string,
	Blue: string,
	Gold: string,
	Green: string,
	Grey: string,
	Purple: string,
	Red: string,
	Teal: string,
}

export type Library = {
	Frames: { Gold: string },
	Backgrounds: {
		Washi: Palette,
		Vintage: Palette,
	},
}

local SkillAssets: Library = table.freeze({
	Frames = table.freeze({
		Gold = "rbxassetid://71502945814007",
	}),
	Backgrounds = table.freeze({
		Washi = table.freeze({
			Amber = "rbxassetid://73592488866229",
			Black = "rbxassetid://106673974330758",
			Blue = "rbxassetid://85601907082374",
			Gold = "rbxassetid://104345496505935",
			Green = "rbxassetid://79220966729439",
			Grey = "rbxassetid://81487382219486",
			Purple = "rbxassetid://106801642554970",
			Red = "rbxassetid://99134915816391",
			Teal = "rbxassetid://139751609122567",
		}),
		Vintage = table.freeze({
			Amber = "rbxassetid://121264564557087",
			Black = "rbxassetid://113222518558676",
			Blue = "rbxassetid://116238389011147",
			Gold = "rbxassetid://75402199872143",
			Green = "rbxassetid://75283204197360",
			Grey = "rbxassetid://85088266716033",
			Purple = "rbxassetid://102306218626433",
			Red = "rbxassetid://81874933707089",
			Teal = "rbxassetid://107599855023793",
		}),
	}),
})

return SkillAssets

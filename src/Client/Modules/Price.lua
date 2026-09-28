--!strict
-- Robux product price for world prompts. Cached GetProductInfoAsync.

local MarketplaceService = game:GetService("MarketplaceService")

export type Module = {
	Line: (self: Module, amount: number) -> string,
	Robux: (self: Module, productId: number?, paint: (number) -> ()) -> (),
}

local Price = {} :: Module

local ROBUX = "\u{E002}" -- Roblox Robux glyph
local Cache: { [number]: number } = {}

function Price:Line(amount: number): string
	return `Buy · {amount} {ROBUX}`
end

function Price:Robux(productId: number?, paint: (number) -> ())
	if not productId or productId <= 0 then
		return
	end
	local cached = Cache[productId]
	if cached then
		paint(cached)
		return
	end
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfoAsync(productId, Enum.InfoType.Product)
		end)
		if not ok or type(info) ~= "table" then
			return
		end
		local amount = (info :: any).PriceInRobux
		if typeof(amount) ~= "number" then
			return
		end
		Cache[productId] = amount
		paint(amount)
	end)
end

return Price

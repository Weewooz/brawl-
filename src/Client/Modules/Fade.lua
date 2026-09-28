--!strict
-- CollectionService observer for water/debris fade. Bound early from ReplicatedFirst
-- before Framework Init so parts tagged while preloading still tween.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Tags = require(ReplicatedStorage.Shared.Core.Tags)

local ATTR = "Fade"
local Bound = false

local function Tween(part: Instance)
	if not part:IsA("BasePart") or not part.Parent then
		return
	end

	local raw = part:GetAttribute(ATTR)
	local duration = if typeof(raw) == "number" then raw else 0.2

	TweenService:Create(
		part,
		TweenInfo.new(math.max(duration, 0), Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ LocalTransparencyModifier = 1 }
	):Play()
end

local Fade = {}

function Fade.Bind()
	if Bound then
		return
	end
	Bound = true

	for _, part in CollectionService:GetTagged(Tags.Fade) do
		Tween(part)
	end
	CollectionService:GetInstanceAddedSignal(Tags.Fade):Connect(Tween)
end

return Fade

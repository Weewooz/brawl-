--!strict
local Players = game:GetService("Players")

type Contribution = { At: number, Round: number }
local Outcomes = {}
local Hits: { [Model]: { [Player]: Contribution } } = setmetatable({}, { __mode = "k" }) :: any
local Last: { [Model]: Player } = setmetatable({}, { __mode = "k" }) :: any
local ASSIST_WINDOW = 8

function Outcomes.Record(attacker: Model, target: Model, now: number)
	local player = Players:GetPlayerFromCharacter(attacker)
	if attacker:GetAttribute("CaptureActive") ~= true or target:GetAttribute("CaptureActive") ~= true then
		return
	end
	Last[target] = player
	if not player then
		return
	end
	local contributors = Hits[target]
	if not contributors then
		contributors = {}
		Hits[target] = contributors
	end
	contributors[player] = { At = now, Round = player:GetAttribute("CaptureRound") or 0 }
end

function Outcomes.Finish(target: Model, now: number)
	local contributors = Hits[target]
	local killer = Last[target]
	Hits[target] = nil
	Last[target] = nil
	if not contributors then
		return
	end
	for player, contribution in contributors do
		if
			player.Parent == Players
			and player:GetAttribute("CaptureStatus") == "Playing"
			and contribution.Round == player:GetAttribute("CaptureRound")
			and now - contribution.At <= ASSIST_WINDOW
		then
			local attribute = if player == killer then "CaptureKills" else "CaptureAssists"
			player:SetAttribute(attribute, (player:GetAttribute(attribute) or 0) + 1)
		end
	end
end

function Outcomes.Clear(target: Model)
	Hits[target] = nil
	Last[target] = nil
end

return Outcomes

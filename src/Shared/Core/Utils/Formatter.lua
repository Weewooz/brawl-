function Time(seconds: number, level: number?): string
	level = level or 2
	local s = math.max(0, math.floor(seconds))

	local months = math.floor(s / (30 * 24 * 3600))
	s = s % (30 * 24 * 3600)
	local days = math.floor(s / (24 * 3600))
	s = s % (24 * 3600)
	local hours = math.floor(s / 3600)
	s = s % 3600
	local minutes = math.floor(s / 60)
	local secs = s % 60

	if level < 0 then
		if months > 0 then
			level = 6
		elseif days > 0 then
			level = 4
		elseif hours > 0 then
			level = 3
		elseif minutes > 0 then
			level = 2
		else
			level = 1
		end
	end

	local parts = {}

	if level >= 6 and months > 0 then
		table.insert(parts, string.format("%02d", months))
	end
	if level >= 5 and (days > 0 or #parts > 0) then
		table.insert(parts, string.format("%02d", days))
	end
	if level >= 4 and (hours > 0 or #parts > 0) then
		table.insert(parts, string.format("%02d", hours))
	elseif level == 3 then
		table.insert(parts, string.format("%02d", hours))
	end
	if level >= 2 and (minutes > 0 or #parts > 0) then
		table.insert(parts, string.format("%02d", minutes))
	elseif level == 2 then
		table.insert(parts, string.format("%02d", minutes))
	end
	table.insert(parts, string.format("%02d", secs))

	-- Control how many fields to display based on level
	if level == 1 then
		return string.format("%02d", secs)
	elseif level == 2 then
		return string.format("%02d:%02d", minutes, secs)
	elseif level == 3 then
		return string.format("%02d:%02d:%02d", hours, minutes, secs)
	elseif level == 4 then
		return string.format("%02d:%02d:%02d:%02d", days, hours, minutes, secs)
	elseif level == 5 then
		-- legacy: dynamic/variable-width output including days (and higher if requested)
		return table.concat(parts, ":")
	elseif level == 6 then
		return string.format("%02d:%02d:%02d:%02d:%02d", months, days, hours, minutes, secs)
	else
		-- fallback, show as much as possible (up to months)
		return table.concat(parts, ":")
	end
end

return {
	Time = Time,
}

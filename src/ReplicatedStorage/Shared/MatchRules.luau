--!strict
-- Pure match rules shared by the server and the pilot checks.
-- Pad positions, participant selection, and pad assignment do not touch instances.

export type Candidate = {
	userId: number,
	inZone: boolean,
	waitStartedAt: number,
}

export type PlanePoint = {
	x: number,
	z: number,
}

export type IntRng = {
	NextInteger: (any, number, number) -> number,
}

local MatchRules = {}

function MatchRules.padPoints(count: number, radius: number): {PlanePoint}
	local points = table.create(count)
	for index = 1, count do
		local angle = (index - 1) / count * math.pi * 2
		points[index] = {
			x = math.cos(angle) * radius,
			z = math.sin(angle) * radius,
		}
	end
	return points
end

function MatchRules.minimumEdgeGap(points: {PlanePoint}, diameter: number): number
	local nearest = math.huge
	for index = 1, #points do
		local nextPoint = points[index % #points + 1]
		local point = points[index]
		local dx = point.x - nextPoint.x
		local dz = point.z - nextPoint.z
		local centerDistance = math.sqrt(dx * dx + dz * dz)
		if centerDistance < nearest then
			nearest = centerDistance
		end
	end
	return nearest - diameter
end

-- Earliest continuous wait, then smaller UserId. In-zone only, capped at max.
-- Fewer than min returns an empty list so a 0-person cycle does not start a match.
function MatchRules.selectParticipants(candidates: {Candidate}, maxParticipants: number, minParticipants: number): {number}
	local waiting = {}
	for _, candidate in ipairs(candidates) do
		if candidate.inZone then
			table.insert(waiting, candidate)
		end
	end
	table.sort(waiting, function(a, b)
		if a.waitStartedAt ~= b.waitStartedAt then
			return a.waitStartedAt < b.waitStartedAt
		end
		return a.userId < b.userId
	end)
	local selected = {}
	local limit = math.min(maxParticipants, #waiting)
	for index = 1, limit do
		selected[index] = waiting[index].userId
	end
	if #selected < minParticipants then
		return {}
	end
	return selected
end

function MatchRules.assignPads(userIds: {number}, padCount: number, random: IntRng): {[number]: number}
	assert(#userIds <= padCount, "More participants than pads")
	local pads = table.create(padCount)
	for index = 1, padCount do
		pads[index] = index
	end
	for index = padCount, 2, -1 do
		local swapIndex = random:NextInteger(1, index)
		pads[index], pads[swapIndex] = pads[swapIndex], pads[index]
	end
	local assignment = {}
	for order = 1, #userIds do
		assignment[userIds[order]] = pads[order]
	end
	return assignment
end

local function contains(list: {number}, userId: number): boolean
	return table.find(list, userId) ~= nil
end

local function constantRng(): IntRng
	return {
		NextInteger = function(_self, min: number, _max: number): number
			return min
		end,
	}
end

function MatchRules.selfCheck(constants: any)
	local match = constants.Match
	local arena = constants.Arena
	assert(match.MinParticipants == 1 and match.MaxParticipants == 12)
	assert(match.PlaySeconds == 120 and match.ResultSeconds == 30 and match.RestSeconds == 30)
	assert(math.abs(arena.PadCenterRadius - 30.91) < 0.01)
	local points = MatchRules.padPoints(match.MaxParticipants, arena.PadCenterRadius)
	assert(#points == 12)
	local gap = MatchRules.minimumEdgeGap(points, arena.PadDiameter)
	assert(math.abs(gap - arena.PadGap) < 0.001, `pad gap {gap}`)
	assert(arena.PadCenterRadius + arena.PadDiameter / 2 <= arena.Diameter / 2)

	local solo = MatchRules.selectParticipants({
		{ userId = 7, inZone = true, waitStartedAt = 3 },
	}, match.MaxParticipants, match.MinParticipants)
	assert(#solo == 1 and solo[1] == 7, "solo join")

	local oneOfTwo = MatchRules.selectParticipants({
		{ userId = 2, inZone = false, waitStartedAt = 1 },
		{ userId = 9, inZone = true, waitStartedAt = 4 },
	}, match.MaxParticipants, match.MinParticipants)
	assert(#oneOfTwo == 1 and oneOfTwo[1] == 9, "only the player inside the circle")
	local oneMap = MatchRules.assignPads(oneOfTwo, match.MaxParticipants, constantRng())
	assert(oneMap[9] ~= nil and oneMap[2] == nil)

	local twelve = {}
	for index = 1, 12 do
		twelve[index] = { userId = 100 + index, inZone = true, waitStartedAt = index }
	end
	local all = MatchRules.selectParticipants(twelve, match.MaxParticipants, match.MinParticipants)
	assert(#all == 12)
	local padMap = MatchRules.assignPads(all, match.MaxParticipants, constantRng())
	local seen = {}
	for _, padIndex in padMap do
		assert(type(padIndex) == "number" and padIndex >= 1 and padIndex <= 12)
		assert(seen[padIndex] == nil, "duplicate pad")
		seen[padIndex] = true
	end
	local seenCount = 0
	for _ in seen do
		seenCount += 1
	end
	assert(seenCount == 12, "12 unique pads")

	local latestExcluded = {}
	for index = 1, 13 do
		latestExcluded[index] = { userId = index, inZone = true, waitStartedAt = index }
	end
	local firstTwelve = MatchRules.selectParticipants(latestExcluded, match.MaxParticipants, match.MinParticipants)
	assert(#firstTwelve == 12)
	assert(contains(firstTwelve, 1) and contains(firstTwelve, 12))
	assert(not contains(firstTwelve, 13), "13th waiter is excluded")

	local tiedAtCutoff = {}
	for index = 1, 11 do
		tiedAtCutoff[index] = { userId = 100 + index, inZone = true, waitStartedAt = 0 }
	end
	tiedAtCutoff[12] = { userId = 40, inZone = true, waitStartedAt = 10 }
	tiedAtCutoff[13] = { userId = 4, inZone = true, waitStartedAt = 10 }
	local tiePick = MatchRules.selectParticipants(tiedAtCutoff, match.MaxParticipants, match.MinParticipants)
	assert(#tiePick == 12)
	assert(contains(tiePick, 4) and not contains(tiePick, 40), "same wait time keeps the smaller UserId")

	local sameTime = {}
	for index = 1, 13 do
		sameTime[index] = { userId = 14 - index, inZone = true, waitStartedAt = 5 }
	end
	local samePick = MatchRules.selectParticipants(sameTime, match.MaxParticipants, match.MinParticipants)
	assert(#samePick == 12 and contains(samePick, 1) and not contains(samePick, 13))

	local nobody = MatchRules.selectParticipants({
		{ userId = 1, inZone = false, waitStartedAt = 0 },
	}, match.MaxParticipants, match.MinParticipants)
	assert(#nobody == 0, "empty cycle")
end

return MatchRules

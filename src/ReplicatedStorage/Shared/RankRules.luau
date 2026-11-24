--!strict
-- Global rank uses one finished-match best score. Ties share a place and the next place skips.

export type Entry = {
	userId: number,
	name: string?,
	score: number,
}

export type Placed = {
	userId: number,
	name: string,
	score: number,
	rank: number,
}

local RankRules = {}

function RankRules.recordOf(bestScore: any, ranked: any): (number?, boolean)
	if type(bestScore) ~= "number" or bestScore < 0 or bestScore % 1 ~= 0 or bestScore >= math.huge then
		return nil, false
	end
	if ranked == true then
		return bestScore, true
	end
	if bestScore > 0 then
		return bestScore, true
	end
	return nil, false
end

function RankRules.storedValue(previous: any, score: number): number?
	if type(previous) == "number" and previous >= score then
		return nil
	end
	return score
end

function RankRules.place(entries: {Entry}): {Placed}
	local placed: {Placed} = {}
	local rank = 1
	for index, entry in ipairs(entries) do
		if index > 1 and entry.score < entries[index - 1].score then
			rank = index
		end
		table.insert(placed, {
			userId = entry.userId,
			name = if type(entry.name) == "string" and entry.name ~= "" then entry.name else tostring(entry.userId),
			score = entry.score,
			rank = rank,
		})
	end
	return placed
end

function RankRules.selfCheck()
	local best = 0
	local ranked = false
	local function finish(score: number, finished: boolean)
		if not finished then
			return
		end
		best = math.max(best, score)
		ranked = true
	end
	finish(100, true)
	assert(best == 100 and ranked, "the first finished match becomes the best score")
	finish(80, true)
	assert(best == 100, "a lower finished score does not replace the best")
	finish(120, true)
	assert(best == 120, "a higher finished score replaces the best")
	finish(150, false)
	assert(best == 120 and ranked, "practice does not change the global best")
	local noneScore, none = RankRules.recordOf(0, nil)
	assert(noneScore == nil and not none, "a legacy zero is not a finished record")
	local zeroScore, zero = RankRules.recordOf(0, true)
	assert(zeroScore == 0 and zero, "a finished zero is a record")
	local legacyScore, legacy = RankRules.recordOf(80, nil)
	assert(legacyScore == 80 and legacy, "a legacy positive best score is a record")
	assert(RankRules.storedValue(nil, 0) == 0, "the first record can be zero")
	assert(RankRules.storedValue(100, 80) == nil, "a lower score does not write the board")
	assert(RankRules.storedValue(100, 120) == 120, "a higher score replaces the board")
	assert(RankRules.storedValue(120, 120) == nil, "the same score does not write again")
	local rows = RankRules.place({
		{ userId = 1, name = "A", score = 120 },
		{ userId = 2, name = "B", score = 120 },
		{ userId = 3, name = "C", score = 100 },
	})
	assert(rows[1].rank == 1 and rows[2].rank == 1 and rows[3].rank == 3, "tied scores share a rank and the next rank skips")
end

return RankRules

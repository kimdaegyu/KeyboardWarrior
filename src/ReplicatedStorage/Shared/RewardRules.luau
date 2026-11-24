--!strict
-- Reward, level, and grant rules. Rates come from the sheets passed in, not from literals.

export type RewardRow = {
	Id: string,
	Gold: string,
	Exp: string,
}

export type LevelRow = {
	Id: string,
	TotalExp: string,
}

export type Rates = {
	wordGold: number,
	wordExp: number,
	sentenceGold: number,
	sentenceExp: number,
	completeGold: number,
	completeExp: number,
}

export type LevelStep = {
	level: number,
	totalExp: number,
}

export type Profile = {
	schemaVersion: number,
	gold: number,
	exp: number,
	bestScore: number,
	grants: {string}?,
	uiLocale: string?,
	gloss: string?,
	typing: string?,
	tutorialSeen: boolean?,
	ranked: boolean?,
	owned: {string}?,
	body: string?,
	rim: string?,
	effect: string?,
}

export type RankRow = {
	userId: number,
	score: number,
	rank: number,
}

local GRANT_LIMIT = 48

local RewardRules = {}

local function amount(value: string): number
	local parsed = tonumber(value)
	if type(parsed) ~= "number" or parsed < 0 or parsed % 1 ~= 0 then
		return 0
	end
	return parsed
end

function RewardRules.ratesFromRows(rows: {RewardRow}): Rates
	local found: {[string]: RewardRow} = {}
	for _, row in rows do
		found[row.Id] = row
	end
	local word = found.Word
	local sentence = found.Sentence
	local complete = found.Complete
	assert(word ~= nil and sentence ~= nil and complete ~= nil, "Reward sheet is missing a row")
	return {
		wordGold = amount(word.Gold),
		wordExp = amount(word.Exp),
		sentenceGold = amount(sentence.Gold),
		sentenceExp = amount(sentence.Exp),
		completeGold = amount(complete.Gold),
		completeExp = amount(complete.Exp),
	}
end

function RewardRules.levelsFromRows(rows: {LevelRow}): {LevelStep}
	local steps: {LevelStep} = {}
	for _, row in rows do
		local level = tonumber(row.Id)
		local total = tonumber(row.TotalExp)
		if type(level) == "number" and type(total) == "number" then
			table.insert(steps, { level = level, totalExp = total })
		end
	end
	table.sort(steps, function(a, b)
		return a.totalExp < b.totalExp
	end)
	return steps
end

function RewardRules.reward(rates: Rates, words: number, sentences: number, finished: boolean): (number, number)
	local gold = words * rates.wordGold + sentences * rates.sentenceGold
	local exp = words * rates.wordExp + sentences * rates.sentenceExp
	if finished and words + sentences >= 1 then
		gold += rates.completeGold
		exp += rates.completeExp
	end
	return gold, exp
end

function RewardRules.progress(exp: number, levels: {LevelStep}): (number, number, number?)
	local level = levels[1].level
	local floorExp = levels[1].totalExp
	local nextExp: number? = nil
	for _, step in levels do
		if step.totalExp <= exp then
			level = step.level
			floorExp = step.totalExp
			nextExp = nil
		elseif nextExp == nil then
			nextExp = step.totalExp
		end
	end
	return level, floorExp, nextExp
end

function RewardRules.settlementId(serverToken: string, matchId: number, nonce: string): string
	return serverToken .. ":" .. tostring(matchId) .. ":" .. nonce
end

function RewardRules.displayRows<T>(rows: {T}): {T}
	return table.clone(rows)
end

function RewardRules.profileAfterOpen(success: boolean, data: Profile?): Profile?
	if not success or data == nil then
		return nil
	end
	return data
end

function RewardRules.applyGrant(profile: Profile, settlementId: string, gold: number, exp: number, score: number, finished: boolean): (Profile, boolean)
	local grants: {string} = {}
	if type(profile.grants) == "table" then
		for _, id in profile.grants do
			if id == settlementId then
				return profile, false
			end
			table.insert(grants, id)
		end
	end
	table.insert(grants, settlementId)
	while #grants > GRANT_LIMIT do
		table.remove(grants, 1)
	end
	local best = profile.bestScore
	local ranked = profile.ranked == true
	if finished then
		best = math.max(best, score)
		ranked = true
	end
	local updated: Profile = {
		schemaVersion = profile.schemaVersion,
		gold = profile.gold + gold,
		exp = profile.exp + exp,
		bestScore = best,
		grants = grants,
	}
	if ranked then
		updated.ranked = true
	end
	if type(profile.uiLocale) == "string" then
		updated.uiLocale = profile.uiLocale
	end
	if type(profile.gloss) == "string" then
		updated.gloss = profile.gloss
	end
	if type(profile.typing) == "string" then
		updated.typing = profile.typing
	end
	if type(profile.tutorialSeen) == "boolean" then
		updated.tutorialSeen = profile.tutorialSeen
	end
	if type(profile.owned) == "table" then
		local owned: {string} = {}
		for _, id in profile.owned do
			if type(id) == "string" then
				table.insert(owned, id)
			end
		end
		updated.owned = owned
	end
	if type(profile.body) == "string" then
		updated.body = profile.body
	end
	if type(profile.rim) == "string" then
		updated.rim = profile.rim
	end
	if type(profile.effect) == "string" then
		updated.effect = profile.effect
	end
	return updated, true
end

function RewardRules.selfCheck(rewardRows: {RewardRow}, levelRows: {LevelRow})
	local rates = RewardRules.ratesFromRows(rewardRows)
	local levels = RewardRules.levelsFromRows(levelRows)
	assert(levels[1].level == 1 and levels[1].totalExp == 0, "level 1 starts at zero")

	local gold, exp = RewardRules.reward(rates, 2, 1, true)
	local againGold, againExp = RewardRules.reward(rates, 2, 1, true)
	assert(gold == againGold and exp == againExp, "x2 is not an input to the reward")
	assert(gold == rates.wordGold * 2 + rates.sentenceGold + rates.completeGold, "answer gold plus completion")
	assert(exp == rates.wordExp * 2 + rates.sentenceExp + rates.completeExp, "completion experience")
	if rates.wordGold == 1 and rates.sentenceGold == 4 and rates.completeGold == 50 and rates.wordExp == 0 and rates.sentenceExp == 0 and rates.completeExp == 10 then
		assert(gold == 56 and exp == 10, "sample sheet pays 56 gold and 10 exp")
	end

	local zeroGold, zeroExp = RewardRules.reward(rates, 0, 0, true)
	assert(zeroGold == 0 and zeroExp == 0, "a finished player with no answers is unpaid")
	local leaveGold, leaveExp = RewardRules.reward(rates, 1, 0, false)
	assert(leaveGold == rates.wordGold and leaveExp == rates.wordExp, "a leaver keeps approved answer gold only")

	local before: Profile = { schemaVersion = 1, gold = 0, exp = 90, bestScore = 20 }
	local paid, applied = RewardRules.applyGrant(before, "server-a:1:once", gold, exp, 45, true)
	assert(applied and paid.gold == gold and paid.exp == 90 + exp and paid.bestScore == 45 and paid.ranked == true, "one grant updates the profile")
	local replay, replayed = RewardRules.applyGrant(paid, "server-a:1:once", gold, exp, 45, true)
	assert(not replayed and replay.gold == paid.gold, "a repeated settlement does not pay again")
	local doubled, doubledApplied = RewardRules.applyGrant(before, "server-a:1:score", gold, exp, 90, true)
	assert(doubledApplied and doubled.gold == gold and doubled.bestScore == 90, "a higher score does not change the gold")

	local left, leftApplied = RewardRules.applyGrant(before, "server-a:1:left", leaveGold, leaveExp, 10, false)
	assert(leftApplied and left.gold == leaveGold and left.bestScore == 20 and left.ranked == nil, "leaving does not replace the best score")
	local practiced, practiceApplied = RewardRules.applyGrant(paid, "server-a:1:practice", 0, 0, 150, false)
	assert(practiceApplied and practiced.bestScore == paid.bestScore and practiced.ranked == true, "practice does not change a finished best score")
	local climbing: Profile = { schemaVersion = 1, gold = 0, exp = 0, bestScore = 0 }
	local firstScore, firstOk = RewardRules.applyGrant(climbing, "rank:100", 0, 0, 100, true)
	local lowerScore, lowerOk = RewardRules.applyGrant(firstScore, "rank:80", 0, 0, 80, true)
	local higherScore, higherOk = RewardRules.applyGrant(lowerScore, "rank:120", 0, 0, 120, true)
	local practiceScore, practiceOk = RewardRules.applyGrant(higherScore, "rank:150", 0, 0, 150, false)
	assert(firstOk and lowerOk and higherOk and practiceOk, "the best-score sequence is applied")
	assert(firstScore.bestScore == 100 and lowerScore.bestScore == 100 and higherScore.bestScore == 120 and practiceScore.bestScore == 120, "finished scores keep the greater best")
	assert(practiceScore.ranked == true and firstScore.ranked == true, "only a finished match is ranked")
	local finishedZero, zeroOk = RewardRules.applyGrant(climbing, "rank:0", 0, 0, 0, true)
	assert(zeroOk and finishedZero.bestScore == 0 and finishedZero.ranked == true, "a finished zero is a record")

	local configured: Profile = {
		schemaVersion = 1,
		gold = 3,
		exp = 9,
		bestScore = 4,
		grants = { "keep" },
		uiLocale = "ko",
		gloss = "ko",
		typing = "ko",
		tutorialSeen = true,
		owned = { "pilot_body" },
		body = "pilot_body",
	}
	local withSettings, settingsApplied = RewardRules.applyGrant(configured, "server-a:1:keep-settings", 1, 0, 10, false)
	assert(settingsApplied and withSettings.uiLocale == "ko" and withSettings.gloss == "ko" and withSettings.typing == "ko" and withSettings.tutorialSeen == true, "a reward keeps the saved settings")
	assert(withSettings.owned ~= nil and withSettings.owned[1] == "pilot_body" and withSettings.body == "pilot_body", "a reward keeps the shop")
	assert(withSettings.gold == 4 and withSettings.exp == 9 and withSettings.bestScore == 4, "settings do not change the reward")
	assert(withSettings.grants ~= nil and withSettings.grants[1] == "keep" and withSettings.grants[2] == "server-a:1:keep-settings", "older grants stay with the new settlement")

	if rates.completeExp == 10 then
		local level, floorExp, nextExp = RewardRules.progress(90 + rates.completeExp, levels)
		assert(90 + rates.completeExp == 100 and level == 2 and floorExp == 100 and nextExp == nil, "100 exp is level 2")
		assert(RewardRules.progress(90, levels) == 1, "90 exp stays on level 1")
	end

	local tied: {RankRow} = {
		{ userId = 9, score = 10, rank = 1 },
		{ userId = 2, score = 10, rank = 2 },
	}
	local shown = RewardRules.displayRows(tied)
	assert(shown[1].userId == 9 and shown[2].rank == 2, "the result keeps the sealed order")
	assert(RewardRules.settlementId("server-a", 1, "n") ~= RewardRules.settlementId("server-b", 1, "n"), "local match numbers collide across servers")
	assert(RewardRules.settlementId("server-a", 1, "n") ~= "1", "a local match number is not a settlement id")
	assert(RewardRules.profileAfterOpen(false, nil) == nil, "a failed open does not invent a profile")
	local kept = RewardRules.profileAfterOpen(true, before)
	assert(kept ~= nil and kept.gold == 0 and kept.exp == 90 and kept.bestScore == 20, "an opened profile keeps its balances")
end

return RewardRules

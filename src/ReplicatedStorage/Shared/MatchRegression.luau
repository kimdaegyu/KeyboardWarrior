--!strict
-- Twelve-player regression. Selection, pads, questions, scores, ranks, and
-- settlement are the modules the match server calls. Profiles and the rank
-- board in this file are a test store, not the live DataStore.

local MatchRules = if script then require(script.Parent.MatchRules) else require("./MatchRules")
local QuestionRules = if script then require(script.Parent.QuestionRules) else require("./QuestionRules")
local PlaytestMetrics = if script then require(script.Parent.PlaytestMetrics) else require("./PlaytestMetrics")
local RewardRules = if script then require(script.Parent.RewardRules) else require("./RewardRules")
local RankRules = if script then require(script.Parent.RankRules) else require("./RankRules")
local SettingsRules = if script then require(script.Parent.SettingsRules) else require("./SettingsRules")

local MatchRegression = {}

type Memory = {
	profiles: {[number]: RewardRules.Profile},
	board: {[number]: number},
}

local function lowRng(): MatchRules.IntRng
	return {
		NextInteger = function(_self, min: number, _max: number): number
			return min
		end,
	}
end

local function blank(): RewardRules.Profile
	return {
		schemaVersion = 1,
		gold = 0,
		exp = 0,
		bestScore = 0,
	}
end

local function profile(memory: Memory, userId: number): RewardRules.Profile
	local current = memory.profiles[userId]
	if current == nil then
		current = blank()
		memory.profiles[userId] = current
	end
	return current
end

local function settle(memory: Memory, rates: RewardRules.Rates, settlementId: string, person: QuestionRules.Outcome): boolean
	local gold, exp = RewardRules.reward(rates, person.words, person.sentences, person.finished)
	local updated, applied = RewardRules.applyGrant(profile(memory, person.userId), settlementId, gold, exp, person.score, person.finished)
	if applied then
		memory.profiles[person.userId] = updated
		local score, recorded = RankRules.recordOf(updated.bestScore, updated.ranked)
		if recorded and score ~= nil then
			local stored = RankRules.storedValue(memory.board[person.userId], score)
			if stored ~= nil then
				memory.board[person.userId] = stored
			end
		end
	end
	return applied
end

local function uniquePads(assignment: {[number]: number}, expected: number)
	local seen: {[number]: boolean} = {}
	local count = 0
	for _, padIndex in assignment do
		assert(seen[padIndex] ~= true, "duplicate pad")
		seen[padIndex] = true
		count += 1
	end
	assert(count == expected, "every participant has a distinct pad")
end

local function findOutcome(rows: {QuestionRules.Outcome}, userId: number): QuestionRules.Outcome?
	for _, row in rows do
		if row.userId == userId then
			return row
		end
	end
	return nil
end

local function placedBoard(memory: Memory): {RankRules.Placed}
	local entries: {RankRules.Entry} = {}
	for userId, score in memory.board do
		table.insert(entries, {
			userId = userId,
			name = tostring(userId),
			score = score,
		})
	end
	table.sort(entries, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.userId < b.userId
	end)
	return RankRules.place(entries)
end

local function mean(values: {number}): number
	local sum = 0
	for _, value in values do
		sum += value
	end
	return sum / #values
end

local function solve(round: QuestionRules.Round, userId: number, now: number, method: string): (QuestionRules.Message, number, QuestionRules.Message)
	local solver = round.solvers[userId]
	local seen = QuestionRules.current(round, userId, now)
	local before = solver.score
	local result = QuestionRules.submit(round, userId, round.matchId, seen.issue :: number, seen.text :: string, now, method)
	return result, before, seen
end

local function run(
	deck: {QuestionRules.Prompt},
	languages: {SettingsRules.Language},
	rates: RewardRules.Rates,
	constants: any
): string
	local match = constants.Match
	local endsAt = match.PlaySeconds
	local issueAt = endsAt - (match.DoubleScoreSeconds + 1)
	local answerAt = endsAt - (match.DoubleScoreSeconds - 1)
	local outside = endsAt - match.DoubleScoreSeconds - 0.001
	local captureAt = endsAt - match.DoubleScoreSeconds
	local config = {
		doubleSeconds = match.DoubleScoreSeconds,
		multiplier = match.EndScoreMultiplier,
	}
	local saved: {[number]: string} = {
		[101] = "en",
		[102] = "ko",
		[103] = "en",
		[104] = "ko",
		[105] = "en",
		[106] = "ko",
		[107] = "en",
		[108] = "en",
		[109] = "en",
		[110] = "ko",
		[111] = "en",
		[112] = "ko",
	}
	local candidates: {MatchRules.Candidate} = {}
	for userId = 101, 112 do
		table.insert(candidates, { userId = userId, inZone = true, waitStartedAt = userId - 100 })
	end
	table.insert(candidates, { userId = 198, inZone = false, waitStartedAt = 0 })
	table.insert(candidates, { userId = 199, inZone = true, waitStartedAt = 13 })
	local selected = MatchRules.selectParticipants(candidates, match.MaxParticipants, match.MinParticipants)
	assert(#selected == 12, "twelve waiting players start the first match")
	assert(table.find(selected, 199) == nil and table.find(selected, 198) == nil, "the 13th waiter and a player outside the circle stay out")
	local pads = MatchRules.assignPads(selected, match.MaxParticipants, lowRng())
	uniquePads(pads, 12)
	local byUser: {[number]: string} = {}
	for _, userId in selected do
		local languageId = SettingsRules.sessionTyping(languages, saved[userId], false)
		if languageId == "" then
			languageId = "en"
		end
		byUser[userId] = languageId
	end
	assert(byUser[101] == "en" and byUser[102] == "ko" and byUser[108] == "en" and byUser[110] == "ko", "saved typing languages are the languages used in the match")
	local memory: Memory = { profiles = {}, board = {} }
	local settlementId = RewardRules.settlementId("regression", 41, "1")
	local round = QuestionRules.begin(deck, 41, endsAt, selected, 0, config, settlementId, byUser)
	local english = QuestionRules.current(round, 101, 1)
	local korean = QuestionRules.current(round, 102, 1)
	assert(english.text == QuestionRules.textFor(deck[1], "en") and korean.text == QuestionRules.textFor(deck[1], "ko"), "each player receives the prompt in the selected language")
	assert(english.text ~= korean.text, "English and Korean prompts differ")
	assert(round.metrics.samples["101:1"].issuedAt == 0, "reading the prompt again does not move the issue time")

	local function methodFor(userId: number): string
		return if byUser[userId] == "ko" then "touch" else "keyboard"
	end

	local elapsed = { en = {} :: {number}, ko = {} :: {number} }
	local function answer(userId: number, now: number)
		local result, before, seen = solve(round, userId, now, methodFor(userId))
		assert(result.awarded == true, "the scripted answer is accepted once")
		if seen.issue == 1 then
			local bucket = if byUser[userId] == "ko" then elapsed.ko else elapsed.en
			table.insert(bucket, now)
		end
		return result, before, seen
	end

	answer(101, 10)
	answer(101, 20)
	answer(101, 30)
	answer(102, 12)
	answer(102, 22)
	answer(102, 32)
	answer(111, 25)
	answer(110, 15)
	QuestionRules.forget(round, 110, 40)
	assert(round.solvers[110] == nil, "the leaver is no longer in the match")
	answer(112, 35)
	answer(112, 45)
	answer(103, 40)
	answer(104, 50)
	answer(105, 60)
	answer(106, 60)
	answer(107, 70)
	answer(107, 80)

	local _, _, firstIssued = answer(108, issueAt)
	assert(firstIssued.multiplier == 1, "a prompt issued before the last 30 seconds keeps the base multiplier")
	QuestionRules.noteClock(round, outside)
	assert(round.metrics.doubleCaptured == false, "31 hundredths outside the window does not record ranks")
	QuestionRules.noteClock(round, captureAt)
	local frozen: {[number]: number} = {}
	for userId, rank in round.metrics.doubleRanks do
		frozen[userId] = rank
	end
	for _, standing in QuestionRules.standings(round) do
		assert(frozen[standing.userId] == standing.rank, "the window stores the standing order at entry")
	end
	assert(frozen[110] == nil, "a player who already left is not in the window")

	local doubled, beforeDouble, issuedInside = solve(round, 108, answerAt, "keyboard")
	assert(issuedInside.multiplier == 1, "a prompt issued at 31 seconds still scores at the base multiplier when answered at 29")
	assert(doubled.awarded == true and doubled.total == beforeDouble + (issuedInside.score :: number), "the base multiplier is the one locked at issue time")
	assert(round.metrics.samples["108:2"].issuedAt == issueAt and round.metrics.samples["108:2"].multiplier == 1, "the follow-up prompt keeps the 31-second issue")
	local words = round.solvers[108].wordCount
	local echo = QuestionRules.submit(round, 108, round.matchId, issuedInside.issue :: number, issuedInside.text :: string, answerAt, "keyboard")
	assert(echo.awarded == false and echo.total == doubled.total and round.solvers[108].wordCount == words, "a resent answer does not score, complete, or count again")
	local follow = QuestionRules.current(round, 108, answerAt)
	assert(follow.multiplier == config.multiplier, "the prompt issued at 29 seconds is locked to the double multiplier")
	assert(round.metrics.samples["108:3"].issuedAt == answerAt and round.metrics.samples["108:3"].multiplier == config.multiplier, "the double multiplier is stored with that issue")
	local scored, beforeLast, lastSeen = solve(round, 108, answerAt + 1, "keyboard")
	assert(lastSeen.multiplier == config.multiplier and scored.total == beforeLast + (lastSeen.score :: number) * config.multiplier, "the doubled prompt pays the locked multiplier")
	for userId, rank in frozen do
		assert(round.metrics.doubleRanks[userId] == rank, "later scores do not replace the window ranks")
	end

	QuestionRules.close(round)
	QuestionRules.seal(round)
	local outcome = QuestionRules.outcome(round)
	local report = PlaytestMetrics.report(round)
	assert(#outcome.rows == 11 and #outcome.departed == 1, "one leaver leaves eleven finishers")
	local shown = QuestionRules.visibleRanks(round.finalOrder :: {QuestionRules.Standing}, 109, 5)
	assert(#shown == 6 and shown[#shown].userId == 109, "the phone drawer keeps the top five plus the local row")
	for _, person in outcome.rows do
		local prefix = string.format("%d %s 완주 단어 %d 문장 %d 점수 %d", person.userId, person.language, person.words, person.sentences, person.score)
		local at = string.find(report, prefix, 1, true)
		assert(at ~= nil, "the summary score matches the result row")
		local tail = string.sub(report, at :: number, (at :: number) + #prefix + 64)
		assert(string.find(tail, string.format("최종 순위 %d", person.rank), 1, true) ~= nil, "the summary rank matches the result row")
		local windowRank = frozen[person.userId]
		local windowLabel = if windowRank == nil then "없음" else tostring(windowRank)
		assert(string.find(tail, "마지막 30초 순위 " .. windowLabel, 1, true) ~= nil, "the summary keeps the window rank")
	end
	local leaver = outcome.departed[1]
	assert(leaver.userId == 110 and leaver.finished == false and leaver.rank == 0, "the leaver is outside the final order")
	local leavePrefix = string.format("%d %s 이탈 단어 %d 문장 %d 점수 %d", leaver.userId, leaver.language, leaver.words, leaver.sentences, leaver.score)
	assert(string.find(report, leavePrefix, 1, true) ~= nil and string.find(report, leavePrefix .. " 분당", 1, true) ~= nil, "the leaver score is the approved score")
	assert(string.find(report, "최종 순위 없음", 1, true) ~= nil, "a leaver has no final rank")
	local leaveRate = PlaytestMetrics.perMinute(leaver.score, 40)
	assert(leaveRate ~= nil and string.find(report, string.format("분당 %.3f", leaveRate), 1, true) ~= nil, "a leaver's rate uses the time until they left")

	local function row(userId: number): QuestionRules.Outcome
		return assert(findOutcome(outcome.rows, userId), "finisher")
	end
	assert(row(101).score == row(102).score and row(101).rank < row(102).rank, "an equal score keeps the player who reached it first")
	assert(round.solvers[105].score == round.solvers[106].score and round.solvers[105].reachedAt == round.solvers[106].reachedAt, "two players can finish equal at the same time")
	assert(row(105).rank + 1 == row(106).rank, "the same reach time keeps the smaller UserId ahead")
	assert(row(109).score == 0 and row(109).words == 0 and row(109).sentences == 0, "a finisher can stay at zero")
	assert(row(108).rank == 1 and row(108).score > row(101).score, "the doubled prompt changes the final order")
	assert(frozen[108] ~= row(108).rank, "the window rank stays where it was captured")

	local fast = row(108)
	local paidGold, paidExp = RewardRules.reward(rates, fast.words, fast.sentences, true)
	assert(settle(memory, rates, settlementId, fast) == true, "the first settlement is applied")
	assert(profile(memory, 108).gold == paidGold and profile(memory, 108).exp == paidExp, "reward gold follows the answer counts, not the score multiplier")
	assert(settle(memory, rates, settlementId, fast) == false and profile(memory, 108).gold == paidGold, "the same settlement does not pay again")
	for _, person in outcome.rows do
		if person.userId ~= 108 then
			assert(settle(memory, rates, settlementId, person) == true, "each finisher is settled once")
		end
	end
	assert(settle(memory, rates, settlementId, leaver) == true, "the leaver is settled from approved answers")
	local leaveGold, leaveExp = RewardRules.reward(rates, leaver.words, leaver.sentences, false)
	local zeroGold, zeroExp = RewardRules.reward(rates, 0, 0, true)
	assert(profile(memory, 110).gold == leaveGold and profile(memory, 110).exp == leaveExp and profile(memory, 110).ranked ~= true, "a leaver keeps answer gold and is not ranked")
	assert(profile(memory, 109).gold == zeroGold and profile(memory, 109).exp == zeroExp and profile(memory, 109).ranked == true and profile(memory, 109).bestScore == 0, "a zero finisher is ranked and unpaid")
	assert(memory.board[110] == nil and memory.board[109] == 0 and memory.board[108] == fast.score, "the test board records finished scores only")
	local board = placedBoard(memory)
	local globalRank: {[number]: number} = {}
	for _, placed in board do
		globalRank[placed.userId] = placed.rank
	end
	assert(globalRank[105] == globalRank[106] and row(105).rank ~= row(106).rank, "global ties share a place while the match order stays unique")

	local enAverage = string.format("%s EN 단어 물리 키보드 출제 %d 완료 %d 미완료 0 평균 %.3f초 (n=%d)", deck[1].id, #elapsed.en, #elapsed.en, mean(elapsed.en), #elapsed.en)
	local enOpen = string.format("%s EN 단어 미확인 출제 1 완료 0 미완료 1 평균 없음 (n=0)", deck[1].id)
	local koAverage = string.format("%s KO 단어 화면 키보드 출제 %d 완료 %d 미완료 0 평균 %.3f초 (n=%d)", deck[1].id, #elapsed.ko, #elapsed.ko, mean(elapsed.ko), #elapsed.ko)
	assert(string.find(report, enAverage, 1, true) ~= nil, "English completion time excludes the unfinished prompt")
	assert(string.find(report, enOpen, 1, true) ~= nil, "the unfinished English prompt is incomplete")
	assert(string.find(report, koAverage, 1, true) ~= nil, "Korean completion time is separate")
	PlaytestMetrics.clear(round.metrics)
	assert(string.find(PlaytestMetrics.report(round), "완료 1", 1, true) == nil, "clearing the summary drops the first match")

	local secondSaved: {[number]: string} = { [108] = "en", [113] = "ko" }
	local secondCandidates: {MatchRules.Candidate} = {
		{ userId = 108, inZone = true, waitStartedAt = 0 },
		{ userId = 101, inZone = false, waitStartedAt = 0 },
	}
	for offset = 1, 11 do
		local userId = 112 + offset
		secondSaved[userId] = if userId == 113 then "ko" else "en"
		table.insert(secondCandidates, { userId = userId, inZone = true, waitStartedAt = offset })
	end
	local secondSelected = MatchRules.selectParticipants(secondCandidates, match.MaxParticipants, match.MinParticipants)
	assert(#secondSelected == 12 and secondSelected[1] == 108 and table.find(secondSelected, 101) == nil, "the next match selects a different roster")
	local secondPads = MatchRules.assignPads(secondSelected, match.MaxParticipants, lowRng())
	uniquePads(secondPads, 12)
	assert(secondPads[108] ~= pads[108], "pad assignment starts from the new roster")
	local secondLanguages: {[number]: string} = {}
	for _, userId in secondSelected do
		secondLanguages[userId] = SettingsRules.sessionTyping(languages, secondSaved[userId], false)
	end
	local secondId = RewardRules.settlementId("regression", 42, "2")
	assert(secondId ~= settlementId, "each match has its own settlement id")
	local bestBefore = profile(memory, 108).bestScore
	local goldBefore = profile(memory, 108).gold
	local second = QuestionRules.begin(deck, 42, endsAt, secondSelected, 0, config, secondId, secondLanguages)
	assert(second.solvers[108].issue == 1 and second.solvers[108].score == 0, "a returning player starts the next match at the first prompt and zero")
	assert(second.metrics.doubleCaptured == false and second.metrics.doubleRanks[108] == nil, "the next match has no window rank yet")
	local fresh = QuestionRules.current(second, 113, 1)
	assert(fresh.text == QuestionRules.textFor(deck[1], "ko") and fresh.issue == 1, "the new roster receives its own first prompt")
	local secondScore = QuestionRules.submit(second, 113, 42, 1, fresh.text :: string, 10, "touch")
	assert(secondScore.awarded == true and second.solvers[113].score == deck[1].score, "the second match scores only its own answer")
	local held = second.solvers[113].score
	local stale = QuestionRules.submit(second, 113, round.matchId, 1, fresh.text :: string, 50, "touch")
	local late = QuestionRules.submit(round, 108, round.matchId, 1, QuestionRules.textFor(deck[1], "en"), 50, "keyboard")
	assert(stale.ok == false and late.ok == false, "a late or crossed submission is rejected")
	assert(second.solvers[113].score == held and second.solvers[108].score == 0, "the first match cannot change the second match")
	QuestionRules.noteClock(second, captureAt)
	for _, standing in QuestionRules.standings(second) do
		assert(second.metrics.doubleRanks[standing.userId] == standing.rank, "the second window uses the second match")
	end
	assert(second.metrics.doubleRanks[108] ~= frozen[108], "the second window is not the first match's rank")
	QuestionRules.close(second)
	QuestionRules.seal(second)
	local secondOutcome = QuestionRules.outcome(second)
	local secondReport = PlaytestMetrics.report(second)
	assert(string.find(secondReport, "match=42", 1, true) ~= nil and string.find(secondReport, "match=41", 1, true) == nil, "the next summary starts empty of the previous match")
	assert(string.find(secondReport, enAverage, 1, true) == nil, "the next summary does not keep the first match's average")
	local returned = findOutcome(secondOutcome.rows, 108)
	assert(returned ~= nil and returned.score == 0, "a returning player is scored only from the second match")
	for _, person in secondOutcome.rows do
		assert(settle(memory, rates, secondId, person) == true, "the second match settles on its own id")
	end
	assert(profile(memory, 108).bestScore == bestBefore and profile(memory, 108).gold == goldBefore, "a lower second finish does not reduce the saved best score or add gold")
	assert(memory.board[108] == bestBefore, "the test board does not replace a better finished score")
	PlaytestMetrics.clear(second.metrics)

	local ids: {number} = {}
	for userId in memory.profiles do
		table.insert(ids, userId)
	end
	table.sort(ids)
	local parts: {string} = { report, secondReport }
	for _, userId in ids do
		local stored = memory.profiles[userId]
		table.insert(parts, string.format("%d:%d:%d:%s", userId, stored.gold, stored.bestScore, tostring(stored.ranked == true)))
	end
	table.insert(parts, string.format("%d:%d", pads[108], secondPads[108]))
	return table.concat(parts, "\n")
end

function MatchRegression.selfCheck(
	questionRows: {QuestionRules.SheetRow},
	gradeRows: {QuestionRules.GradeRow},
	rewardRows: {RewardRules.RewardRow},
	languageRows: {SettingsRules.Row},
	constants: any
)
	local deck = QuestionRules.deckFromRows(questionRows, gradeRows)
	assert(#deck >= 3 and deck[1].kind == "Word" and deck[2].kind == "Word" and deck[3].kind == "Sentence", "the pilot deck still starts with two words and a sentence")
	local languages, reason = SettingsRules.catalog(languageRows)
	assert(reason == "ok" and languages ~= nil, "language catalog")
	local rates = RewardRules.ratesFromRows(rewardRows)
	local first = run(deck, languages :: {SettingsRules.Language}, rates, constants)
	local second = run(deck, languages :: {SettingsRules.Language}, rates, constants)
	assert(first == second, "running the twelve-player scenario again produces the same result")
end

return MatchRegression

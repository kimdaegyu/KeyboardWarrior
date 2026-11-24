--!strict
-- Official-match timing. Practice does not use this module.
-- The typed answer and individual keys are not stored.

local PlaytestMetrics = {}

export type Method = "keyboard" | "touch" | "mixed" | "unknown"

export type Sample = {
	matchId: number,
	userId: number,
	questionId: string,
	issue: number,
	kind: string,
	language: string,
	multiplier: number,
	issuedAt: number,
	status: string,
	method: Method,
	elapsed: number?,
	points: number?,
}

export type State = {
	samples: {[string]: Sample},
	order: {string},
	doubleCaptured: boolean,
	doubleRanks: {[number]: number},
}

export type Standing = {
	userId: number,
	rank: number,
}

local METHODS: {[string]: boolean} = {
	keyboard = true,
	touch = true,
	mixed = true,
	unknown = true,
}

local function keyFor(userId: number, issue: number): string
	return tostring(userId) .. ":" .. tostring(issue)
end

function PlaytestMetrics.begin(): State
	return {
		samples = {},
		order = {},
		doubleCaptured = false,
		doubleRanks = {},
	}
end

function PlaytestMetrics.method(value: any): Method
	if type(value) == "string" and METHODS[value] == true then
		return value :: Method
	end
	return "unknown"
end

function PlaytestMetrics.issue(
	state: State,
	matchId: number,
	userId: number,
	questionId: string,
	issue: number,
	kind: string,
	language: string,
	multiplier: number,
	issuedAt: number
)
	local key = keyFor(userId, issue)
	if state.samples[key] ~= nil then
		return
	end
	state.samples[key] = {
		matchId = matchId,
		userId = userId,
		questionId = questionId,
		issue = issue,
		kind = if kind == "Sentence" then "Sentence" else "Word",
		language = language,
		multiplier = multiplier,
		issuedAt = issuedAt,
		status = "open",
		method = "unknown",
	}
	table.insert(state.order, key)
end

function PlaytestMetrics.complete(state: State, userId: number, issue: number, now: number, method: any, points: number): boolean
	local sample = state.samples[keyFor(userId, issue)]
	if sample == nil or sample.status ~= "open" then
		return false
	end
	sample.status = "done"
	sample.elapsed = now - sample.issuedAt
	sample.method = PlaytestMetrics.method(method)
	sample.points = points
	return true
end

function PlaytestMetrics.abandonUser(state: State, userId: number)
	for _, key in state.order do
		local sample = state.samples[key]
		if sample.userId == userId and sample.status == "open" then
			sample.status = "incomplete"
		end
	end
end

function PlaytestMetrics.abandonOpen(state: State)
	for _, key in state.order do
		local sample = state.samples[key]
		if sample.status == "open" then
			sample.status = "incomplete"
		end
	end
end

function PlaytestMetrics.noteWindow(state: State, remain: number, window: number, ranks: {Standing})
	if state.doubleCaptured or remain <= 0 or remain > window then
		return
	end
	state.doubleCaptured = true
	for _, row in ranks do
		state.doubleRanks[row.userId] = row.rank
	end
end

function PlaytestMetrics.clear(state: State)
	table.clear(state.samples)
	table.clear(state.order)
	table.clear(state.doubleRanks)
	state.doubleCaptured = false
end

local function methodLabel(method: Method): string
	if method == "keyboard" then
		return "물리 키보드"
	end
	if method == "touch" then
		return "화면 키보드"
	end
	if method == "mixed" then
		return "혼용"
	end
	return "미확인"
end

local function kindLabel(kind: string): string
	if kind == "Sentence" then
		return "문장"
	end
	return "단어"
end

local function languageLabel(language: string): string
	if language == "" then
		return "EN"
	end
	return string.upper(language)
end

local function secondsLabel(value: number?): string
	if value == nil then
		return "없음"
	end
	return string.format("%.3f초", value)
end

function PlaytestMetrics.perMinute(score: number, seconds: number): number?
	if seconds <= 0 then
		return nil
	end
	return score / (seconds / 60)
end

function PlaytestMetrics.report(round: any): string
	local state = round.metrics :: State
	local groups: {[string]: {questionId: string, language: string, kind: string, method: Method, issued: number, done: number, elapsed: number}} = {}
	local groupOrder: {string} = {}
	for _, key in state.order do
		local sample = state.samples[key]
		local groupKey = sample.questionId .. "\0" .. sample.language .. "\0" .. sample.kind .. "\0" .. sample.method
		local group = groups[groupKey]
		if group == nil then
			group = {
				questionId = sample.questionId,
				language = sample.language,
				kind = sample.kind,
				method = sample.method,
				issued = 0,
				done = 0,
				elapsed = 0,
			}
			groups[groupKey] = group
			table.insert(groupOrder, groupKey)
		end
		group.issued += 1
		if sample.status == "done" and sample.elapsed ~= nil then
			group.done += 1
			group.elapsed += sample.elapsed
		end
	end
	table.sort(groupOrder, function(a, b)
		local left = groups[a]
		local right = groups[b]
		if left.questionId ~= right.questionId then
			return left.questionId < right.questionId
		end
		if left.language ~= right.language then
			return left.language < right.language
		end
		if left.kind ~= right.kind then
			return left.kind < right.kind
		end
		return left.method < right.method
	end)

	local lines = {
		string.format("[KeyboardWarrior] 플레이테스트 지표 match=%d", round.matchId),
		"분당 점수 = 최종 점수 / (참가 시간(초) / 60). 완주자는 종료 시각-시작 시각, 이탈자는 이탈 시각-시작 시각.",
		"문제 ID 언어 종류 입력 방식 출제 완료 미완료 평균 출제→정답 승인 시간",
	}
	for _, groupKey in groupOrder do
		local group = groups[groupKey]
		local incomplete = group.issued - group.done
		local average = if group.done > 0 then group.elapsed / group.done else nil
		table.insert(lines, string.format(
			"%s %s %s %s 출제 %d 완료 %d 미완료 %d 평균 %s (n=%d)",
			group.questionId,
			languageLabel(group.language),
			kindLabel(group.kind),
			methodLabel(group.method),
			group.issued,
			group.done,
			incomplete,
			secondsLabel(average),
			group.done
		))
	end
	table.insert(lines, "참가자")
	local finishers = if round.finalOrder ~= nil then round.finalOrder else {}
	for _, standing in finishers do
		local solver = round.solvers[standing.userId]
		local played = if solver ~= nil then solver.language else "en"
		local words = if solver ~= nil then solver.wordCount else 0
		local sentences = if solver ~= nil then solver.sentenceCount else 0
		local rate = PlaytestMetrics.perMinute(standing.score, round.endsAt - round.startedAt)
		local doubleRank = state.doubleRanks[standing.userId]
		table.insert(lines, string.format(
			"%d %s 완주 단어 %d 문장 %d 점수 %d 분당 %s 마지막 30초 순위 %s 최종 순위 %d",
			standing.userId,
			languageLabel(played),
			words,
			sentences,
			standing.score,
			if rate == nil then "없음" else string.format("%.3f", rate),
			if doubleRank == nil then "없음" else tostring(doubleRank),
			standing.rank
		))
	end
	local leavers: {number} = {}
	for userId in round.departed do
		table.insert(leavers, userId)
	end
	table.sort(leavers)
	for _, userId in leavers do
		local left = round.departed[userId]
		local played = if type(left.language) == "string" then left.language else "en"
		local rate = if type(left.leftAt) == "number" then PlaytestMetrics.perMinute(left.score, left.leftAt - round.startedAt) else nil
		local doubleRank = state.doubleRanks[userId]
		table.insert(lines, string.format(
			"%d %s 이탈 단어 %d 문장 %d 점수 %d 분당 %s 마지막 30초 순위 %s 최종 순위 없음",
			userId,
			languageLabel(played),
			left.words,
			left.sentences,
			left.score,
			if rate == nil then "없음" else string.format("%.3f", rate),
			if doubleRank == nil then "없음" else tostring(doubleRank)
		))
	end
	return table.concat(lines, "\n")
end

function PlaytestMetrics.selfCheck(QuestionRules: any)
	local deck = {
		{ id = "apple", text = "apple", texts = { en = "apple", ko = "사과" }, score = 10, gradeId = "Basic", colorHex = "#6961BB", kind = "Word" },
		{ id = "play", text = "play now", texts = { en = "play now", ko = "지금 놀자" }, score = 25, gradeId = "Bright", colorHex = "#AA58D0", kind = "Sentence" },
	}
	local config = { doubleSeconds = 30, multiplier = 2 }
	local round = QuestionRules.begin(deck, 7, 120, { 2, 9 }, 0, config, nil, { [2] = "en", [9] = "ko" })
	QuestionRules.current(round, 2, 4)
	assert(round.metrics.samples["2:1"].issuedAt == 0, "a repeated question query keeps the first issue time")
	local first = QuestionRules.submit(round, 2, 7, 1, "apple", 10, "keyboard")
	assert(first.awarded == true and first.total == 10, "the first approval scores once")
	assert(round.metrics.samples["2:1"].elapsed == 10, "elapsed time starts at the first issue, not the later query")
	local duplicate = QuestionRules.submit(round, 2, 7, 1, "apple", 11, "keyboard")
	assert(duplicate.awarded == false and duplicate.total == 10, "a resent answer does not score again")
	QuestionRules.current(round, 2, 12)
	local outside = QuestionRules.begin(deck, 8, 120, { 2 }, 0, config)
	QuestionRules.noteClock(outside, 120 - 30.001)
	assert(outside.metrics.doubleCaptured == false, "just over 30 seconds does not capture the rank")
	QuestionRules.noteClock(round, 90)
	assert(round.metrics.doubleRanks[2] == 1 and round.metrics.doubleRanks[9] == 2, "the last 30 seconds capture the standing order once")
		local passed = QuestionRules.submit(round, 9, 7, 1, "사과", 95, "touch")
	assert(passed.awarded == true and passed.total == 10, "Korean approval is separate from English")
	local overtook = QuestionRules.submit(round, 9, 7, 2, "지금 놀자", 100, "touch")
	assert(overtook.awarded == true and overtook.total == 60, "a prompt issued inside the last 30 seconds keeps that multiplier")
	QuestionRules.noteClock(round, 100)
	assert(round.metrics.doubleRanks[9] == 2, "a later score does not replace the captured rank")
	QuestionRules.forget(round, 9, 100)
	QuestionRules.close(round)
	QuestionRules.seal(round)
	local report = PlaytestMetrics.report(round)
	assert(round.metrics.samples["2:1"].points == 10, "the summary keeps the awarded points without the typed answer")
	assert(string.find(report, "apple EN 단어 물리 키보드 출제 1 완료 1 미완료 0 평균 10.000초 (n=1)", 1, true) ~= nil, "English completion time stays with the first issue")
	assert(string.find(report, "apple KO 단어 화면 키보드 출제 1 완료 1 미완료 0 평균 95.000초 (n=1)", 1, true) ~= nil, "Korean completion time is separate")
	assert(string.find(report, "play EN 문장 미확인 출제 1 완료 0 미완료 1 평균 없음 (n=0)", 1, true) ~= nil, "an unfinished prompt is excluded from the average")
	assert(string.find(report, "2 EN 완주 단어 1 문장 0 점수 10 분당 5.000 마지막 30초 순위 1 최종 순위 1", 1, true) ~= nil, "a finisher uses the sealed rank and the full match length")
	assert(string.find(report, "9 KO 이탈 단어 1 문장 1 점수 60 분당 36.000 마지막 30초 순위 2 최종 순위 없음", 1, true) ~= nil, "a departure is not a finisher")
	local again = QuestionRules.begin(deck, 8, 120, { 2 }, 0, config)
	local fresh = PlaytestMetrics.report(again)
	assert(string.find(fresh, "출제 1", 1, true) ~= nil and string.find(fresh, "완료 0", 1, true) ~= nil, "the next match starts empty")
	assert(string.find(fresh, "match=8", 1, true) ~= nil and string.find(fresh, "match=7", 1, true) == nil, "the next match does not keep the previous summary")
	PlaytestMetrics.clear(round.metrics)
	local cleared = PlaytestMetrics.report(round)
	assert(string.find(cleared, "출제", 1, true) ~= nil and string.find(cleared, "완료 1", 1, true) == nil, "closing the match drops the collected rows")

	local shared = QuestionRules.begin(deck, 9, 120, { 2, 9 }, 0, config)
	QuestionRules.submit(shared, 2, 9, 1, "apple", 10)
	QuestionRules.close(shared)
	local mixed = PlaytestMetrics.report(shared)
	assert(string.find(mixed, "apple EN 단어 미확인 출제 2 완료 1 미완료 1 평균 10.000초 (n=1)", 1, true) ~= nil, "an unfinished issue does not shorten the average")
end

return PlaytestMetrics

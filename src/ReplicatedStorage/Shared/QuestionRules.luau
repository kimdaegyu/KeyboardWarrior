--!strict
-- Shared question order and completion rules. No instances and no sample prompts.

local HangulInput = if script then require(script.Parent.HangulInput) else require("./HangulInput")
local PlaytestMetrics = if script
	then require(script.Parent.PlaytestMetrics)
	else require("./PlaytestMetrics")

export type SheetRow = {
	Id: string,
	Enabled: string,
	en: string,
	ko: string?,
	Score: string?,
	GradeId: string?,
	Kind: string?,
}

export type GradeRow = {
	Id: string,
	ColorHex: string,
}

export type Prompt = {
	id: string,
	text: string,
	texts: {[string]: string}?,
	score: number,
	gradeId: string,
	colorHex: string,
	kind: string,
}

export type ScoreConfig = {
	doubleSeconds: number,
	multiplier: number,
}

export type Solver = {
	issue: number,
	index: number,
	score: number,
	wordCount: number,
	strokes: number,
	sentenceCount: number,
	multiplier: number,
	reachedAt: number,
	scoredIssue: number,
	lastIssue: number?,
	lastAwarded: boolean?,
	lastTotal: number?,
	lastNextIssue: number?,
	lastNextId: string?,
	lastNextText: string?,
	lastNextScore: number?,
	lastNextPoints: number?,
	lastNextMultiplier: number?,
	lastNextColor: string?,
	language: string,
}

export type Standing = {
	userId: number,
	score: number,
	reachedAt: number,
	rank: number,
}

export type Departure = {
	score: number,
	words: number,
	sentences: number,
	language: string?,
	leftAt: number?,
}

export type Outcome = {
	userId: number,
	language: string,
	rank: number,
	score: number,
	words: number,
	sentences: number,
	finished: boolean,
}

export type Round = {
	matchId: number,
	settlementId: string,
	endsAt: number,
	open: boolean,
	sealed: boolean,
	startedAt: number,
	scoreConfig: ScoreConfig,
	deck: {Prompt},
	solvers: {[number]: Solver},
	departed: {[number]: Departure},
	finalOrder: {Standing}?,
	metrics: PlaytestMetrics.State,
}

export type Message = {
	ok: boolean,
	reason: string?,
	matchId: number,
	issue: number?,
	questionId: string?,
	text: string?,
	nextIssue: number?,
	nextQuestionId: string?,
	nextText: string?,
	score: number?,
	points: number?,
	multiplier: number?,
	colorHex: string?,
	total: number?,
	awarded: boolean?,
	nextScore: number?,
	nextPoints: number?,
	nextMultiplier: number?,
	nextColorHex: string?,
	typing: string?,
}

export type ClientSession = {
	matchId: number,
	issue: number,
	questionId: string,
	text: string,
	points: number,
	multiplier: number,
	colorHex: string,
	total: number,
	typing: string,
}

local QuestionRules = {}

QuestionRules.MaxInputLength = 200

local DEFAULT_SCORE: ScoreConfig = {
	doubleSeconds = 30,
	multiplier = 2,
}

function QuestionRules.multiplierFor(remain: number, config: ScoreConfig): number
	if remain > 0 and remain <= config.doubleSeconds then
		return config.multiplier
	end
	return 1
end

function QuestionRules.clientMatchId(phase: string?, inMatch: boolean, matchId: number?): number
	if phase ~= "Play" or inMatch ~= true then
		return 0
	end
	if type(matchId) ~= "number" or matchId <= 0 then
		return 0
	end
	return matchId
end

local function columnText(row: SheetRow, name: string): string
	if name == "en" then
		return row.en
	end
	local value = (row :: any)[name]
	if type(value) == "string" then
		return value
	end
	return ""
end

function QuestionRules.deckFromRows(rows: {SheetRow}, grades: {GradeRow}?, languageIds: {string}?): {Prompt}
	local colors: {[string]: string} = {}
	if grades ~= nil then
		for _, grade in grades do
			colors[grade.Id] = grade.ColorHex
		end
	end
	local names = if languageIds ~= nil then languageIds else { "en", "ko" }
	local deck = {}
	for _, row in ipairs(rows) do
		if row.Enabled == "1" and row.Id ~= "" and row.en ~= "" then
			local gradeId = row.GradeId or ""
			local parsed = tonumber(row.Score)
			local texts: {[string]: string} = {}
			for _, name in names do
				texts[name] = columnText(row, name)
			end
			if texts.en == nil or texts.en == "" then
				texts.en = row.en
			end
			table.insert(deck, table.freeze({
				id = row.Id,
				text = row.en,
				texts = texts,
				score = if type(parsed) == "number" then parsed else 0,
				gradeId = gradeId,
				colorHex = colors[gradeId] or "#FFFFFF",
				kind = if row.Kind == "Sentence" then "Sentence" else "Word",
			}))
		end
	end
	return table.freeze(deck)
end

function QuestionRules.matches(input: string, answer: string): boolean
	return string.lower(input) == string.lower(answer)
end

function QuestionRules.textFor(prompt: Prompt, language: string): string
	local texts = prompt.texts
	if texts ~= nil then
		local value = texts[language]
		if type(value) == "string" and value ~= "" then
			return value
		end
	end
	if language == "en" then
		return prompt.text
	end
	return ""
end

function QuestionRules.clip(text: string, limit: number): string
	if limit < 0 then
		return ""
	end
	local count = utf8.len(text)
	if count == nil then
		return ""
	end
	if count <= limit then
		return text
	end
	local offset = utf8.offset(text, limit + 1)
	if offset == nil then
		return text
	end
	return string.sub(text, 1, offset - 1)
end

function QuestionRules.autoSubmits(language: string): boolean
	return language ~= ""
end

-- The caret is a byte index. A composing syllable may sit after it, and the rendered
-- field may already show that syllable before Text commits it. Candidate lists are not read.
function QuestionRules.fieldAnswer(text: string, cursor: number, content: string?): string
	local rendered = text
	if type(content) == "string" and content ~= text and #content > #text and string.sub(content, 1, #text) == text then
		rendered = content
	end
	if type(cursor) ~= "number" or cursor < 1 or cursor > #rendered + 1 then
		return rendered
	end
	return string.sub(rendered, 1, cursor - 1) .. string.sub(rendered, cursor)
end

function QuestionRules.revives(text: string, accepted: string): boolean
	if accepted == "" or text == "" then
		return false
	end
	if text == accepted then
		return true
	end
	if #text > #accepted and string.sub(text, 1, #accepted) == accepted then
		local rest = string.sub(text, #accepted + 1)
		for index = 1, #rest do
			if string.sub(rest, index, index) ~= " " then
				return false
			end
		end
		return rest ~= ""
	end
	if #text < #accepted and string.sub(accepted, -#text) == text then
		return true
	end
	return false
end

function QuestionRules.usesIme(language: string): boolean
	return language ~= "en"
end

export type Compose = {
	pending: boolean,
	snapshot: string,
	settled: boolean,
}

function QuestionRules.composeIdle(): Compose
	return {
		pending = false,
		snapshot = "",
		settled = false,
	}
end

-- Events are the engine text, the Enter key, a later key, and focus loss.
-- A Hangul commit is the Text change after an Enter the IME consumed, not a delay.
function QuestionRules.composeEvent(state: Compose, event: string, text: string, gameProcessed: boolean?): (Compose, string)
	if event == "enter" then
		if gameProcessed == true and text ~= "" then
			return {
				pending = true,
				snapshot = text,
				settled = false,
			}, "wait"
		end
		return {
			pending = false,
			snapshot = text,
			settled = false,
		}, "ignore"
	end
	if event == "text" then
		if state.pending then
			return {
				pending = false,
				snapshot = text,
				settled = true,
			}, "submit"
		end
		return state, "show"
	end
	if event == "key" then
		if state.pending then
			return {
				pending = false,
				snapshot = state.snapshot,
				settled = true,
			}, "ignore"
		end
		return state, "ignore"
	end
	if event == "blur" then
		if state.pending and text ~= state.snapshot then
			return {
				pending = false,
				snapshot = text,
				settled = true,
			}, "submit"
		end
		if state.pending then
			return state, "wait"
		end
		if state.settled then
			return {
				pending = false,
				snapshot = state.snapshot,
				settled = false,
			}, "ignore"
		end
		return {
			pending = false,
			snapshot = text,
			settled = true,
		}, "submit"
	end
	return state, "ignore"
end

function QuestionRules.languageCode(language: string?): string
	if type(language) ~= "string" or language == "" then
		return string.upper("en")
	end
	return string.upper(language)
end

function QuestionRules.missingText(rows: {SheetRow}, languageIds: {string}): (string?, string?)
	for _, row in rows do
		if row.Enabled == "1" and row.Id ~= "" then
			for _, languageId in languageIds do
				if columnText(row, languageId) == "" then
					return row.Id, languageId
				end
			end
		end
	end
	return nil, nil
end

local function promptAt(deck: {Prompt}, index: number): Prompt
	local count = #deck
	return deck[(index - 1) % count + 1]
end

function QuestionRules.begin(deck: {Prompt}, matchId: number, endsAt: number, userIds: {number}, now: number?, config: ScoreConfig?, settlementId: string?, byUser: {[number]: string}?): Round
	local startedAt = if type(now) == "number" then now else 0
	local scoreConfig = config or DEFAULT_SCORE
	local multiplier = QuestionRules.multiplierFor(endsAt - startedAt, scoreConfig)
	local solvers: {[number]: Solver} = {}
	for _, userId in ipairs(userIds) do
		local language = "en"
		if byUser ~= nil and type(byUser[userId]) == "string" and byUser[userId] ~= "" then
			language = byUser[userId]
		end
		solvers[userId] = {
			issue = 1,
			index = 1,
			score = 0,
			wordCount = 0,
			strokes = 0,
			sentenceCount = 0,
			multiplier = multiplier,
			reachedAt = startedAt,
			scoredIssue = 0,
			language = language,
		}
	end
	local round: Round = {
		matchId = matchId,
		settlementId = if type(settlementId) == "string" then settlementId else "",
		endsAt = endsAt,
		open = true,
		sealed = false,
		startedAt = startedAt,
		scoreConfig = scoreConfig,
		deck = deck,
		solvers = solvers,
		departed = {},
		metrics = PlaytestMetrics.begin(),
	}
	for userId, solver in solvers do
		if #deck > 0 then
			local prompt = promptAt(deck, solver.index)
			PlaytestMetrics.issue(round.metrics, matchId, userId, prompt.id, solver.issue, prompt.kind, solver.language, solver.multiplier, startedAt)
		end
	end
	return round
end

function QuestionRules.close(round: Round?)
	if round == nil then
		return
	end
	if round.metrics ~= nil then
		PlaytestMetrics.abandonOpen(round.metrics)
	end
	round.open = false
end

function QuestionRules.noteClock(round: Round?, now: number)
	if round == nil or round.metrics == nil then
		return
	end
	PlaytestMetrics.noteWindow(round.metrics, round.endsAt - now, round.scoreConfig.doubleSeconds, QuestionRules.standings(round))
end

function QuestionRules.forget(round: Round?, userId: number, now: number?)
	if round == nil or round.sealed then
		return
	end
	local solver = round.solvers[userId]
	if solver == nil then
		return
	end
	if round.metrics ~= nil then
		PlaytestMetrics.abandonUser(round.metrics, userId)
	end
	round.departed[userId] = {
		score = solver.score,
		words = solver.wordCount,
		sentences = solver.sentenceCount,
		language = solver.language,
		leftAt = if type(now) == "number" then now else round.startedAt,
	}
	round.solvers[userId] = nil
end

function QuestionRules.standings(round: Round): {Standing}
	local list: {Standing} = {}
	for userId, solver in round.solvers do
		table.insert(list, {
			userId = userId,
			score = solver.score,
			reachedAt = solver.reachedAt,
			rank = 0,
		})
	end
	table.sort(list, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		if a.reachedAt ~= b.reachedAt then
			return a.reachedAt < b.reachedAt
		end
		return a.userId < b.userId
	end)
	for index, row in list do
		row.rank = index
	end
	return list
end

function QuestionRules.leaderboard(round: Round): {Standing}
	if round.sealed and round.finalOrder ~= nil then
		return round.finalOrder
	end
	return QuestionRules.standings(round)
end

function QuestionRules.outcome(round: Round): {rows: {Outcome}, departed: {Outcome}}
	local order = QuestionRules.leaderboard(round)
	local rows: {Outcome} = table.create(#order)
	for index, standing in order do
		local solver = round.solvers[standing.userId]
		rows[index] = {
			userId = standing.userId,
			language = QuestionRules.languageCode(if solver ~= nil then solver.language else nil),
			rank = standing.rank,
			score = standing.score,
			words = if solver ~= nil then solver.wordCount else 0,
			sentences = if solver ~= nil then solver.sentenceCount else 0,
			finished = true,
		}
	end
	local departed: {Outcome} = {}
	for userId, stats in round.departed do
		table.insert(departed, {
			userId = userId,
			language = QuestionRules.languageCode(stats.language),
			rank = 0,
			score = stats.score,
			words = stats.words,
			sentences = stats.sentences,
			finished = false,
		})
	end
	table.sort(departed, function(a, b)
		return a.userId < b.userId
	end)
	return {
		rows = rows,
		departed = departed,
	}
end

function QuestionRules.seal(round: Round?)
	if round == nil or round.sealed then
		return
	end
	round.finalOrder = QuestionRules.standings(round)
	round.sealed = true
end

function QuestionRules.visibleRanks(rows: {Standing}, userId: number, limit: number): {Standing}
	local shown: {Standing} = {}
	local mine: Standing? = nil
	for _, row in rows do
		if row.rank <= limit then
			table.insert(shown, row)
		end
		if row.userId == userId then
			mine = row
		end
	end
	if mine ~= nil and mine.rank > limit then
		table.insert(shown, mine)
	end
	return shown
end

local function closed(round: Round?): Message
	return {
		ok = false,
		reason = "closed",
		matchId = if round ~= nil then round.matchId else 0,
	}
end

local function live(round: Round, now: number): boolean
	return round.open and now < round.endsAt and #round.deck > 0
end

local function stateMessage(round: Round, solver: Solver): Message
	local prompt = promptAt(round.deck, solver.index)
	return {
		ok = true,
		matchId = round.matchId,
		issue = solver.issue,
		questionId = prompt.id,
		text = QuestionRules.textFor(prompt, solver.language),
		score = prompt.score,
		points = prompt.score * solver.multiplier,
		multiplier = solver.multiplier,
		colorHex = prompt.colorHex,
		total = solver.score,
		typing = solver.language,
	}
end

local function echoMessage(round: Round, solver: Solver, awarded: boolean): Message
	return {
		ok = true,
		matchId = round.matchId,
		issue = solver.lastIssue,
		nextIssue = solver.lastNextIssue,
		nextQuestionId = solver.lastNextId,
		nextText = solver.lastNextText,
		awarded = awarded,
		total = solver.lastTotal,
		nextScore = solver.lastNextScore,
		nextPoints = solver.lastNextPoints,
		nextMultiplier = solver.lastNextMultiplier,
		nextColorHex = solver.lastNextColor,
		typing = solver.language,
	}
end

function QuestionRules.current(round: Round?, userId: number, now: number): Message
	if round == nil or not live(round, now) then
		return closed(round)
	end
	local solver = round.solvers[userId]
	if solver == nil then
		return {
			ok = false,
			reason = "not-participant",
			matchId = round.matchId,
		}
	end
	local prompt = promptAt(round.deck, solver.index)
	PlaytestMetrics.issue(round.metrics, round.matchId, userId, prompt.id, solver.issue, prompt.kind, solver.language, solver.multiplier, now)
	QuestionRules.noteClock(round, now)
	return stateMessage(round, solver)
end

function QuestionRules.submit(round: Round?, userId: number, matchId: number, issue: number, text: string, now: number, method: any): Message
	if round == nil then
		return closed(nil)
	end
	if matchId ~= round.matchId then
		return {
			ok = false,
			reason = "stale",
			matchId = round.matchId,
		}
	end
	if not live(round, now) then
		return closed(round)
	end
	QuestionRules.noteClock(round, now)
	local solver = round.solvers[userId]
	if solver == nil then
		return {
			ok = false,
			reason = "not-participant",
			matchId = round.matchId,
		}
	end
	text = QuestionRules.clip(text, QuestionRules.MaxInputLength)
	if solver.lastIssue == issue then
		return echoMessage(round, solver, false)
	end
	if issue ~= solver.issue then
		return {
			ok = false,
			reason = "bad-issue",
			matchId = round.matchId,
			issue = solver.issue,
		}
	end
	local prompt = promptAt(round.deck, solver.index)
	local answer = QuestionRules.textFor(prompt, solver.language)
	if not QuestionRules.matches(text, answer) then
		return {
			ok = false,
			reason = "mismatch",
			matchId = round.matchId,
			issue = solver.issue,
			questionId = prompt.id,
			text = answer,
		}
	end
	local completedIssue = solver.issue
	local issuedMultiplier = solver.multiplier
	if solver.scoredIssue ~= completedIssue then
		solver.strokes += HangulInput.strokes(answer)
		solver.score += prompt.score * issuedMultiplier
		solver.reachedAt = now
		solver.scoredIssue = completedIssue
		if prompt.kind == "Sentence" then
			solver.sentenceCount += 1
		else
			solver.wordCount += 1
		end
		PlaytestMetrics.complete(round.metrics, userId, completedIssue, now, method, prompt.score * issuedMultiplier)
	end
	solver.lastIssue = completedIssue
	solver.lastTotal = solver.score
	solver.issue += 1
	solver.index += 1
	local nextPrompt = promptAt(round.deck, solver.index)
	solver.multiplier = QuestionRules.multiplierFor(round.endsAt - now, round.scoreConfig)
	solver.lastNextIssue = solver.issue
	solver.lastNextId = nextPrompt.id
	solver.lastNextText = QuestionRules.textFor(nextPrompt, solver.language)
	solver.lastNextScore = nextPrompt.score
	solver.lastNextPoints = nextPrompt.score * solver.multiplier
	solver.lastNextMultiplier = solver.multiplier
	solver.lastNextColor = nextPrompt.colorHex
	PlaytestMetrics.issue(round.metrics, round.matchId, userId, nextPrompt.id, solver.issue, nextPrompt.kind, solver.language, solver.multiplier, now)
	return echoMessage(round, solver, true)
end

local function carriedTyping(session: ClientSession?, message: Message): string
	if type(message.typing) == "string" and message.typing ~= "" then
		return message.typing
	end
	if session ~= nil then
		return session.typing
	end
	return "en"
end

function QuestionRules.applyClient(session: ClientSession?, buffer: string, message: Message, activeMatchId: number): (ClientSession?, string)
	if type(message.matchId) ~= "number" or message.matchId ~= activeMatchId or activeMatchId <= 0 then
		return session, buffer
	end
	if session ~= nil
		and message.ok == true
		and message.issue == session.issue
		and message.nextIssue ~= nil
		and message.nextIssue ~= session.issue
	then
		local kept = ""
		if buffer ~= "" and buffer ~= session.text then
			kept = buffer
		end
		return {
			matchId = activeMatchId,
			issue = message.nextIssue,
			questionId = message.nextQuestionId or "",
			text = message.nextText or "",
			points = message.nextPoints or 0,
			multiplier = message.nextMultiplier or 1,
			colorHex = message.nextColorHex or "",
			total = message.total or 0,
			typing = carriedTyping(session, message),
		}, kept
	end
	if message.ok == true
		and message.nextIssue == nil
		and type(message.issue) == "number"
		and message.questionId ~= nil
		and message.text ~= nil
	then
		if session == nil or session.issue == message.issue then
			return {
				matchId = activeMatchId,
				issue = message.issue,
				questionId = message.questionId,
				text = message.text,
				points = message.points or 0,
				multiplier = message.multiplier or 1,
				colorHex = message.colorHex or "",
				total = message.total or (if session ~= nil then session.total else 0),
				typing = carriedTyping(session, message),
			}, buffer
		end
	end
	return session, buffer
end

function QuestionRules.acceptEnter(locked: boolean, buffer: string): boolean
	return locked ~= true and buffer ~= ""
end

function QuestionRules.selfCheck(rows: {SheetRow}, grades: {GradeRow}?)
	assert(QuestionRules.clientMatchId("Play", true, 4) == 4)
	assert(QuestionRules.clientMatchId("Result", true, 4) == 0, "result closes the typing screen")
	assert(QuestionRules.clientMatchId("Play", false, 4) == 0, "lobby players stay on the lobby HUD")
	assert(QuestionRules.clientMatchId("Play", true, 0) == 0)
	assert(QuestionRules.acceptEnter(false, "look out"), "a completed draft can be submitted")
	assert(not QuestionRules.acceptEnter(true, "look out"), "Enter after an auto-correct does not submit again")
	assert(not QuestionRules.acceptEnter(false, ""), "Enter on an empty next draft does not advance")

	local expected = {}
	for _, row in ipairs(rows) do
		if row.Enabled == "1" and row.Id ~= "" and row.en ~= "" then
			table.insert(expected, row)
		end
	end
	local deck = QuestionRules.deckFromRows(rows, grades)
	assert(#deck == #expected and #deck >= 1, "enabled deck")
	for index, row in ipairs(expected) do
		assert(deck[index].id == row.Id and deck[index].text == row.en)
		assert(#row.en <= QuestionRules.MaxInputLength)
		local parsed = tonumber(row.Score)
		assert(deck[index].score == (if type(parsed) == "number" then parsed else 0))
		if grades ~= nil and row.GradeId ~= nil and row.GradeId ~= "" then
			local color = "#FFFFFF"
			for _, grade in grades do
				if grade.Id == row.GradeId then
					color = grade.ColorHex
				end
			end
			assert(deck[index].colorHex == color)
		end
	end
	local hiddenRows = table.clone(rows)
	table.insert(hiddenRows, { Id = "disabled-test", Enabled = "0", en = "hidden" })
	local visible = QuestionRules.deckFromRows(hiddenRows)
	assert(#visible == #deck)
	for _, prompt in ipairs(visible) do
		assert(prompt.text ~= "hidden")
	end

	local first = deck[1]
	assert(QuestionRules.matches(string.upper(first.text), first.text))
	assert(not QuestionRules.matches(first.text .. " ", first.text))
	if #first.text > 0 then
		assert(not QuestionRules.matches(string.sub(first.text, 1, #first.text - 1), first.text))
	end
	for _, prompt in ipairs(deck) do
		if string.find(prompt.text, " ", 1, true) ~= nil then
			assert(not QuestionRules.matches(string.gsub(prompt.text, " ", ""), prompt.text), "internal spaces stay")
			assert(QuestionRules.matches(string.upper(prompt.text), prompt.text))
			break
		end
	end

	local round = QuestionRules.begin(deck, 4, 100, { 10, 20 })
	local mine = QuestionRules.current(round, 10, 50)
	local theirs = QuestionRules.current(round, 20, 50)
	assert(mine.ok and theirs.ok)
	assert(mine.issue == 1 and theirs.issue == 1)
	assert(mine.questionId == first.id and theirs.questionId == first.id)
	assert(mine.text == first.text and theirs.text == first.text)
	local repeatCurrent = QuestionRules.current(round, 10, 50)
	assert(repeatCurrent.issue == 1 and repeatCurrent.text == first.text and repeatCurrent.questionId == first.id)

	local wrong = QuestionRules.submit(round, 10, 4, 1, "nope", 50)
	assert(wrong.ok == false and wrong.reason == "mismatch" and wrong.nextIssue == nil)
	local unchanged = QuestionRules.current(round, 10, 50)
	assert(unchanged.issue == 1 and unchanged.text == first.text)

	local done = QuestionRules.submit(round, 10, 4, 1, string.upper(first.text), 99.999)
	assert(done.ok and done.issue == 1 and done.nextIssue == 2 and done.nextText ~= nil)
	local nextText = done.nextText :: string
	local duplicate = QuestionRules.submit(round, 10, 4, 1, string.upper(first.text), 99.999)
	assert(duplicate.ok and duplicate.nextIssue == 2 and duplicate.nextText == nextText)
	local advanced = QuestionRules.current(round, 10, 50)
	assert(advanced.issue == 2 and advanced.text == nextText, "duplicate submit does not skip")
	local partner = QuestionRules.current(round, 20, 50)
	assert(partner.issue == 1 and partner.text == first.text and partner.questionId == first.id)

	local older = QuestionRules.submit(round, 10, 4, 0, first.text, 50)
	assert(older.reason == "bad-issue")
	assert(QuestionRules.current(round, 10, 50).issue == 2)

	local cycling = QuestionRules.begin(deck, 8, 500, { 3 })
	local expectText = first.text
	for step = 1, #deck + 1 do
		local current = QuestionRules.current(cycling, 3, 10)
		assert(current.ok and current.issue == step and current.text == expectText)
		local completed = QuestionRules.submit(cycling, 3, 8, step, current.text :: string, 10)
		assert(completed.ok and completed.nextIssue == step + 1 and completed.nextText ~= nil)
		expectText = completed.nextText :: string
	end
	local wrapped = QuestionRules.current(cycling, 3, 10)
	assert(wrapped.issue == #deck + 2)
	if #deck == 1 then
		assert(wrapped.text == first.text)
	else
		assert(wrapped.text == deck[2].text, "the deck continues after the last prompt")
	end

	local timed = QuestionRules.begin(deck, 9, 30, { 1 })
	local justBefore = QuestionRules.submit(timed, 1, 9, 1, first.text, 29.999)
	assert(justBefore.ok and justBefore.nextIssue == 2)
	QuestionRules.close(timed)
	local afterClose = QuestionRules.submit(timed, 1, 9, 2, justBefore.nextText or "", 10)
	assert(afterClose.ok == false and afterClose.reason == "closed")

	local deadline = QuestionRules.begin(deck, 9, 30, { 1 })
	local tooLate = QuestionRules.submit(deadline, 1, 9, 1, first.text, 30)
	assert(tooLate.ok == false and tooLate.reason == "closed")
	local stillFirst = QuestionRules.current(deadline, 1, 29.999)
	assert(stillFirst.ok and stillFirst.issue == 1 and stillFirst.text == first.text)

	local fresh = QuestionRules.begin(deck, 2, 100, { 5 })
	local stale = QuestionRules.submit(fresh, 5, 1, 1, first.text, 10)
	assert(stale.reason == "stale")
	assert(QuestionRules.current(fresh, 5, 10).issue == 1)
	local outsider = QuestionRules.submit(fresh, 6, 2, 1, first.text, 10)
	assert(outsider.reason == "not-participant")
	QuestionRules.forget(fresh, 5)
	assert(QuestionRules.submit(fresh, 5, 2, 1, first.text, 10).reason == "not-participant")
	assert(QuestionRules.current(nil, 5, 10).reason == "closed")

	local session: ClientSession? = nil
	local buffer = ""
	session, buffer = QuestionRules.applyClient(session, buffer, mine, 4)
	assert(session ~= nil and session.issue == 1 and session.text == first.text and buffer == "")
	buffer = string.sub(first.text, 1, 1)
	local keptSession, keptBuffer = QuestionRules.applyClient(session, buffer, mine, 4)
	assert(keptSession ~= nil and keptSession.issue == 1 and keptBuffer == buffer, "re-request keeps the draft")
	local moved, cleared = QuestionRules.applyClient(session, first.text, done, 4)
	assert(moved ~= nil and moved.issue == 2 and moved.text == nextText and cleared == "")
	local early, keptNext = QuestionRules.applyClient(session, "b", done, 4)
	assert(early ~= nil and early.issue == 2 and keptNext == "b", "a character typed before the result stays")
	local stayed, typed = QuestionRules.applyClient(moved, "s", done, 4)
	assert(stayed ~= nil and stayed.issue == 2 and typed == "s", "a second completion packet keeps the new draft")
	local otherMatch, otherBuffer = QuestionRules.applyClient(moved, "s", done, 99)
	assert(otherMatch ~= nil and otherMatch.issue == 2 and otherBuffer == "s")
	local lateSession, lateBuffer = QuestionRules.applyClient(session, "next", done, 0)
	assert(lateSession ~= nil and lateSession.issue == 1 and lateBuffer == "next")

	local scoreConfig: ScoreConfig = { doubleSeconds = 30, multiplier = 2 }
	local normal = QuestionRules.begin(deck, 15, 500, { 4 }, 0, scoreConfig)
	local total = 0
	assert(HangulInput.strokes("ab cd") == 5 and HangulInput.strokes("과 값") == 8, "CPM counts spaces and Dubeolsik compound strokes")
	local expectedStrokes = 0
	local steps = math.min(3, #deck)
	for step = 1, steps do
		local current = QuestionRules.current(normal, 4, 10)
		assert(current.multiplier == 1 and current.points == deck[step].score)
		local scored = QuestionRules.submit(normal, 4, 15, step, current.text :: string, 10)
		total += deck[step].score
		assert(scored.awarded == true and scored.total == total, "first completion adds the issued prompt")
		local replay = QuestionRules.submit(normal, 4, 15, step, current.text :: string, 10)
		assert(replay.awarded == false and replay.total == total, "a repeated submit does not score again")
		expectedStrokes += HangulInput.strokes(current.text :: string)
		assert(normal.solvers[4].strokes == expectedStrokes, "a replay never adds typing strokes")
	end
	if steps >= 3 and deck[1].score == 10 and deck[2].score == 10 and deck[3].score == 25 then
		assert(total == 45, "sample questions accumulate 10, 20, 45")
	end
	if steps >= 3 and deck[1].kind == "Word" and deck[2].kind == "Word" and deck[3].kind == "Sentence" then
		local solver = normal.solvers[4]
		assert(solver.wordCount == 2 and solver.sentenceCount == 1, "a repeated submit does not add another answer")
	end
	if steps == #deck then
		local wrappedScore = QuestionRules.current(normal, 4, 10)
		assert(wrappedScore.text == deck[1].text)
		local again = QuestionRules.submit(normal, 4, 15, steps + 1, wrappedScore.text :: string, 10)
		assert(again.awarded == true and again.total == total + deck[1].score, "a repeated prompt id scores on a new issue")
	end

	local endsAt = 120
	local issuedAt = endsAt - 31
	local boundary = QuestionRules.begin(deck, 11, endsAt, { 1 }, issuedAt, scoreConfig)
	local earlyCard = QuestionRules.current(boundary, 1, issuedAt)
	assert(earlyCard.multiplier == 1 and earlyCard.points == deck[1].score, "31 seconds stays at the base score")
	local solvedAt = endsAt - 29
	local baseAward = QuestionRules.submit(boundary, 1, 11, 1, deck[1].text, solvedAt)
	assert(baseAward.total == deck[1].score and baseAward.nextMultiplier == 2)
	if #deck >= 2 then
		assert(baseAward.nextPoints == deck[2].score * 2, "the next prompt locks 2x at issue time")
	end
	local reread = QuestionRules.current(boundary, 1, endsAt - 5)
	assert(reread.multiplier == baseAward.nextMultiplier and reread.points == baseAward.nextPoints, "re-request keeps the issued multiplier")
	local echoed = QuestionRules.submit(boundary, 1, 11, 1, deck[1].text, solvedAt)
	assert(echoed.awarded == false and echoed.total == baseAward.total)

	local atThirty = QuestionRules.begin(deck, 12, endsAt, { 1 }, endsAt - 30, scoreConfig)
	assert(QuestionRules.current(atThirty, 1, endsAt - 30).multiplier == 2, "exactly 30 seconds is double")
	local outside = QuestionRules.begin(deck, 13, endsAt, { 1 }, endsAt - 30.001, scoreConfig)
	assert(QuestionRules.current(outside, 1, endsAt - 30.001).multiplier == 1)
	local expired = QuestionRules.begin(deck, 14, endsAt, { 1 }, issuedAt, scoreConfig)
	local rejected = QuestionRules.submit(expired, 1, 14, 1, deck[1].text, endsAt)
	assert(rejected.reason == "closed" and QuestionRules.standings(expired)[1].score == 0, "the deadline adds nothing")

	local ordered = QuestionRules.begin(deck, 16, 1000, { 9, 2 }, 0, scoreConfig)
	local zeros = QuestionRules.standings(ordered)
	assert(zeros[1].userId == 2 and zeros[1].score == 0 and zeros[2].userId == 9, "zero scores share the start and UserId breaks the tie")
	QuestionRules.submit(ordered, 9, 16, 1, deck[1].text, 10)
	QuestionRules.submit(ordered, 2, 16, 1, deck[1].text, 11)
	local chased = QuestionRules.standings(ordered)
	assert(chased[1].userId == 9 and chased[2].userId == 2 and chased[1].score == chased[2].score, "the earlier equal score stays ahead")
	local sameTime = QuestionRules.begin(deck, 17, 1000, { 9, 2 }, 0, scoreConfig)
	QuestionRules.submit(sameTime, 9, 17, 1, deck[1].text, 5)
	QuestionRules.submit(sameTime, 2, 17, 1, deck[1].text, 5)
	assert(QuestionRules.standings(sameTime)[1].userId == 2, "the same reach time keeps the smaller UserId")

	local finalRound = QuestionRules.begin(deck, 18, 1000, { 3 }, 0, scoreConfig)
	QuestionRules.submit(finalRound, 3, 18, 1, deck[1].text, 4)
	QuestionRules.seal(finalRound)
	local frozen = QuestionRules.leaderboard(finalRound)
	QuestionRules.forget(finalRound, 3)
	local still = QuestionRules.leaderboard(finalRound)
	assert(still[1].userId == 3 and still[1].score == frozen[1].score, "a sealed result stays readable")

	local sample: {Standing} = {}
	for index = 1, 6 do
		sample[index] = { userId = index, score = 7 - index, reachedAt = index, rank = index }
	end
	assert(#QuestionRules.visibleRanks(sample, 6, 5) == 6, "a player outside the top five is added once")
	assert(#QuestionRules.visibleRanks(sample, 2, 5) == 5, "a player already in the top five is not repeated")

	local missingId, missingColumn = QuestionRules.missingText(rows, { "en", "ko" })
	assert(missingId == nil and missingColumn == nil, "enabled questions have every typing column")
	if rows[1] ~= nil then
		local blank = table.clone(rows[1])
		blank.Enabled = "1"
		blank.ko = ""
		local blankId, blankColumn = QuestionRules.missingText({ blank }, { "ko" })
		assert(blankId == blank.Id and blankColumn == "ko", "an empty Korean cell names the question and column")
	end
	assert(not QuestionRules.matches("벼", "별"), "a syllable without the final consonant is not the answer")
	assert(QuestionRules.matches("별", "별"))
	assert(QuestionRules.clip("사과", 1) == "사" and QuestionRules.clip("사과", 2) == "사과", "a length limit keeps a Hangul character whole")
	assert(QuestionRules.autoSubmits("en") and QuestionRules.autoSubmits("ko") and QuestionRules.autoSubmits("ja"), "a displayed answer advances in every typing language")
	assert(QuestionRules.usesIme("ko") and QuestionRules.usesIme("ja") and not QuestionRules.usesIme("en"), "English does not use an IME field")
	local appleCaret = utf8.offset("사과", 2)
	assert(appleCaret ~= nil and QuestionRules.fieldAnswer("사과", appleCaret :: number, "사과") == "사과", "text after the caret still belongs to the answer")
	assert(QuestionRules.matches(QuestionRules.fieldAnswer("사", appleCaret :: number, "사과"), "사과"), "a syllable shown in the field completes the answer")
	assert(not QuestionRules.matches(QuestionRules.fieldAnswer("사", appleCaret :: number, "사"), "사과"), "a missing syllable does not match")
	assert(not QuestionRules.matches(QuestionRules.fieldAnswer("벼", 1, "벼"), "별"), "an unfinished syllable stays on the prompt")
	assert(QuestionRules.matches(QuestionRules.fieldAnswer("별", 1, "별"), "별"), "the finished syllable matches with the caret in front")
	local sentence = "우리는 함께 놀아요"
	local lastCaret = utf8.offset(sentence, -1)
	assert(lastCaret ~= nil and QuestionRules.matches(QuestionRules.fieldAnswer(sentence, lastCaret :: number, sentence), sentence), "the sentence matches when its last syllable is displayed")
	assert(not QuestionRules.matches(QuestionRules.fieldAnswer(string.sub(sentence, 1, (lastCaret :: number) - 1), lastCaret :: number, string.sub(sentence, 1, (lastCaret :: number) - 1)), sentence), "a sentence without its last syllable waits")
	assert(not QuestionRules.matches("우리는함께 놀아요", sentence), "a missing space stays incomplete")
	assert(QuestionRules.matches(QuestionRules.fieldAnswer("play now", 5, "play now"), "play now"), "a space already in the field counts")
	assert(not QuestionRules.matches(QuestionRules.fieldAnswer("playnow", 5, "playnow"), "play now"), "a missing space does not match")
	assert(not QuestionRules.matches(QuestionRules.fieldAnswer("あ", 1, "あ"), "亜"), "a conversion candidate outside the field is not an answer")
	assert(QuestionRules.matches(QuestionRules.fieldAnswer("亜", 1, "亜"), "亜"), "a conversion shown in the field matches")
	assert(QuestionRules.revives("사과", "사과") and QuestionRules.revives("과", "사과") and QuestionRules.revives("사과 ", "사과"), "a late commit of the accepted answer is the same answer")
	assert(not QuestionRules.revives("사", "사과") and not QuestionRules.revives("별", "사과"), "a new draft is not a late commit")
	local compose = QuestionRules.composeIdle()
	local action: string
	compose, action = QuestionRules.composeEvent(compose, "text", "벼", nil)
	assert(action == "show" and not compose.pending, "a composing syllable is only shown")
	compose, action = QuestionRules.composeEvent(compose, "text", "별", nil)
	assert(action == "show", "a finished syllable is still a text change")
	compose = QuestionRules.composeIdle()
	compose, action = QuestionRules.composeEvent(compose, "text", "사", nil)
	assert(action == "show")
	compose, action = QuestionRules.composeEvent(compose, "enter", "사", true)
	assert(action == "wait" and compose.pending, "Enter that the IME consumes waits for the committed text")
	compose, action = QuestionRules.composeEvent(compose, "text", "사과", nil)
	assert(action == "submit" and not compose.pending, "the committed text is submitted once")
	compose, action = QuestionRules.composeEvent(compose, "blur", "사과", nil)
	assert(action == "ignore", "focus loss after the commit does not submit again")
	compose = QuestionRules.composeIdle()
	compose, action = QuestionRules.composeEvent(compose, "enter", "사과", false)
	assert(action == "ignore")
	compose, action = QuestionRules.composeEvent(compose, "blur", "사과", nil)
	assert(action == "submit", "Enter that the field already holds is submitted on focus loss")
	compose, action = QuestionRules.composeEvent(compose, "blur", "사과", nil)
	assert(action == "ignore", "a second focus loss does not submit again")
	compose = QuestionRules.composeIdle()
	compose, action = QuestionRules.composeEvent(compose, "enter", "별", true)
	compose, action = QuestionRules.composeEvent(compose, "key", "별", nil)
	assert(action == "ignore" and not compose.pending, "the next key is not the commit")
	compose, action = QuestionRules.composeEvent(compose, "blur", "별", nil)
	assert(action == "ignore", "a key before focus loss does not submit the old text")
	compose, action = QuestionRules.composeEvent(compose, "text", "ㅂ", nil)
	assert(action == "show", "the next character stays a draft")
	compose = QuestionRules.composeIdle()
	compose, action = QuestionRules.composeEvent(compose, "enter", "", true)
	assert(action == "ignore" and not compose.pending, "Enter after a cleared field does not wait")
	compose, action = QuestionRules.composeEvent(compose, "text", "ㅂ", nil)
	assert(action == "show", "the next character after Enter stays a draft")
	assert(QuestionRules.languageCode("en") == "EN" and QuestionRules.languageCode("ko") == "KO", "rank labels use the issued language")

	local shared: {Prompt} = {
		{
			id = "sample-word",
			text = "mark",
			texts = { en = "mark", ko = "별" },
			score = 10,
			gradeId = "",
			colorHex = "#FFFFFF",
			kind = "Word",
		},
		{
			id = "sample-line",
			text = "play now",
			texts = { en = "play now", ko = "사과" },
			score = 25,
			gradeId = "",
			colorHex = "#FFFFFF",
			kind = "Sentence",
		},
	}
	local pair = QuestionRules.begin(shared, 21, 1000, { 1, 2 }, 0, scoreConfig, nil, { [1] = "en", [2] = "ko" })
	local englishCard = QuestionRules.current(pair, 1, 10)
	local koreanCard = QuestionRules.current(pair, 2, 10)
	assert(englishCard.questionId == koreanCard.questionId and englishCard.text == "mark" and koreanCard.text == "별", "the same question id uses each player's column")
	assert(englishCard.points == koreanCard.points and englishCard.typing == "en" and koreanCard.typing == "ko", "both languages share the issued score")
	local partial = QuestionRules.submit(pair, 2, 21, 1, "벼", 10)
	assert(partial.reason == "mismatch" and partial.nextIssue == nil, "Korean does not submit before the final consonant")
	local koreanDone = QuestionRules.submit(pair, 2, 21, 1, "별", 10)
	assert(koreanDone.awarded == true and koreanDone.total == 10 and koreanDone.nextText == "사과", "Enter scores the issued Korean text")
	local koreanAgain = QuestionRules.submit(pair, 2, 21, 1, "별", 10)
	assert(koreanAgain.awarded == false and koreanAgain.total == 10, "one Enter scores the Korean prompt once")
	local englishStill = QuestionRules.current(pair, 1, 10)
	assert(englishStill.issue == 1 and englishStill.text == "mark", "the other player's issue stays put")
	local englishDone = QuestionRules.submit(pair, 1, 21, 1, "MARK", 12)
	assert(englishDone.awarded == true and englishDone.total == 10 and englishDone.nextText == "play now", "English keeps case-insensitive scoring")
	local pairOrder = QuestionRules.standings(pair)
	assert(pairOrder[1].score == pairOrder[2].score and pairOrder[1].score == 10, "the two languages share the score rule")
	QuestionRules.forget(pair, 2)
	assert(pair.departed[2] ~= nil and pair.departed[2].language == "ko", "a departure keeps the language used in this match")
end

return QuestionRules

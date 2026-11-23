--!strict
-- Shared question order and completion rules. No instances and no sample prompts.

export type SheetRow = {
	Id: string,
	Enabled: string,
	en: string,
}

export type Prompt = {
	id: string,
	text: string,
}

export type Solver = {
	issue: number,
	index: number,
	lastIssue: number?,
	lastNextIssue: number?,
	lastNextId: string?,
	lastNextText: string?,
}

export type Round = {
	matchId: number,
	endsAt: number,
	open: boolean,
	deck: {Prompt},
	solvers: {[number]: Solver},
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
}

export type ClientSession = {
	matchId: number,
	issue: number,
	questionId: string,
	text: string,
}

local QuestionRules = {}

QuestionRules.MaxInputLength = 200

function QuestionRules.clientMatchId(phase: string?, inMatch: boolean, matchId: number?): number
	if phase ~= "Play" or inMatch ~= true then
		return 0
	end
	if type(matchId) ~= "number" or matchId <= 0 then
		return 0
	end
	return matchId
end

function QuestionRules.deckFromRows(rows: {SheetRow}): {Prompt}
	local deck = {}
	for _, row in ipairs(rows) do
		if row.Enabled == "1" and row.Id ~= "" and row.en ~= "" then
			table.insert(deck, table.freeze({
				id = row.Id,
				text = row.en,
			}))
		end
	end
	return table.freeze(deck)
end

function QuestionRules.matches(input: string, answer: string): boolean
	return string.lower(input) == string.lower(answer)
end

local function promptAt(deck: {Prompt}, index: number): Prompt
	local count = #deck
	return deck[(index - 1) % count + 1]
end

function QuestionRules.begin(deck: {Prompt}, matchId: number, endsAt: number, userIds: {number}): Round
	local solvers: {[number]: Solver} = {}
	for _, userId in ipairs(userIds) do
		solvers[userId] = {
			issue = 1,
			index = 1,
		}
	end
	return {
		matchId = matchId,
		endsAt = endsAt,
		open = true,
		deck = deck,
		solvers = solvers,
	}
end

function QuestionRules.close(round: Round?)
	if round ~= nil then
		round.open = false
	end
end

function QuestionRules.forget(round: Round?, userId: number)
	if round ~= nil then
		round.solvers[userId] = nil
	end
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
		text = prompt.text,
	}
end

local function echoMessage(round: Round, solver: Solver): Message
	return {
		ok = true,
		matchId = round.matchId,
		issue = solver.lastIssue,
		nextIssue = solver.lastNextIssue,
		nextQuestionId = solver.lastNextId,
		nextText = solver.lastNextText,
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
	return stateMessage(round, solver)
end

function QuestionRules.submit(round: Round?, userId: number, matchId: number, issue: number, text: string, now: number): Message
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
	local solver = round.solvers[userId]
	if solver == nil then
		return {
			ok = false,
			reason = "not-participant",
			matchId = round.matchId,
		}
	end
	if #text > QuestionRules.MaxInputLength then
		text = string.sub(text, 1, QuestionRules.MaxInputLength)
	end
	if solver.lastIssue == issue then
		return echoMessage(round, solver)
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
	if not QuestionRules.matches(text, prompt.text) then
		return {
			ok = false,
			reason = "mismatch",
			matchId = round.matchId,
			issue = solver.issue,
			questionId = prompt.id,
			text = prompt.text,
		}
	end
	solver.lastIssue = solver.issue
	solver.issue += 1
	solver.index += 1
	local nextPrompt = promptAt(round.deck, solver.index)
	solver.lastNextIssue = solver.issue
	solver.lastNextId = nextPrompt.id
	solver.lastNextText = nextPrompt.text
	return echoMessage(round, solver)
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
		return {
			matchId = activeMatchId,
			issue = message.nextIssue,
			questionId = message.nextQuestionId or "",
			text = message.nextText or "",
		}, ""
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
			}, buffer
		end
	end
	return session, buffer
end

function QuestionRules.selfCheck(rows: {SheetRow})
	assert(QuestionRules.clientMatchId("Play", true, 4) == 4)
	assert(QuestionRules.clientMatchId("Result", true, 4) == 0, "result closes the typing screen")
	assert(QuestionRules.clientMatchId("Play", false, 4) == 0, "lobby players stay on the lobby HUD")
	assert(QuestionRules.clientMatchId("Play", true, 0) == 0)

	local expected = {}
	for _, row in ipairs(rows) do
		if row.Enabled == "1" and row.Id ~= "" and row.en ~= "" then
			table.insert(expected, row)
		end
	end
	local deck = QuestionRules.deckFromRows(rows)
	assert(#deck == #expected and #deck >= 1, "enabled deck")
	for index, row in ipairs(expected) do
		assert(deck[index].id == row.Id and deck[index].text == row.en)
		assert(#row.en <= QuestionRules.MaxInputLength)
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
	local stayed, typed = QuestionRules.applyClient(moved, "s", done, 4)
	assert(stayed ~= nil and stayed.issue == 2 and typed == "s", "a second completion packet keeps the new draft")
	local otherMatch, otherBuffer = QuestionRules.applyClient(moved, "s", done, 99)
	assert(otherMatch ~= nil and otherMatch.issue == 2 and otherBuffer == "s")
	local lateSession, lateBuffer = QuestionRules.applyClient(session, "next", done, 0)
	assert(lateSession ~= nil and lateSession.issue == 1 and lateBuffer == "next")
end

return QuestionRules

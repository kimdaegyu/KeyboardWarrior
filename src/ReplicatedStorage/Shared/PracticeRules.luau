--!strict
-- Personal practice. The deck comes from the question sheet. Nothing here is scored or saved.

export type SheetRow = {
	Id: string,
	Enabled: string,
	en: string,
	ko: string?,
	Kind: string?,
}

export type Prompt = {
	id: string,
	text: string,
	kind: string,
}

export type Session = {
	mode: string,
	index: number,
	solved: number,
	buffer: string,
	busy: boolean,
}

local PracticeRules = {}

PracticeRules.MaxInputLength = 200

local function clipText(text: string, limit: number): string
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

function PracticeRules.matches(input: string, answer: string): boolean
	return string.lower(input) == string.lower(answer)
end

function PracticeRules.catalog(rows: {SheetRow}, column: string?): ({Prompt}, {Prompt})
	local name = if column ~= nil and column ~= "" then column else "en"
	local words: {Prompt} = {}
	local sentences: {Prompt} = {}
	for _, row in rows do
		local text = if name == "en" then row.en else (row :: any)[name]
		if row.Enabled == "1" and row.Id ~= "" and type(text) == "string" and text ~= "" then
			local prompt: Prompt = {
				id = row.Id,
				text = text,
				kind = if row.Kind == "Sentence" then "Sentence" else "Word",
			}
			if row.Kind == "Sentence" then
				table.insert(sentences, prompt)
			elseif row.Kind == "Word" then
				table.insert(words, prompt)
			end
		end
	end
	return words, sentences
end

function PracticeRules.begin(): Session
	return {
		mode = "Word",
		index = 1,
		solved = 0,
		buffer = "",
		busy = false,
	}
end

function PracticeRules.prompt(session: Session, words: {Prompt}, sentences: {Prompt}): Prompt?
	local deck = if session.mode == "Sentence" then sentences else words
	if #deck == 0 then
		return nil
	end
	local index = (session.index - 1) % #deck + 1
	return deck[index]
end

function PracticeRules.setMode(session: Session, mode: string)
	if mode ~= "Word" and mode ~= "Sentence" then
		return
	end
	if session.mode == mode then
		session.buffer = ""
		return
	end
	session.mode = mode
	session.index = 1
	session.buffer = ""
	session.busy = false
end

local function complete(session: Session, words: {Prompt}, sentences: {Prompt})
	if session.busy then
		return
	end
	local current = PracticeRules.prompt(session, words, sentences)
	if current == nil or not PracticeRules.matches(session.buffer, current.text) then
		return
	end
	session.busy = true
	session.solved += 1
	session.index += 1
	session.buffer = ""
	session.busy = false
end

function PracticeRules.applyText(session: Session, words: {Prompt}, sentences: {Prompt}, text: string, hold: boolean?)
	if session.busy then
		return
	end
	if PracticeRules.prompt(session, words, sentences) == nil then
		session.buffer = ""
		return
	end
	session.buffer = clipText(text, PracticeRules.MaxInputLength)
	if hold ~= true then
		complete(session, words, sentences)
	end
end

function PracticeRules.enter(session: Session, words: {Prompt}, sentences: {Prompt})
	complete(session, words, sentences)
end

function PracticeRules.blockedByMatch(inMatch: boolean, phase: string?, resultDismissed: boolean?): boolean
	return inMatch and (phase == "Play" or phase == "Ready" or (phase == "Result" and not resultDismissed))
end

function PracticeRules.selfCheck(rows: {SheetRow})
	local words, sentences = PracticeRules.catalog(rows)
	local session = PracticeRules.begin()
	assert(session.mode == "Word" and session.solved == 0 and session.buffer == "")
	local first = PracticeRules.prompt(session, words, sentences)
	assert(first ~= nil, "word practice has a prompt")
	assert(not PracticeRules.blockedByMatch(false, "Play"), "another match does not close practice")
	assert(PracticeRules.blockedByMatch(true, "Play") and PracticeRules.blockedByMatch(true, "Result") and PracticeRules.blockedByMatch(true, "Ready"), "a confirmed participant leaves practice")
	assert(not PracticeRules.blockedByMatch(false, "Ready"), "a lobby player can keep practicing through the ready count")
	assert(not PracticeRules.blockedByMatch(true, "Result", true) and PracticeRules.blockedByMatch(true, "Play", true), "closing results unlocks only the post-match HUD")
	assert(not PracticeRules.blockedByMatch(false, "Result"), "a spectator can keep practicing through results")

	PracticeRules.applyText(session, words, sentences, string.upper(first.text))
	assert(session.solved == 1 and session.buffer == "", "a matching answer clears the draft")
	PracticeRules.enter(session, words, sentences)
	assert(session.solved == 1, "Enter after auto-complete does not solve a second prompt")

	local solved = session.solved
	session.buffer = "zz"
	PracticeRules.enter(session, words, sentences)
	assert(session.buffer == "zz" and session.solved == solved, "an incomplete Enter keeps the draft")
	PracticeRules.setMode(session, "Sentence")
	assert(session.buffer == "" and session.solved == solved and session.mode == "Sentence", "switching mode clears only the draft")

	local sentence = PracticeRules.prompt(session, words, sentences)
	if sentence ~= nil then
		local seen = sentence.text
		PracticeRules.applyText(session, words, sentences, seen)
		local again = PracticeRules.prompt(session, words, sentences)
		local nextText = if #sentences <= 1 then seen else sentences[2].text
		assert(session.buffer == "" and again ~= nil and again.text == nextText, "a finished sentence clears the draft and advances")
		assert(session.solved == solved + 1, "the sentence counts once")
	end

	local fresh = PracticeRules.begin()
	assert(fresh.solved == 0, "a new practice session starts at zero")
	local empty = PracticeRules.begin()
	PracticeRules.applyText(empty, {}, {}, "text")
	assert(empty.solved == 0 and empty.buffer == "", "an empty deck does not accept an answer")

	if #words > 0 then
		local cycle = PracticeRules.begin()
		local firstWord = PracticeRules.prompt(cycle, words, sentences)
		assert(firstWord ~= nil, "word cycle starts")
		local firstText = (firstWord :: Prompt).text
		for _ = 1, #words do
			local current = PracticeRules.prompt(cycle, words, sentences)
			assert(current ~= nil, "word deck has a prompt")
			PracticeRules.applyText(cycle, words, sentences, (current :: Prompt).text)
		end
		local wrapped = PracticeRules.prompt(cycle, words, sentences)
		assert(wrapped ~= nil and (wrapped :: Prompt).text == firstText, "word practice cycles")
		assert(cycle.buffer == "" and cycle.solved == #words, "each word in the cycle counts once")
	end

	if #sentences > 0 then
		local cycle = PracticeRules.begin()
		PracticeRules.setMode(cycle, "Sentence")
		local firstSentence = PracticeRules.prompt(cycle, words, sentences)
		assert(firstSentence ~= nil, "sentence cycle starts")
		local firstText = (firstSentence :: Prompt).text
		for _ = 1, #sentences do
			local current = PracticeRules.prompt(cycle, words, sentences)
			assert(current ~= nil, "sentence deck has a prompt")
			PracticeRules.applyText(cycle, words, sentences, (current :: Prompt).text)
		end
		local wrapped = PracticeRules.prompt(cycle, words, sentences)
		assert(wrapped ~= nil and (wrapped :: Prompt).text == firstText, "sentence practice cycles")
		assert(cycle.buffer == "" and cycle.solved == #sentences, "each sentence in the cycle counts once")
	end

	if #words > 0 then
		local book = PracticeRules.begin()
		local foundBook = false
		for _ = 1, #words do
			local prompt = PracticeRules.prompt(book, words, sentences)
			if prompt ~= nil and prompt.text == "book" then
				foundBook = true
				local before = book.solved
				PracticeRules.applyText(book, words, sentences, "boo")
				assert(book.solved == before and book.buffer == "boo", "one o does not finish book")
				PracticeRules.applyText(book, words, sentences, "book")
				assert(book.solved == before + 1 and book.buffer == "", "both o letters finish book once")
				PracticeRules.enter(book, words, sentences)
				assert(book.solved == before + 1, "Enter after book does not finish the next word")
				break
			end
			if prompt ~= nil then
				PracticeRules.applyText(book, words, sentences, prompt.text)
			end
		end
		assert(foundBook, "the English word deck includes book")
	end

	local koWords, koSentences = PracticeRules.catalog(rows, "ko")
	if #koWords > 0 then
		local ko = PracticeRules.begin()
		local firstKo = PracticeRules.prompt(ko, koWords, koSentences)
		assert(firstKo ~= nil, "Korean word practice has a prompt")
		local answer = (firstKo :: Prompt).text
		local boundary = utf8.offset(answer, 2)
		if boundary ~= nil then
			local prefix = string.sub(answer, 1, boundary - 1)
			PracticeRules.applyText(ko, koWords, koSentences, prefix)
			assert(ko.solved == 0 and ko.buffer == prefix, "a partial Korean answer stays on the prompt")
		end
		PracticeRules.applyText(ko, koWords, koSentences, answer .. "x")
		assert(ko.solved == 0, "a typo does not advance")
		PracticeRules.applyText(ko, koWords, koSentences, answer)
		assert(ko.solved == 1 and ko.buffer == "", "a corrected Korean answer advances once")
		PracticeRules.enter(ko, koWords, koSentences)
		assert(ko.solved == 1 and ko.buffer == "", "Enter after auto-complete does not score the next prompt")
		local syllable = PracticeRules.begin()
		local foundSyllable = false
		for _ = 1, #koWords do
			local prompt = PracticeRules.prompt(syllable, koWords, koSentences)
			if prompt ~= nil and prompt.text == "별" then
				foundSyllable = true
				local before = syllable.solved
				PracticeRules.applyText(syllable, koWords, koSentences, "벼")
				assert(syllable.solved == before and syllable.buffer == "벼", "an unfinished syllable does not advance")
				PracticeRules.applyText(syllable, koWords, koSentences, "별")
				assert(syllable.solved == before + 1 and syllable.buffer == "", "the finished syllable advances once")
				PracticeRules.enter(syllable, koWords, koSentences)
				assert(syllable.solved == before + 1, "Enter after the finished syllable does not advance again")
				break
			end
			if prompt ~= nil then
				PracticeRules.applyText(syllable, koWords, koSentences, prompt.text)
			end
		end
		assert(foundSyllable, "the Korean word deck includes the syllable check")
		local chicken = PracticeRules.begin()
		local foundChicken = false
		for _ = 1, #koWords do
			local prompt = PracticeRules.prompt(chicken, koWords, koSentences)
			if prompt ~= nil and prompt.text == "닭" then
				foundChicken = true
				local before = chicken.solved
				PracticeRules.applyText(chicken, koWords, koSentences, "달")
				assert(chicken.solved == before and chicken.buffer == "달", "닭 waits while the syllable is still 달")
				PracticeRules.applyText(chicken, koWords, koSentences, "닭")
				assert(chicken.solved == before + 1 and chicken.buffer == "", "the final batchim completes 닭 once")
				PracticeRules.enter(chicken, koWords, koSentences)
				assert(chicken.solved == before + 1, "Enter after 닭 does not complete the next prompt")
				break
			end
			if prompt ~= nil then
				PracticeRules.applyText(chicken, koWords, koSentences, prompt.text)
			end
		end
		assert(foundChicken, "the Korean word deck includes 닭")
	end
end

return PracticeRules

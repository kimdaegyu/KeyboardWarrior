--!strict
-- Dubeolsik composition. The OS syllable is not in TextBox.Text until Space, so the
-- judged answer is the syllable these keys already display.

local HangulInput = {}

export type State = {
	committed: string,
	lead: number?,
	vowel: number?,
	tail: number?,
}

local LEAD = { "ㄱ", "ㄲ", "ㄴ", "ㄷ", "ㄸ", "ㄹ", "ㅁ", "ㅂ", "ㅃ", "ㅅ", "ㅆ", "ㅇ", "ㅈ", "ㅉ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ" }
local VOWEL = { "ㅏ", "ㅐ", "ㅑ", "ㅒ", "ㅓ", "ㅔ", "ㅕ", "ㅖ", "ㅗ", "ㅘ", "ㅙ", "ㅚ", "ㅛ", "ㅜ", "ㅝ", "ㅞ", "ㅟ", "ㅠ", "ㅡ", "ㅢ", "ㅣ" }

local LEAD_KEY: {[string]: number} = {
	r = 0, R = 1, s = 2, e = 3, E = 4, f = 5, a = 6, q = 7, Q = 8, t = 9, T = 10,
	d = 11, w = 12, W = 13, c = 14, z = 15, x = 16, v = 17, g = 18,
}
local VOWEL_KEY: {[string]: number} = {
	k = 0, o = 1, i = 2, O = 3, j = 4, p = 5, u = 6, P = 7, h = 8, y = 12, n = 13, b = 17, m = 18, l = 20,
}
local VOWEL_COMBO: {[number]: {[string]: number}} = {
	[8] = { k = 9, o = 10, l = 11 },
	[13] = { j = 14, p = 15, l = 16 },
	[18] = { l = 19 },
}
local TAIL_KEY: {[string]: number} = {
	r = 1, R = 2, s = 4, e = 7, f = 8, a = 16, q = 17, t = 19, T = 20, d = 21, w = 22, c = 23, z = 24, x = 25, v = 26, g = 27,
}
local TAIL_COMBO: {[number]: {[string]: number}} = {
	[1] = { t = 3 },
	[4] = { w = 5, g = 6 },
	[8] = { r = 9, a = 10, q = 11, t = 12, x = 13, v = 14, g = 15 },
	[17] = { t = 18 },
}
local TAIL_SPLIT: {[number]: {tail: number, lead: number}} = {
	[3] = { tail = 1, lead = 9 },
	[5] = { tail = 4, lead = 12 },
	[6] = { tail = 4, lead = 18 },
	[9] = { tail = 8, lead = 0 },
	[10] = { tail = 8, lead = 6 },
	[11] = { tail = 8, lead = 7 },
	[12] = { tail = 8, lead = 9 },
	[13] = { tail = 8, lead = 16 },
	[14] = { tail = 8, lead = 17 },
	[15] = { tail = 8, lead = 18 },
	[18] = { tail = 17, lead = 9 },
}
local TAIL_LEAD: {[number]: number} = {
	[1] = 0, [2] = 1, [4] = 2, [7] = 3, [8] = 5, [16] = 6, [17] = 7, [19] = 9,
	[20] = 10, [21] = 11, [22] = 12, [23] = 14, [24] = 15, [25] = 16, [26] = 17, [27] = 18,
}
local LEAD_COMBO: {[number]: {[string]: number}} = {
	[0] = { r = 1 },
	[3] = { e = 4 },
	[7] = { q = 8 },
	[9] = { t = 10 },
	[12] = { w = 13 },
}
local LEAD_UNDO: {[number]: number} = { [1] = 0, [4] = 3, [8] = 7, [10] = 9, [13] = 12 }
local VOWEL_UNDO: {[number]: number} = { [9] = 8, [10] = 8, [11] = 8, [14] = 13, [15] = 13, [16] = 13, [19] = 18 }
local TAIL_UNDO: {[number]: number} = {
	[3] = 1, [5] = 4, [6] = 4, [9] = 8, [10] = 8, [11] = 8, [12] = 8, [13] = 8, [14] = 8, [15] = 8, [18] = 17,
}

local function rendered(state: State): string
	if state.lead == nil then
		return ""
	end
	if state.vowel == nil then
		return LEAD[(state.lead :: number) + 1]
	end
	local tail = state.tail or 0
	return utf8.char(0xAC00 + ((state.lead :: number) * 21 + (state.vowel :: number)) * 28 + tail)
end

local function commit(state: State)
	local text = rendered(state)
	if text ~= "" then
		state.committed ..= text
	end
	state.lead = nil
	state.vowel = nil
	state.tail = nil
end

local function takeTail(state: State): number?
	local tail = state.tail
	if tail == nil then
		return nil
	end
	local split = TAIL_SPLIT[tail]
	if split ~= nil then
		state.tail = split.tail
		return split.lead
	end
	state.tail = nil
	return TAIL_LEAD[tail]
end

function HangulInput.begin(): State
	return {
		committed = "",
		lead = nil,
		vowel = nil,
		tail = nil,
	}
end

function HangulInput.clear(state: State)
	state.committed = ""
	state.lead = nil
	state.vowel = nil
	state.tail = nil
end

function HangulInput.text(state: State): string
	return state.committed .. rendered(state)
end

function HangulInput.key(state: State, key: string): boolean
	local vowel = VOWEL_KEY[key]
	if vowel ~= nil then
		if state.lead == nil then
			state.committed ..= VOWEL[vowel + 1]
			return true
		end
		if state.vowel == nil then
			state.vowel = vowel
			return true
		end
		if state.tail == nil then
			local combo = VOWEL_COMBO[state.vowel :: number]
			local nextVowel = if combo ~= nil then combo[key] else nil
			if nextVowel ~= nil then
				state.vowel = nextVowel
				return true
			end
			commit(state)
			state.committed ..= VOWEL[vowel + 1]
			return true
		end
		local nextLead = takeTail(state)
		commit(state)
		state.lead = nextLead
		state.vowel = vowel
		return true
	end
	local lead = LEAD_KEY[key]
	if lead == nil then
		return false
	end
	if state.lead == nil then
		state.lead = lead
		return true
	end
	if state.vowel == nil then
		local combo = LEAD_COMBO[state.lead :: number]
		local doubled = if combo ~= nil then combo[key] else nil
		if doubled ~= nil then
			state.lead = doubled
			return true
		end
		commit(state)
		state.lead = lead
		return true
	end
	if state.tail == nil then
		local tail = TAIL_KEY[key]
		if tail ~= nil then
			state.tail = tail
			return true
		end
		commit(state)
		state.lead = lead
		return true
	end
	local combo = TAIL_COMBO[state.tail :: number]
	local joined = if combo ~= nil then combo[key] else nil
	if joined ~= nil then
		state.tail = joined
		return true
	end
	commit(state)
	state.lead = lead
	return true
end

function HangulInput.space(state: State)
	commit(state)
	state.committed ..= " "
end

function HangulInput.backspace(state: State)
	if state.tail ~= nil then
		state.tail = TAIL_UNDO[state.tail :: number]
		return
	end
	if state.vowel ~= nil then
		state.vowel = VOWEL_UNDO[state.vowel :: number]
		return
	end
	if state.lead ~= nil then
		state.lead = LEAD_UNDO[state.lead :: number]
		return
	end
	local count = utf8.len(state.committed)
	if count == nil or count < 1 then
		state.committed = ""
		return
	end
	local start = utf8.offset(state.committed, count)
	if start == nil then
		state.committed = ""
		return
	end
	local last = string.sub(state.committed, start)
	state.committed = string.sub(state.committed, 1, start - 1)
	local code = utf8.codepoint(last)
	if code >= 0xAC00 and code <= 0xD7A3 then
		local index = code - 0xAC00
		state.lead = math.floor(index / 588)
		state.vowel = math.floor((index % 588) / 28)
		local tail = index % 28
		state.tail = if tail == 0 then nil else tail
		HangulInput.backspace(state)
	end
end

local function typeKeys(keys: string): string
	local state = HangulInput.begin()
	for index = 1, #keys do
		local key = string.sub(keys, index, index)
		if key == " " then
			HangulInput.space(state)
		else
			HangulInput.key(state, key)
		end
	end
	return HangulInput.text(state)
end

function HangulInput.selfCheck()
	assert(typeKeys("tk") == "사", "the first syllable is complete before the next consonant")
	assert(typeKeys("tkrh") == "사고", "a vowel that has not combined yet is not the answer")
	assert(typeKeys("tkrhk") == "사과", "the last vowel completes the word before Space")
	local spaced = HangulInput.begin()
	for _, key in { "t", "k", "r", "h", "k" } do
		HangulInput.key(spaced, key)
	end
	assert(HangulInput.text(spaced) == "사과", "Space is not required")
	HangulInput.space(spaced)
	assert(HangulInput.text(spaced) == "사과 ", "Space only adds a space after the word is already complete")
	assert(typeKeys("qu") == "벼" and typeKeys("quf") == "별", "the final consonant completes the syllable")
	assert(typeKeys("ekf") == "달" and typeKeys("ekfr") == "닭", "닭 stays 달 until the final batchim")
	local undone = HangulInput.begin()
	for _, key in { "t", "k", "r", "h", "k" } do
		HangulInput.key(undone, key)
	end
	HangulInput.backspace(undone)
	assert(HangulInput.text(undone) == "사고", "Backspace removes the last vowel")
	HangulInput.key(undone, "k")
	assert(HangulInput.text(undone) == "사과", "typing the vowel again restores the word")
	assert(typeKeys("dnflsms gkaRp shfdkdy") == "우리는 함께 놀아요", "spaces stay between the composed words")
end

return HangulInput

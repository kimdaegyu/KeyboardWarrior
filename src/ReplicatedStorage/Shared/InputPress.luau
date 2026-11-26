--!strict
-- One physical press types one character, whichever route reports it first.
-- Releasing the key ends that press, so the next press counts with no time window.
-- A focused English text box owns every letter, including O and I.
-- Touch and Korean still take the key in the game.

local InputPress = {}

export type Route = "cas" | "uis"
export type Phase = "begin" | "end"
export type Decision = "apply" | "duplicate" | "textbox" | "release" | "ignored"
export type Action = "sink" | "pass"

export type Gate = {
	engaged: boolean,
	alive: boolean,
	yield: boolean,
	ime: boolean,
	touch: boolean,
	focused: boolean,
	gameProcessed: boolean,
	route: Route,
	phase: Phase,
	key: string,
}

export type State = {
	down: {[string]: boolean},
	quiet: {[string]: boolean},
}

local function cameraKey(key: string): boolean
	return key == "o" or key == "i"
end

function InputPress.beginState(): State
	return {
		down = {},
		quiet = {},
	}
end

function InputPress.clear(state: State)
	table.clear(state.down)
	table.clear(state.quiet)
end

function InputPress.holdQuiet(state: State)
	for key, open in state.down do
		if open then
			state.quiet[key] = true
		end
	end
	table.clear(state.down)
end

function InputPress.accepts(gate: Gate): boolean
	if gate.phase ~= "begin" or not gate.alive or not gate.engaged or gate.yield then
		return false
	end
	if gate.ime then
		return gate.route == "cas"
	end
	if gate.touch then
		return true
	end
	-- A focused English field already receives every letter once the camera zoom
	-- binding is released. Stealing i and o here drops them when that binding wins.
	if gate.focused then
		return false
	end
	if gate.route == "uis" and gate.gameProcessed and not cameraKey(gate.key) then
		return false
	end
	return true
end

local function textBoxOwns(gate: Gate): boolean
	return gate.phase == "begin"
		and gate.alive
		and gate.engaged
		and not gate.yield
		and not gate.ime
		and not gate.touch
		and gate.focused
end

function InputPress.claim(state: State, key: string)
	state.quiet[key] = nil
	state.down[key] = true
end

function InputPress.offer(state: State, gate: Gate): Decision
	if gate.phase == "end" then
		local owned = state.down[gate.key] == true
		state.quiet[gate.key] = nil
		state.down[gate.key] = nil
		return if owned then "release" else "ignored"
	end
	if not InputPress.accepts(gate) then
		if textBoxOwns(gate) then
			if state.down[gate.key] then
				return "duplicate"
			end
			state.down[gate.key] = true
			return "textbox"
		end
		return "ignored"
	end
	if state.down[gate.key] then
		return "duplicate"
	end
	state.down[gate.key] = true
	return "apply"
end

function InputPress.casAction(decision: Decision, gate: Gate): Action
	if decision == "apply" then
		return "sink"
	end
	if decision == "duplicate" or decision == "release" then
		if gate.yield or not gate.engaged or not gate.alive then
			return "pass"
		end
		if cameraKey(gate.key) or gate.ime or gate.touch or not gate.focused then
			return "sink"
		end
	end
	return "pass"
end

function InputPress.releasesHold(decision: Decision, key: string): boolean
	return decision == "textbox" and key ~= "space" and key ~= "return"
end

local function withPhase(gate: Gate, phase: Phase): Gate
	return {
		engaged = gate.engaged,
		alive = gate.alive,
		yield = gate.yield,
		ime = gate.ime,
		touch = gate.touch,
		focused = gate.focused,
		gameProcessed = gate.gameProcessed,
		route = gate.route,
		phase = phase,
		key = gate.key,
	}
end

-- Studio's camera shortcut can report End for I or O while that key is still held.
-- Every other letter trusts End, because IsKeyDown can still be true for that frame.
-- Ignoring that End leaves the press open, so the next l in balloon never types.
function InputPress.event(state: State, gate: Gate, physicallyDown: boolean): Decision
	if gate.phase == "end" and physicallyDown and (gate.key == "i" or gate.key == "o") then
		return "ignored"
	end
	if gate.phase == "begin" and state.quiet[gate.key] then
		return "ignored"
	end
	return InputPress.offer(state, gate)
end

function InputPress.sample(state: State, gate: Gate, physicallyDown: boolean): Decision
	local open = state.down[gate.key] == true
	if physicallyDown then
		if open or state.quiet[gate.key] then
			return "ignored"
		end
		return InputPress.offer(state, withPhase(gate, "begin"))
	end
	state.quiet[gate.key] = nil
	if open then
		return InputPress.offer(state, withPhase(gate, "end"))
	end
	return "ignored"
end

local function gate(route: Route, phase: Phase, key: string, focused: boolean, gameProcessed: boolean, touch: boolean, yield: boolean, ime: boolean): Gate
	return {
		engaged = true,
		alive = true,
		yield = yield,
		ime = ime,
		touch = touch,
		focused = focused,
		gameProcessed = gameProcessed,
		route = route,
		phase = phase,
		key = key,
	}
end

local function glyph(key: string): string
	if key == "space" then
		return " "
	end
	return key
end

local function legacyDropsSecondPress(secondsAfterMark: number): boolean
	local markedAt = 0
	return markedAt ~= nil and secondsAfterMark - markedAt < 0.02
end

local function press(state: State, routes: {Route}, key: string, focused: boolean, touch: boolean): string
	local text = ""
	for _, route in routes do
		local processed = route == "uis" and focused and cameraKey(key)
		local decision = InputPress.offer(state, gate(route, "begin", key, focused, processed, touch, false, false))
		if decision == "apply" or decision == "textbox" then
			text ..= glyph(key)
		end
	end
	for _, route in routes do
		InputPress.offer(state, gate(route, "end", key, focused, false, touch, false, false))
	end
	return text
end

-- Native Text may have advanced to the following letter before reconciliation.
function InputPress.reconcileRepeat(before: string, letter: string, text: string): string
	if string.sub(text, 1, #before) ~= before or string.sub(text, #before + 1, #before + 1) == letter then
		return text
	end
	return before .. letter .. string.sub(text, #before + 1)
end

function InputPress.selfCheck()
	local refocused = InputPress.beginState()
	local lDown = gate("uis", "begin", "l", true, true, false, false, false)
	local lUp = withPhase(lDown, "end")
	assert(InputPress.event(refocused, lDown, true) == "textbox")
	InputPress.holdQuiet(refocused)
	InputPress.event(refocused, lUp, false)
	assert(InputPress.event(refocused, lDown, true) == "textbox", "physical release rearms L after focus loss")
	assert(InputPress.reconcileRepeat("bal", "l", "bal") == "ball", "recover a missing second l")
	assert(InputPress.reconcileRepeat("bal", "l", "baloon") == "balloon", "keep the letters typed after a missed repeat")
	assert(InputPress.reconcileRepeat("bal", "l", "ballo") == "ballo", "native repeat is counted once")
	assert(InputPress.reconcileRepeat("bal", "l", "ba") == "ba", "an edited prefix is left alone")
	assert(legacyDropsSecondPress(0.01), "the removed 20ms window drops a separate press")
	local forward = InputPress.beginState()
	assert(press(forward, { "cas", "uis" }, "o", false, false) == "o", "CAS then UIS is one o")
	local reverse = InputPress.beginState()
	assert(press(reverse, { "uis", "cas" }, "o", false, false) == "o", "UIS then CAS is one o")
	local casOnly = InputPress.beginState()
	assert(press(casOnly, { "cas" }, "o", false, false) == "o", "CAS alone is one o")
	local uisOnly = InputPress.beginState()
	assert(press(uisOnly, { "uis" }, "o", false, false) == "o", "UIS alone is one o")

	local repeated = InputPress.beginState()
	local quick = press(repeated, { "cas", "uis" }, "o", false, false) .. press(repeated, { "uis", "cas" }, "o", false, false)
	assert(quick == "oo", "press, release, and a new press within 20ms is oo")
	local entered = InputPress.casAction("apply", gate("cas", "begin", "o", false, false, false, false, false))
	assert(entered == "sink", "O typed on entry does not zoom the camera")

	local playing = InputPress.beginState()
	local phrase = ""
	for _, key in { "l", "o", "o", "k", "space", "o", "u", "t" } do
		phrase ..= press(playing, { "cas", "uis" }, key, true, false)
	end
	local marks = 0
	local spaces = 0
	for index = 1, #phrase do
		local ch = string.sub(phrase, index, index)
		if ch == "o" then
			marks += 1
		elseif ch == " " then
			spaces += 1
		end
	end
	assert(phrase == "look out" and marks == 3 and spaces == 1, "look out keeps three o letters and one space")
	assert(press(playing, { "uis", "cas" }, "o", true, false) == "o", "the next question keeps its first o")

	local fieldOwned = gate("cas", "begin", "o", true, false, false, false, false)
	assert(InputPress.offer(InputPress.beginState(), fieldOwned) == "textbox", "a focused field owns O the same way it owns other letters")
	assert(InputPress.casAction("textbox", fieldOwned) == "pass", "O is not sunk before the field can read it")
	local claimed = InputPress.beginState()
	InputPress.claim(claimed, "o")
	assert(InputPress.offer(claimed, gate("cas", "begin", "o", false, false, true, false, false)) == "duplicate", "a camera key already placed in the field is not typed again")

	local ranked = InputPress.beginState()
	InputPress.offer(ranked, gate("cas", "begin", "o", true, false, false, false, false))
	InputPress.clear(ranked)
	assert(press(ranked, { "cas", "uis" }, "o", true, false) == "o", "O after the rank panel closes is kept")

	local chat = InputPress.beginState()
	local away = gate("cas", "begin", "o", false, false, false, true, false)
	assert(InputPress.offer(chat, away) == "ignored", "chat keeps the draft unchanged")
	assert(InputPress.casAction("ignored", away) == "pass", "chat is allowed to receive the key")
	InputPress.clear(chat)
	assert(press(chat, { "uis", "cas" }, "o", true, false) == "o", "the first O after chat or the menu returns")

	local blurred = InputPress.beginState()
	assert(InputPress.offer(blurred, gate("uis", "begin", "o", false, false, false, false, false)) == "apply", "O before the window blurs")
	InputPress.clear(blurred)
	assert(InputPress.offer(blurred, gate("cas", "begin", "o", false, false, false, false, false)) == "apply", "release while unfocused does not swallow the next O")

	local korean = InputPress.beginState()
	assert(InputPress.offer(korean, gate("cas", "begin", "o", false, false, false, false, true)) == "apply", "Korean O is assembled once")
	assert(InputPress.offer(korean, gate("uis", "begin", "o", false, false, false, false, true)) == "ignored", "the second route does not assemble O again")

	local mobile = "o"
	local bluetooth = InputPress.beginState()
	mobile ..= press(bluetooth, { "cas", "uis" }, "o", false, true)
	mobile ..= "o"
	assert(mobile == "ooo", "screen, bluetooth, and screen again extend one draft")

	local emulator = InputPress.beginState()
	local sampled = gate("cas", "begin", "o", false, true, true, false, false)
	assert(InputPress.sample(emulator, sampled, true) == "apply", "a touch emulator types O from the key state when Begin never arrives")
	assert(InputPress.sample(emulator, sampled, true) == "ignored", "holding that O does not repeat")
	local spurious = gate("uis", "end", "o", false, true, true, false, false)
	assert(InputPress.event(emulator, spurious, true) == "ignored", "an End while O is still down does not cancel the press")
	assert(InputPress.sample(emulator, sampled, false) == "release", "releasing O closes the press")
	assert(InputPress.sample(emulator, sampled, true) == "apply", "the next emulator O is a second character")
	local balloon = InputPress.beginState()
	local beginL = gate("cas", "begin", "l", true, false, false, false, false)
	local endL = gate("uis", "end", "l", true, false, false, false, false)
	assert(InputPress.event(balloon, beginL, true) == "textbox", "the first l reaches the field")
	assert(InputPress.event(balloon, endL, true) == "release", "l is released even when IsKeyDown still lags")
	assert(InputPress.event(balloon, beginL, true) == "textbox", "balloon keeps the second l")
	local touchL = InputPress.beginState()
	local touchBegin = gate("cas", "begin", "l", false, false, true, false, false)
	local touchEnd = gate("uis", "end", "l", false, false, true, false, false)
	assert(InputPress.event(touchL, touchBegin, true) == "apply", "a touch keyboard types the first l")
	assert(InputPress.event(touchL, touchEnd, true) == "release", "touch l is released on key up")
	assert(InputPress.event(touchL, touchBegin, true) == "apply", "touch balloon keeps the second l")
	local chatting = gate("cas", "begin", "o", false, true, true, true, false)
	assert(InputPress.sample(InputPress.beginState(), chatting, true) == "ignored", "the emulator does not type O into chat")
	assert(InputPress.releasesHold("textbox", "l") and not InputPress.releasesHold("duplicate", "o") and not InputPress.releasesHold("textbox", "space"), "only a new text-box letter opens the next question")
end

return InputPress

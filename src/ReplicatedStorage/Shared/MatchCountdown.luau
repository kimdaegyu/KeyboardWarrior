--!strict
-- Official-match ready clock. The digit follows the server start time, so a late
-- snapshot shows the current number and does not replay the numbers it missed.

local MatchCountdown = {}

-- The sheet starts opening this long before the match, and MatchStart plays at that same instant.
MatchCountdown.SplitLead = 0.1
MatchCountdown.StartLife = 0.3

function MatchCountdown.digit(remain: number): number?
	if remain > 2 then
		return 3
	end
	if remain > 1 then
		return 2
	end
	if remain > 0 then
		return 1
	end
	return nil
end

function MatchCountdown.playsReady(digit: number?): boolean
	return digit == 1 or digit == 2
end

function MatchCountdown.shouldStartCue(remain: number): boolean
	return remain <= 0
end

function MatchCountdown.shouldOpenCue(remain: number): boolean
	return remain > 0 and remain <= MatchCountdown.SplitLead
end

function MatchCountdown.shouldCue(heard: {[number]: boolean}, digit: number?): boolean
	if digit == nil or heard[digit] == true then
		return false
	end
	heard[digit] = true
	return true
end

function MatchCountdown.split(remain: number): number
	if remain <= 0 then
		return 1
	end
	if remain >= MatchCountdown.SplitLead then
		return 0
	end
	return (MatchCountdown.SplitLead - remain) / MatchCountdown.SplitLead
end

function MatchCountdown.digitPose(age: number): (number, number)
	local settle = math.max(0, 1 - age / 0.18)
	local shake = math.max(0, 1 - age / 0.45)
	return 1 + 0.15 * settle, math.sin(age * 22) * 3 * shake
end

function MatchCountdown.startPose(age: number): (number, number, number)
	if age >= MatchCountdown.StartLife then
		return 1, 0, 1
	end
	local settle = math.max(0, 1 - age / 0.12)
	local shake = math.max(0, 1 - age / 0.22)
	local transparency = if age < 0.18 then 0 else (age - 0.18) / 0.12
	return 1 + 0.4 * settle, math.sin(age * 28) * 3 * shake, transparency
end

function MatchCountdown.selfCheck()
	assert(MatchCountdown.digit(3) == 3 and MatchCountdown.digit(2.01) == 3, "the first second shows 3")
	assert(MatchCountdown.digit(2) == 2 and MatchCountdown.digit(1.6) == 2, "a snapshot 1.4 seconds late shows 2")
	assert(MatchCountdown.digit(1) == 1 and MatchCountdown.digit(0.2) == 1, "the last second shows 1")
	assert(MatchCountdown.digit(0) == nil and MatchCountdown.digit(-0.1) == nil, "the start instant clears the number")

	local heard: {[number]: boolean} = {}
	local function cue(remain: number): boolean
		local digit = MatchCountdown.digit(remain)
		if not MatchCountdown.playsReady(digit) then
			return false
		end
		return MatchCountdown.shouldCue(heard, digit)
	end
	assert(not MatchCountdown.playsReady(3) and cue(2.5) == false, "3 does not play a ready sound")
	assert(cue(1.6) == true and cue(1.4) == false, "the same number does not cue twice")
	assert(MatchCountdown.shouldStartCue(0) and MatchCountdown.shouldStartCue(-0.01), "match music is due at the start instant")
	assert(not MatchCountdown.shouldStartCue(MatchCountdown.SplitLead) and not MatchCountdown.shouldStartCue(0.01), "match music waits through the sheet opening")
	assert(MatchCountdown.shouldOpenCue(MatchCountdown.SplitLead) and MatchCountdown.shouldOpenCue(MatchCountdown.SplitLead / 2), "MatchStart is due as the sheet starts to open")
	assert(not MatchCountdown.shouldOpenCue(MatchCountdown.SplitLead + 0.01) and not MatchCountdown.shouldOpenCue(0), "MatchStart is not due before the sheet opens or at the start")
	assert(cue(0.4) == true and cue(0) == false, "only the number on screen cues")
	assert(heard[3] ~= true, "a missed 3 is not played afterwards")

	assert(MatchCountdown.split(2) == 0 and MatchCountdown.split(MatchCountdown.SplitLead) == 0, "the sheet stays closed through most of the count")
	assert(MatchCountdown.split(0) == 1, "the sheet is gone at the start instant")
	local mid = MatchCountdown.split(MatchCountdown.SplitLead / 2)
	assert(math.abs(mid - 0.5) < 1e-6, "the sheet opens across the last part of 1")

	local scale, rotation = MatchCountdown.digitPose(0)
	assert(math.abs(scale - 1.15) < 1e-6 and rotation == 0, "a number arrives large")
	local settled = MatchCountdown.digitPose(1)
	assert(math.abs(settled - 1) < 1e-6, "a number settles to its resting size")
	local startScale, _, startTransparency = MatchCountdown.startPose(0)
	assert(startScale > 1 and startTransparency == 0, "START arrives large")
	local _, _, gone = MatchCountdown.startPose(MatchCountdown.StartLife)
	assert(gone == 1, "START is gone within its short life")
end

return MatchCountdown

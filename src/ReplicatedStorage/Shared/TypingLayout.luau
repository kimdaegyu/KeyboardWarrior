--!strict
-- Height plan for the shared typing screen. No instances, so the 568×320 fit can be checked outside Studio.

export type Plan = {
	margin: number,
	gap: number,
	showKeys: boolean,
	rowHeight: number,
	keyRows: number,
	keyBlock: number,
	timeHeight: number,
	inputHeight: number,
	questionHeight: number,
	blockHeight: number,
	textSize: number,
	inputTextSize: number,
	compact: boolean,
	questionWidth: number,
	viewGap: number,
	viewLane: number,
}

local TypingLayout = {}

function TypingLayout.plan(width: number, height: number, showKeys: boolean, compactHeight: number?, compactWidth: number?, outerMargin: number?): Plan
	local heightLimit = if compactHeight ~= nil then compactHeight else 430
	local widthLimit = if compactWidth ~= nil then compactWidth else 760
	local compact = height <= heightLimit or width <= widthLimit
	local margin = outerMargin or (if compact then 6 else 16)
	local gap = 4
	local timeHeight = if compact then 22 else 32
	local inputHeight = if compact then 28 else 40
	local keyRows = 4
	local rowHeight = 0
	local keyBlock = 0
	-- The prompt keeps only the height the words, gloss, and input need. The rest is the arena.
	local questionCap = 112
	if showKeys then
		questionCap = if compact then 64 else 96
	elseif compact then
		questionCap = 72
	end
	if showKeys then
		local chrome = margin * 2 + timeHeight + inputHeight + gap * 2 + questionCap
		local available = height - chrome
		local maxRow = math.floor((available - gap * (keyRows - 1)) / keyRows)
		if maxRow < 26 then
			rowHeight = 26
		else
			rowHeight = math.min(maxRow, if compact then 36 else 48)
		end
		keyBlock = rowHeight * keyRows + gap * (keyRows - 1)
	end
	local room = height - margin * 2 - timeHeight - inputHeight - gap * 2 - keyBlock
	local questionHeight = math.min(questionCap, math.max(0, room))
	if questionHeight < 18 then
		timeHeight = 18
		inputHeight = 22
		room = height - margin * 2 - timeHeight - inputHeight - gap * 2 - keyBlock
		questionHeight = math.min(questionCap, math.max(0, room))
	end
	-- Scale only the match HUD after budgeting the keyboard rows.
	timeHeight = math.round(timeHeight * 0.8)
	inputHeight = math.round(inputHeight * 0.8)
	questionHeight = math.round(questionHeight * 0.8)
	local blockHeight = timeHeight + questionHeight + inputHeight + gap * 2
	local viewRoom = height - (margin * 2 + blockHeight + keyBlock)
	if compact and timeHeight < 36 and viewRoom >= 36 - timeHeight then
		local extra = 36 - timeHeight
		timeHeight += extra
		blockHeight += extra
	end
	local inner = math.max(0, width - margin * 2)
	local questionWidth = inner
	local viewLane = 0
	if compact and showKeys and questionWidth > 360 then
		viewLane = questionWidth - 360
		questionWidth = 360
	end
	local viewGap = math.max(0, height - (margin * 2 + blockHeight + keyBlock))
	return {
		margin = margin,
		gap = gap,
		showKeys = showKeys,
		rowHeight = rowHeight,
		keyRows = keyRows,
		keyBlock = keyBlock,
		timeHeight = timeHeight,
		inputHeight = inputHeight,
		questionHeight = questionHeight,
		blockHeight = blockHeight,
		textSize = math.clamp(math.floor(questionHeight * 0.42), 14, 36),
		inputTextSize = math.clamp(inputHeight - 8, 12, 28),
		compact = compact,
		questionWidth = questionWidth,
		viewGap = viewGap,
		viewLane = viewLane,
	}
end

export type PracticePlan = {
	margin: number,
	gap: number,
	showKeys: boolean,
	toolbarHeight: number,
	rowHeight: number,
	keyRows: number,
	keyBlock: number,
	inputHeight: number,
	questionHeight: number,
	textSize: number,
	inputTextSize: number,
	compact: boolean,
}

function TypingLayout.practicePlan(width: number, height: number, showKeys: boolean, compactHeight: number?, compactWidth: number?, outerMargin: number?): PracticePlan
	local heightLimit = if compactHeight ~= nil then compactHeight else 430
	local widthLimit = if compactWidth ~= nil then compactWidth else 760
	local compact = height <= heightLimit or width <= widthLimit
	local margin = outerMargin or (if compact then 6 else 16)
	local gap = 4
	local toolbarHeight = if compact then 36 else 44
	local inputHeight = if compact then 28 else 40
	local keyRows = 4
	local rowHeight = 0
	local keyBlock = 0
	if showKeys then
		local minQuestion = 36
		local chrome = margin * 2 + toolbarHeight + inputHeight + gap * 3 + minQuestion
		local available = height - chrome
		local maxRow = math.floor((available - gap * (keyRows - 1)) / keyRows)
		if maxRow < 26 then
			rowHeight = 26
		else
			rowHeight = math.min(maxRow, if compact then 36 else 48)
		end
		keyBlock = rowHeight * keyRows + gap * (keyRows - 1)
	end
	local questionHeight = height - margin * 2 - toolbarHeight - inputHeight - gap * 3 - (if showKeys then keyBlock else 0)
	if questionHeight < 18 then
		inputHeight = 22
		questionHeight = height - margin * 2 - toolbarHeight - inputHeight - gap * 3 - (if showKeys then keyBlock else 0)
	end
	if questionHeight < 0 then
		questionHeight = 0
	end
	return {
		margin = margin,
		gap = gap,
		showKeys = showKeys,
		toolbarHeight = toolbarHeight,
		rowHeight = rowHeight,
		keyRows = keyRows,
		keyBlock = keyBlock,
		inputHeight = inputHeight,
		questionHeight = questionHeight,
		textSize = math.clamp(math.floor(questionHeight * 0.42), 14, 36),
		inputTextSize = math.clamp(inputHeight - 8, 12, 28),
		compact = compact,
	}
end

function TypingLayout.matchDetailHeight(questionHeight: number): number
	return math.round(questionHeight * 0.38)
end

function TypingLayout.glossBand(questionHeight: number, shown: boolean): number
	if not shown or questionHeight < 48 then
		return 0
	end
	local band = math.floor(questionHeight * 0.34)
	if band > 32 then
		band = 32
	end
	if questionHeight - band < 36 then
		band = questionHeight - 36
	end
	if band < 16 then
		return 0
	end
	return band
end

function TypingLayout.usedHeight(plan: Plan): number
	return plan.margin * 2 + plan.blockHeight + plan.keyBlock
end

function TypingLayout.selfCheck()
	local phone = TypingLayout.plan(568, 320, true)
	assert(phone.showKeys and phone.keyRows == 4)
	assert(phone.rowHeight == 36, `phone row {phone.rowHeight}`)
	assert(phone.keyBlock == 156, `phone keys {phone.keyBlock}`)
	assert(phone.questionHeight == 51, `phone question {phone.questionHeight}`)
	assert(phone.inputHeight == 22 and phone.timeHeight == 36)
	assert(phone.questionWidth == 360)
	assert(phone.viewLane == 196, `phone arena lane {phone.viewLane}`)
	assert(phone.viewGap == 35, `phone arena gap {phone.viewGap}`)
	assert(TypingLayout.usedHeight(phone) + phone.viewGap == 320, "568×320 keeps the prompt, keys, and an arena gap")

	local desktop = TypingLayout.plan(1366, 768, false)
	assert(not desktop.showKeys and desktop.keyBlock == 0)
	assert(desktop.questionHeight == 90, `desktop question {desktop.questionHeight}`)
	assert(desktop.viewLane == 0 and desktop.viewGap == 580, `desktop arena gap {desktop.viewGap}`)
	assert(desktop.questionWidth == 1366 - 2 * desktop.margin)
	assert(desktop.questionHeight > phone.questionHeight, "a physical keyboard gives the prompt more room")
	assert(TypingLayout.usedHeight(desktop) + desktop.viewGap == 768)

	local practicePhone = TypingLayout.practicePlan(568, 320, true)
	assert(practicePhone.showKeys and practicePhone.keyRows == 4)
	assert(practicePhone.toolbarHeight == 36 and practicePhone.rowHeight == 36, "practice keeps a tappable exit and key row")
	assert(practicePhone.keyBlock == 156 and practicePhone.inputHeight == 28 and practicePhone.questionHeight == 76)
	local practiceUsed = practicePhone.margin * 2
		+ practicePhone.toolbarHeight
		+ practicePhone.questionHeight
		+ practicePhone.inputHeight
		+ practicePhone.keyBlock
		+ practicePhone.gap * 3
	assert(practiceUsed == 320, "568×320 shows the prompt, input, last key row, and exit")
	local practiceDesktop = TypingLayout.practicePlan(1366, 768, false)
	assert(not practiceDesktop.showKeys and practiceDesktop.questionHeight == 640)
	assert(practiceDesktop.questionHeight > practicePhone.questionHeight, "a physical keyboard gives practice more room")

	assert(TypingLayout.glossBand(phone.questionHeight, false) == 0, "a hidden gloss returns the prompt area")
	local matchBand = TypingLayout.matchDetailHeight(phone.questionHeight)
	local practiceBand = TypingLayout.glossBand(practicePhone.questionHeight, true)
	assert(matchBand == 19 and phone.questionHeight - matchBand == 32, "a match gloss stays inside the prompt")
	assert(practiceBand == 25 and practicePhone.questionHeight - practiceBand >= 36, "a practice gloss stays inside the prompt")
	local refit = TypingLayout.plan(568, 320, true)
	assert(refit.inputHeight == 22 and refit.keyBlock == 156 and refit.questionHeight == 51, "gloss does not move the input or the last key row")
end

return TypingLayout

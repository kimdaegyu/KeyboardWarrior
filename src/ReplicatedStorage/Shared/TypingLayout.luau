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
}

local TypingLayout = {}

function TypingLayout.plan(width: number, height: number, showKeys: boolean, compactHeight: number?, compactWidth: number?): Plan
	local heightLimit = if compactHeight ~= nil then compactHeight else 430
	local widthLimit = if compactWidth ~= nil then compactWidth else 760
	local compact = height <= heightLimit or width <= widthLimit
	local margin = if compact then 6 else 16
	local gap = 4
	local timeHeight = if compact then 22 else 32
	local inputHeight = if compact then 28 else 40
	local keyRows = 4
	local rowHeight = 0
	local keyBlock = 0
	if showKeys then
		local minQuestion = 36
		local chrome = margin * 2 + gap + timeHeight + inputHeight + gap * 2 + minQuestion
		local available = height - chrome
		local maxRow = math.floor((available - gap * (keyRows - 1)) / keyRows)
		if maxRow < 26 then
			rowHeight = 26
		else
			rowHeight = math.min(maxRow, if compact then 36 else 48)
		end
		keyBlock = rowHeight * keyRows + gap * (keyRows - 1)
	end
	local blockHeight = height - margin * 2 - (if showKeys then keyBlock + gap else 0)
	local questionHeight = blockHeight - timeHeight - inputHeight - gap * 2
	if questionHeight < 18 then
		timeHeight = 18
		inputHeight = 22
		questionHeight = blockHeight - timeHeight - inputHeight - gap * 2
	end
	if questionHeight < 0 then
		questionHeight = 0
	end
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
	}
end

function TypingLayout.usedHeight(plan: Plan): number
	local keys = if plan.showKeys then plan.gap + plan.keyBlock else 0
	return plan.margin * 2 + plan.blockHeight + keys
end

function TypingLayout.selfCheck()
	local phone = TypingLayout.plan(568, 320, true)
	assert(phone.showKeys and phone.keyRows == 4)
	assert(phone.rowHeight == 36, `phone row {phone.rowHeight}`)
	assert(phone.keyBlock == 156, `phone keys {phone.keyBlock}`)
	assert(phone.questionHeight == 90, `phone question {phone.questionHeight}`)
	assert(phone.inputHeight == 28 and phone.timeHeight == 22)
	assert(TypingLayout.usedHeight(phone) == 320, "568×320 fits time, question, input, and four key rows")

	local desktop = TypingLayout.plan(1366, 768, false)
	assert(not desktop.showKeys and desktop.keyBlock == 0)
	assert(desktop.questionHeight == 656)
	assert(desktop.questionHeight > phone.questionHeight, "a physical keyboard gives the prompt more room")
	assert(TypingLayout.usedHeight(desktop) == 768)
end

return TypingLayout

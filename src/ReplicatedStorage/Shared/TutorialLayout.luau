--!strict
-- One tutorial card. The first page docks low so the join circle stays visible. Buttons stay outside the body.

export type Plan = {
	margin: number,
	gap: number,
	panelWidth: number,
	panelHeight: number,
	title: number,
	body: number,
	step: number,
	row: number,
	docked: boolean,
	uncovered: number,
	compact: boolean,
}

local TutorialLayout = {}

function TutorialLayout.panelHeight(title: number, body: number, step: number, row: number, gap: number): number
	return gap * 2 + title + body + step + row + gap * 3
end

function TutorialLayout.plan(width: number, height: number, docked: boolean, compactHeight: number?, compactWidth: number?): Plan
	local heightLimit = if compactHeight ~= nil then compactHeight else 430
	local widthLimit = if compactWidth ~= nil then compactWidth else 760
	local compact = height <= heightLimit or width <= widthLimit
	local margin = if compact then 8 else 20
	local gap = 4
	local title = if compact then 22 else 28
	local body = if compact then 64 else 120
	local step = if compact then 16 else 20
	local row = if compact then 36 else 44
	local panelHeight = TutorialLayout.panelHeight(title, body, step, row, gap)
	local room = height - margin * 2 - panelHeight
	if room < 0 then
		body = math.max(48, body + room)
		panelHeight = TutorialLayout.panelHeight(title, body, step, row, gap)
	end
	local uncovered = if docked then height - margin - panelHeight else math.max(0, math.floor((height - panelHeight) / 2))
	return {
		margin = margin,
		gap = gap,
		panelWidth = math.min(math.max(0, width - margin * 2), 560),
		panelHeight = panelHeight,
		title = title,
		body = body,
		step = step,
		row = row,
		docked = docked,
		uncovered = uncovered,
		compact = compact,
	}
end

function TutorialLayout.selfCheck()
	local phone = TutorialLayout.plan(568, 320, true)
	assert(phone.compact and phone.docked and phone.row == 36, "the phone tutorial keeps a tappable row")
	assert(phone.uncovered >= 96, "the join page leaves the yellow circle visible")
	assert(phone.panelHeight + phone.margin <= 320 and phone.body >= 48, "568×320 keeps the body and the done button apart")
	local content = phone.gap * 2 + phone.title + phone.gap + phone.body + phone.gap + phone.step + phone.gap + phone.row
	assert(content == phone.panelHeight, "the button row sits below the body")
	local centered = TutorialLayout.plan(568, 320, false)
	assert(not centered.docked and centered.panelHeight + centered.margin * 2 <= 320, "later pages keep done on screen")
	local desktop = TutorialLayout.plan(1366, 768, false)
	assert(not desktop.compact and desktop.row > phone.row and desktop.panelHeight < 768, "a wide tutorial card has taller rows")
end

return TutorialLayout

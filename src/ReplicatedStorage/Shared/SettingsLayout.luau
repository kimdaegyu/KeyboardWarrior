--!strict
-- One settings panel for every device. Rows shrink only when the safe area is shorter than the full form.

export type Plan = {
	margin: number,
	gap: number,
	panelWidth: number,
	title: number,
	label: number,
	row: number,
	status: number,
	compact: boolean,
}

export type ListPlan = {
	margin: number,
	gap: number,
	panelWidth: number,
	row: number,
	back: number,
	listHeight: number,
	canvas: number,
	scrolls: boolean,
}

local SettingsLayout = {}

function SettingsLayout.usedHeight(plan: Plan): number
	local body = plan.title + plan.label * 3 + plan.row * 5 + plan.status
	return plan.margin * 2 + body + plan.gap * 9
end

function SettingsLayout.plan(width: number, height: number, compactHeight: number?, compactWidth: number?): Plan
	local heightLimit = if compactHeight ~= nil then compactHeight else 430
	local widthLimit = if compactWidth ~= nil then compactWidth else 760
	local compact = height <= heightLimit or width <= widthLimit
	local margin = if compact then 8 else 20
	local gap = 4
	local title = if compact then 20 else 32
	local label = if compact then 14 else 22
	local row = if compact then 36 else 44
	local status = if compact then 14 else 22
	local plan: Plan = {
		margin = margin,
		gap = gap,
		panelWidth = math.min(math.max(0, width - margin * 2), 520),
		title = title,
		label = label,
		row = row,
		status = status,
		compact = compact,
	}
	local overflow = SettingsLayout.usedHeight(plan) - height
	if overflow > 0 then
		plan.row = math.max(28, row - overflow)
		plan.title = math.max(20, title - math.floor(overflow / 4))
		plan.label = math.max(14, label - math.floor(overflow / 8))
		plan.status = plan.label
	end
	return plan
end

function SettingsLayout.listPlan(width: number, height: number, count: number, compactHeight: number?, compactWidth: number?): ListPlan
	local heightLimit = if compactHeight ~= nil then compactHeight else 430
	local widthLimit = if compactWidth ~= nil then compactWidth else 760
	local compact = height <= heightLimit or width <= widthLimit
	local margin = if compact then 8 else 20
	local gap = 4
	local row = if compact then 36 else 44
	local listHeight = height - margin * 2 - row - gap
	local rows = math.max(0, count)
	return {
		margin = margin,
		gap = gap,
		panelWidth = math.min(math.max(0, width - margin * 2), 520),
		row = row,
		back = row,
		listHeight = math.max(0, listHeight),
		canvas = rows * row + math.max(0, rows - 1) * gap,
		scrolls = rows * row + math.max(0, rows - 1) * gap > listHeight,
	}
end

function SettingsLayout.selfCheck()
	local phone = SettingsLayout.plan(568, 320)
	assert(phone.compact and phone.row == 36 and phone.title == 20, "phone settings keep a tappable row")
	local used = SettingsLayout.usedHeight(phone)
	assert(used <= 320, "568×320 shows apply and close")
	assert(phone.margin + phone.title + phone.gap + phone.label + phone.gap + phone.row > phone.margin, "the language choices sit under the title")
	local desktop = SettingsLayout.plan(1366, 768)
	assert(not desktop.compact and desktop.row > phone.row and SettingsLayout.usedHeight(desktop) < 768, "a wide settings panel has taller rows")
	local dozen = SettingsLayout.listPlan(568, 320, 12)
	assert(dozen.scrolls, "twelve languages scroll inside the list")
	assert(dozen.margin * 2 + dozen.listHeight + dozen.gap + dozen.back <= 320, "back stays on a 568×320 list")
	local lastTop = 11 * (dozen.row + dozen.gap)
	assert(lastTop + dozen.row <= dozen.canvas and lastTop >= dozen.listHeight, "the last language is reached by scrolling")
	local shortList = SettingsLayout.listPlan(568, 320, 2)
	assert(not shortList.scrolls and shortList.back == 36, "a short list keeps the back button without scrolling")
end

return SettingsLayout

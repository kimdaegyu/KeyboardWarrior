--!strict
-- One settings panel for every device. Rows shrink only when the safe area is shorter than the full form.

export type Plan = {
	margin: number,
	gap: number,
	panelWidth: number,
	title: number,
	stride: number,
	row: number,
	header: number,
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

function SettingsLayout.usedHeight(plan: Plan, rows: number?): number
	local count = if rows ~= nil then rows else 6
	return plan.margin * 2 + plan.title + plan.stride * count + plan.gap + plan.status
end

function SettingsLayout.plan(width: number, height: number, compactHeight: number?, compactWidth: number?): Plan
	local compact = height <= (compactHeight or 430) or width <= (compactWidth or 760)
	local scale = math.min(width / 1672, height / 941, 1)
	local row = math.max(if compact then 36 else 44, math.round(54 * scale))
	return {
		compact = compact,
		panelWidth = math.min(width - 16, math.max(if compact then width * 0.82 else 560, math.round(1030 * scale))),
		header = math.max(28, math.round(66 * scale)),
		margin = math.max(9, math.round(38 * scale)),
		gap = math.max(4, math.round(16 * scale)),
		title = math.max(row, math.round(56 * scale)),
		stride = math.max(row + 4, math.round(98 * scale)),
		row = row,
		status = 18,
	}
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
	assert(phone.compact and phone.row == 36 and phone.title == phone.row, "phone settings keep a tappable row")
	local rows = 6
	local used = SettingsLayout.usedHeight(phone, rows)
	local card = math.min(used, 320 - 12)
	local header = phone.margin + phone.title
	local view = card - header
	local canvas = used - header
	local statusTop = rows * phone.stride + phone.gap
	assert(view < canvas and statusTop + phone.status <= canvas, "568×320 scrolls to the status line while the header stays put")
	assert(phone.stride >= phone.row, "the language choices sit under the title")
	local desktop = SettingsLayout.plan(1366, 768)
	assert(not desktop.compact and desktop.row > phone.row and SettingsLayout.usedHeight(desktop, rows) < 768, "a wide settings panel has taller rows")
	local dozen = SettingsLayout.listPlan(568, 320, 12)
	assert(dozen.scrolls, "twelve languages scroll inside the list")
	assert(dozen.margin * 2 + dozen.listHeight + dozen.gap + dozen.back <= 320, "back stays on a 568×320 list")
	local lastTop = 11 * (dozen.row + dozen.gap)
	assert(lastTop + dozen.row <= dozen.canvas and lastTop >= dozen.listHeight, "the last language is reached by scrolling")
	local shortList = SettingsLayout.listPlan(568, 320, 2)
	assert(not shortList.scrolls and shortList.back == 36, "a short list keeps the back button without scrolling")
end

return SettingsLayout

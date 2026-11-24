--!strict
-- One rank card. The title, personal best, and close button stay on screen. Only the list scrolls.

export type Plan = {
	margin: number,
	gap: number,
	panelWidth: number,
	title: number,
	mine: number,
	header: number,
	row: number,
	close: number,
	listHeight: number,
	compact: boolean,
}

local RankLayout = {}

function RankLayout.plan(width: number, height: number, compactHeight: number?, compactWidth: number?): Plan
	local heightLimit = if compactHeight ~= nil then compactHeight else 430
	local widthLimit = if compactWidth ~= nil then compactWidth else 760
	local compact = height <= heightLimit or width <= widthLimit
	local margin = if compact then 8 else 20
	local gap = 4
	local title = if compact then 22 else 28
	local mine = if compact then 32 else 40
	local header = if compact then 18 else 22
	local row = if compact then 28 else 36
	local close = if compact then 36 else 44
	local chrome = margin * 2 + title + mine + header + close + gap * 4
	local listHeight = height - chrome
	if listHeight < row then
		local overflow = row - listHeight
		title = math.max(18, title - math.floor(overflow / 4))
		mine = math.max(24, mine - math.floor(overflow / 2))
		header = math.max(14, header - math.floor(overflow / 4))
		chrome = margin * 2 + title + mine + header + close + gap * 4
		listHeight = math.max(row, height - chrome)
	end
	return {
		margin = margin,
		gap = gap,
		panelWidth = math.min(math.max(0, width - margin * 2), 720),
		title = title,
		mine = mine,
		header = header,
		row = row,
		close = close,
		listHeight = listHeight,
		compact = compact,
	}
end

function RankLayout.selfCheck()
	local phone = RankLayout.plan(568, 320)
	local chrome = phone.margin * 2 + phone.title + phone.mine + phone.header + phone.close + phone.gap * 4
	assert(phone.compact and phone.close == 36 and phone.row >= 28, "the phone rank card keeps a tappable close button")
	assert(chrome + phone.listHeight <= 320 and phone.listHeight >= phone.row, "568×320 keeps the title and close button outside the scroller")
	local desktop = RankLayout.plan(1366, 768)
	assert(not desktop.compact and desktop.listHeight > phone.listHeight and desktop.close > phone.close, "a wide rank card gives the list more room")
end

return RankLayout

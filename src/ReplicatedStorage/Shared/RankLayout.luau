--!strict
local RankLayout = {}

function RankLayout.plan(width: number, height: number)
	local scale = math.min(width / 1672, height / 941, 1)
	local compact = height <= 430 or width <= 760
	local gap = math.max(8, math.round(26 * scale))
	local group = math.min(width - 16, if compact then width * 0.95 else math.max(685, math.round(1200 * scale)))
	local personal = math.floor((group - gap) * 0.298)
	local pad = math.max(8, math.round(32 * scale))
	local topLimit = 6
	local row = math.max(24, math.round(45 * scale))
	local title = math.max(25, math.round(74 * scale))
	local columns = math.max(20, math.round(42 * scale))
	local close = math.max(if compact then 36 else 44, math.round(54 * scale))
	title = math.max(title, close)
	local boardHeight = math.min(height - topLimit - 6, pad * 2 + title + columns + row * 6)
	local listHeight = math.max(0, boardHeight - 2 * pad - title - columns)
	return {
		left = math.floor((width - group) / 2), top = math.max(topLimit, math.floor((height - boardHeight) / 2)),
		personal = personal, board = group - personal - gap, gap = gap, pad = pad,
		height = boardHeight, personalHeight = math.min(boardHeight, math.max(132, math.round(286 * scale))),
		title = title, columns = columns, row = row, listHeight = listHeight, close = close,
	}
end

function RankLayout.selfCheck()
	for _, size in { {568, 240}, {844, 320}, {1672, 941} } do
		local width, height = size[1], size[2]
		local p = RankLayout.plan(width, height)
		assert(p.listHeight >= p.row and p.top + p.height <= height)
		assert(p.left + p.personal + p.gap + p.board <= width)
	end
end

return RankLayout

--!strict
-- Shared result screen heights. The summary stays readable and the rank list scrolls inside the remainder.

export type Plan = {
	compact: boolean,
	margin: number,
	gap: number,
	summaryHeight: number,
	listHeight: number,
}

local ResultLayout = {}

ResultLayout.rowStride = 28

function ResultLayout.plan(width: number, height: number, compactHeight: number?, compactWidth: number?): Plan
	local heightLimit = if compactHeight ~= nil then compactHeight else 430
	local widthLimit = if compactWidth ~= nil then compactWidth else 760
	local compact = height <= heightLimit or width <= widthLimit
	local margin = if compact then 6 else 16
	local gap = 4
	local summary = if compact then 148 else 168
	local list = height - margin * 2 - summary - gap
	if list < 72 then
		summary = math.max(96, height - margin * 2 - gap - 72)
		list = height - margin * 2 - summary - gap
	end
	if list < 0 then
		list = 0
	end
	return {
		compact = compact,
		margin = margin,
		gap = gap,
		summaryHeight = summary,
		listHeight = list,
	}
end

function ResultLayout.selfCheck()
	local phone = ResultLayout.plan(568, 320)
	assert(phone.compact and phone.summaryHeight == 148 and phone.listHeight == 156, "568×320 keeps the summary and a scrolling list")
	assert(phone.margin * 2 + phone.summaryHeight + phone.gap + phone.listHeight == 320, "the result screen fits the phone height")
	local desktop = ResultLayout.plan(1366, 768)
	assert(not desktop.compact and desktop.listHeight > phone.listHeight, "a wide screen gives the rank list more room")
	local stride = ResultLayout.rowStride
	local canvas = 12 * stride
	local lastTop = 11 * stride
	assert(phone.listHeight < canvas and lastTop >= phone.listHeight, "568×320 reaches rank 12 by scrolling the result list")
	assert(lastTop + stride <= canvas and desktop.listHeight > 0, "a wide result list also contains rank 12")
end

return ResultLayout

--!strict
-- One shop card. Tabs, gold, preview, and the action row stay put. The product list scrolls.

export type Plan = {
	margin: number,
	gap: number,
	title: number,
	gold: number,
	tab: number,
	action: number,
	body: number,
	list: number,
	preview: number,
	compact: boolean,
}

local ShopLayout = {}

function ShopLayout.plan(width: number, height: number, compactHeight: number?, compactWidth: number?): Plan
	local heightLimit = if compactHeight ~= nil then compactHeight else 430
	local widthLimit = if compactWidth ~= nil then compactWidth else 760
	local compact = height <= heightLimit or width <= widthLimit
	local margin = if compact then 8 else 16
	local gap = 4
	local title = if compact then 22 else 28
	local gold = if compact then 18 else 24
	local tab = if compact then 32 else 40
	local action = if compact then 36 else 44
	local preview = if compact then 150 else 280
	local chrome = margin * 2 + title + gold + tab + action + gap * 4
	local body = math.max(72, height - chrome)
	local inner = math.max(0, width - margin * 2)
	local list = inner - preview - gap
	if list < 160 then
		preview = math.max(120, inner - 160 - gap)
		list = math.max(0, inner - preview - gap)
	end
	return {
		margin = margin,
		gap = gap,
		title = title,
		gold = gold,
		tab = tab,
		action = action,
		body = body,
		list = list,
		preview = preview,
		compact = compact,
	}
end

function ShopLayout.selfCheck()
	local phone = ShopLayout.plan(568, 320)
	local chrome = phone.margin * 2 + phone.title + phone.gold + phone.tab + phone.action + phone.gap * 4
	assert(phone.compact and phone.action == 36 and phone.preview >= 120 and phone.list >= 160, "the phone shop keeps a tappable action row")
	assert(chrome + phone.body <= 320 and phone.body >= 72, "568×320 keeps tabs, gold, preview, and close outside the product list")
	local tablet = ShopLayout.plan(1024, 768)
	assert(not tablet.compact and tablet.preview > phone.preview and tablet.body > phone.body and tablet.action > phone.action, "a tablet shop gives the preview more room")
end

return ShopLayout

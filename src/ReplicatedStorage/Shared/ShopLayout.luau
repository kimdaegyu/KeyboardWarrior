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

-- Match the landscape storefront proportions, using the safe height on short phones.
function ShopLayout.windowSize(width: number, height: number, margin: number): (number, number)
	local aspect = 2.05
	local maxWidth = math.max(0, width - 2 * margin)
	local maxHeight = math.max(0, height - 2 * margin)
	local fraction = math.clamp(0.77 - 0.19 * (height - 648) / (1080 - 648), 0.58, 0.77)
	local h = math.min(maxHeight, math.max(204, height * fraction), maxWidth / aspect, 1280 / aspect)
	return math.round(h * aspect), math.round(h)
end

function ShopLayout.plan(width: number, height: number, compactHeight: number?, compactWidth: number?, target: number?): Plan
	local heightLimit = if compactHeight ~= nil then compactHeight else 430
	local widthLimit = if compactWidth ~= nil then compactWidth else 760
	local compact = height <= heightLimit or width <= widthLimit
	local margin = if compact then 8 else 16
	local gap = 4
	local title = if compact then 22 else 28
	local gold = if compact then 18 else 24
	local tab = math.max(target or 0, if compact then 32 else 40)
	local action = math.max(target or 0, if compact then 36 else 44)
	local preview = math.clamp(math.round(width * 0.31), 120, 360)
	local chrome = margin * 2 + title + gold + tab + action + gap * 4
	local body = math.max(0, height - chrome)
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
	for _, viewport in { {568, 240}, {667, 320}, {1024, 768}, {1404, 648}, {1920, 1080} } do
		local w, h = viewport[1], viewport[2]
		local margin = math.clamp(math.round(h * 0.02), 6, 20)
		local width, height = ShopLayout.windowSize(w, h, margin)
		local p = ShopLayout.plan(width, height, nil, nil, if h <= 430 then 36 else 44)
		assert(width + 2 * margin <= w and height + 2 * margin <= h)
		assert(p.list >= 160 and p.body >= p.action)
		assert(p.margin * 2 + p.title + p.gold + p.tab + p.body + p.action + p.gap * 4 == height)
	end
	local desktopWidth = ShopLayout.windowSize(1920, 1080, 20)
	assert(desktopWidth == 1280)
	local phone = ShopLayout.plan(568, 320)
	local chrome = phone.margin * 2 + phone.title + phone.gold + phone.tab + phone.action + phone.gap * 4
	assert(phone.compact and phone.action == 36 and phone.preview >= 120 and phone.list >= 160, "the phone shop keeps a tappable action row")
	assert(chrome + phone.body <= 320 and phone.body >= 72, "568×320 keeps tabs, gold, preview, and close outside the product list")
	local tablet = ShopLayout.plan(1024, 768)
	assert(not tablet.compact and tablet.preview > phone.preview and tablet.body > phone.body and tablet.action > phone.action, "a tablet shop gives the preview more room")
end

return ShopLayout

--!strict
-- One tutorial card. A square figure sits left of the title and the scrolling description.
-- The card stays in the middle of the screen. Buttons stay below both columns.

export type Plan = {
	margin: number,
	gap: number,
	panelWidth: number,
	panelHeight: number,
	title: number,
	body: number,
	image: number,
	textWidth: number,
	step: number,
	row: number,
	docked: boolean,
	uncovered: number,
	compact: boolean,
}

export type Presentation = {
	id: string,
	titleKey: string,
	bodyKey: string,
	image: string,
}

local TutorialLayout = {}

function TutorialLayout.presentation(id: string, titleKey: string, bodyKey: string, imageFor: (string) -> string): Presentation
	return {
		id = id,
		titleKey = titleKey,
		bodyKey = bodyKey,
		image = imageFor(id),
	}
end

function TutorialLayout.plan(width: number, height: number, docked: boolean, compactHeight: number?, compactWidth: number?): Plan
	local heightLimit = if compactHeight ~= nil then compactHeight else 430
	local widthLimit = if compactWidth ~= nil then compactWidth else 760
	local compact = height <= heightLimit or width <= widthLimit
	local margin = if compact then 8 else 20
	local gap = 4
	local title = if compact then 22 else 28
	local step = if compact then 16 else 20
	local row = if compact then 36 else 44
	local imageCap = if compact then 148 else 280
	local textMin = if compact then 132 else 280
	local panelWidth = math.min(math.max(0, width - margin * 2), if compact then 552 else 880)
	local footer = gap + step + gap + row + gap
	local heightBudget = height - margin * 2
	if docked then
		heightBudget = math.min(heightBudget, height - margin - 96)
	end
	local imageByHeight = heightBudget - gap - footer
	local imageByWidth = panelWidth - gap * 2 - gap - textMin
	local image = math.floor(math.max(48, math.min(imageCap, imageByHeight, imageByWidth)))
	local panelHeight = gap + image + footer
	if panelHeight > heightBudget then
		image = math.max(48, image - (panelHeight - heightBudget))
		panelHeight = gap + image + footer
	end
	local textWidth = math.max(0, panelWidth - gap * 2 - gap - image)
	local body = math.max(48, image - title - gap)
	local uncovered = if docked then height - margin - panelHeight else math.max(0, math.floor((height - panelHeight) / 2))
	return {
		margin = margin,
		gap = gap,
		panelWidth = panelWidth,
		panelHeight = panelHeight,
		title = title,
		body = body,
		image = image,
		textWidth = textWidth,
		step = step,
		row = row,
		docked = docked,
		uncovered = uncovered,
		compact = compact,
	}
end

function TutorialLayout.selfCheck()
	local phone = TutorialLayout.plan(568, 320, false)
	assert(phone.compact and not phone.docked and phone.row == 36, "the phone tutorial keeps a tappable row")
	assert(phone.uncovered == math.floor((320 - phone.panelHeight) / 2), "the card sits in the middle of the screen")
	assert(phone.panelHeight + phone.margin * 2 <= 320 and phone.body >= 48, "568×320 keeps the body and the done button apart")
	assert(phone.image >= 48 and phone.textWidth >= 132, "the phone keeps a square figure and a readable description")
	local columnBottom = phone.gap + phone.image
	local buttonsTop = phone.gap + phone.image + phone.gap + phone.step + phone.gap
	assert(phone.gap + phone.title + phone.gap + phone.body == columnBottom, "the description fills the figure height and can scroll to its last line")
	assert(buttonsTop >= columnBottom and buttonsTop + phone.row + phone.gap == phone.panelHeight, "the button row sits below the figure")
	local desktop = TutorialLayout.plan(1366, 768, false)
	assert(not desktop.compact and desktop.row > phone.row and desktop.panelHeight < 768, "a wide tutorial card has taller rows")
	assert(desktop.image > phone.image and desktop.margin > phone.margin, "a short screen shrinks the figure and the margin before the buttons")
	local function imageFor(id: string): string
		return "figure:" .. id
	end
	local pages = {
		{ id = "join", enabled = true, title = "Tutorial.JoinTitle", body = "Tutorial.JoinBody" },
		{ id = "typing", enabled = false, title = "Tutorial.TypingTitle", body = "Tutorial.TypingBody" },
		{ id = "practice", enabled = true, title = "Tutorial.PracticeTitle", body = "Tutorial.PracticeBody" },
		{ id = "shop", enabled = true, title = "Tutorial.ShopTitle", body = "Tutorial.ShopBody" },
	}
	local shown = {}
	for _, page in pages do
		if page.enabled then
			table.insert(shown, page)
		end
	end
	local frame = TutorialLayout.presentation(shown[2].id, shown[2].title, shown[2].body, imageFor)
	assert(frame.id == "practice" and frame.bodyKey == "Tutorial.PracticeBody" and frame.titleKey == "Tutorial.PracticeTitle" and frame.image == "figure:practice", "skipping a disabled step keeps the image on the same id")
end

return TutorialLayout

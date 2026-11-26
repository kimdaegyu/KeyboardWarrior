--!strict
-- Global rank popup. The title, personal best, and close button stay put. Only the list scrolls.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Localization = require(ReplicatedStorage.Shared.Localization)
local PracticeRules = require(ReplicatedStorage.Shared.PracticeRules)
local RankLayout = require(ReplicatedStorage.Shared.RankLayout)
local UiChrome = require(ReplicatedStorage.Shared.UiChrome)
local constants = require(ReplicatedStorage.Shared.IngameConstants)
local RankState = require(script.Parent.RankState)

local RankScreen = {}

function RankScreen.bind(root: Frame): () -> ()
	local screen = Instance.new("Frame")
	screen.Name = "RankScreen"
	screen.Size = UDim2.fromScale(1, 1)
	screen.BackgroundColor3 = UiChrome.Navy
	screen.BackgroundTransparency = 1
	screen.BorderSizePixel = 0
	screen.Visible = false
	screen.Active = true
	screen.ZIndex = 3
	screen.Parent = root

	local function surface(name: string): Frame
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.ZIndex = 4
		frame.Parent = screen
		UiChrome.paint(frame, "panel")
		local outline = frame:FindFirstChildOfClass("UIStroke")
		if outline then outline.Color = UiChrome.Navy end
		return frame
	end
	local personal = surface("PersonalRecord")
	local card = surface("Leaderboard")

	local function label(name: string, xAlign: Enum.TextXAlignment, parent: GuiObject?): TextLabel
		local item = Instance.new("TextLabel")
		item.Name = name
		item.BackgroundTransparency = 1
		item.Font = Enum.Font.GothamMedium
		item.TextColor3 = UiChrome.Navy
		item.TextXAlignment = xAlign
		item.TextYAlignment = Enum.TextYAlignment.Center
		item.TextTruncate = Enum.TextTruncate.AtEnd
		item.ZIndex = 5
		item.Parent = parent or card
		return item
	end

	local left = Enum.TextXAlignment.Left
	local titleLabel = label("Title", left)
	titleLabel.Font = Enum.Font.GothamBold
	local trophy = UiChrome.icon(card, 10073)
	local portrait = UiChrome.icon(personal, 10071)
	local recordTitle = label("RecordTitle", left, personal)
	local personalLanguage = label("Language", Enum.TextXAlignment.Right, personal)
	local position = label("MyPosition", left, personal)
	position.Font = Enum.Font.GothamBold
	position.TextScaled = true
	local positionFont = Instance.new("UITextSizeConstraint")
	positionFont.MinTextSize = 11
	positionFont.Parent = position
	local bestTitle = label("BestTitle", left, personal)
	local mineLabel = label("BestValue", left, personal)
	mineLabel.Font = Enum.Font.GothamBold
	mineLabel.TextScaled = true
	local bestFont = Instance.new("UITextSizeConstraint")
	bestFont.MinTextSize = 10
	bestFont.Parent = mineLabel
	local personalCpmTitle = label("CpmTitle", left, personal)
	local personalCpm = mineLabel:Clone()
	personalCpm.Name = "CpmValue"
	personalCpm.Parent = personal
	local cpmFont = personalCpm:FindFirstChildOfClass("UITextSizeConstraint") :: UITextSizeConstraint
	local placeLabel = label("Place", left)
	local playerLabel = label("Player", left)
	local scoreLabel = label("Score", left)
	local languageLabel = label("Language", left)
	local cpmLabel = label("Cpm", left)
	for _, heading in { placeLabel, playerLabel, scoreLabel, cpmLabel, languageLabel } do
		heading.TextColor3 = UiChrome.Blue
	end
	local function divider(parent: GuiObject)
		local line = Instance.new("Frame")
		line.BorderSizePixel = 0
		line.BackgroundColor3 = Color3.fromRGB(215, 228, 250)
		line.Size = UDim2.new(1, 0, 0, 1)
		line.Position = UDim2.new(0, 0, 1, -1)
		line.Parent = parent
		return line
	end
	local headingRule = divider(card)

	local list = Instance.new("ScrollingFrame")
	list.Name = "Rows"
	list.ClipsDescendants = true
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ZIndex = 5
	list.Parent = card
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 0)
	layout.Parent = list

	local notice = Instance.new("TextLabel")
	notice.Name = "Notice"
	notice.BackgroundTransparency = 1
	notice.Font = Enum.Font.GothamMedium
	notice.TextColor3 = UiChrome.Navy
	notice.TextWrapped = true
	notice.TextXAlignment = Enum.TextXAlignment.Left
	notice.TextYAlignment = Enum.TextYAlignment.Top
	notice.LayoutOrder = 0
	notice.ZIndex = 6
	notice.Parent = list

	local closeButton = UiChrome.closeButton(card)

	local rowFrames: {Frame} = {}

	local function ensureRow(index: number): Frame
		local existing = rowFrames[index]
		if existing ~= nil then
			return existing
		end
		local row = Instance.new("Frame")
		row.Name = "Row"
		row.BackgroundColor3 = UiChrome.White
		row.BackgroundTransparency = 1
		row.BorderSizePixel = 0
		row.LayoutOrder = index
		row.ZIndex = 6
		row.Parent = list
		UiChrome.round(row, 6)
		local line = divider(row)
		line.Position = UDim2.new(0, 6, 1, -1)
		line.Size = UDim2.new(1, -12, 0, 1)
		local function cell(cellName: string, align: Enum.TextXAlignment): TextLabel
			local item = Instance.new("TextLabel")
			item.Name = cellName
			item.BackgroundTransparency = 1
			item.Font = Enum.Font.GothamMedium
			item.TextColor3 = UiChrome.Navy
			item.TextXAlignment = align
			item.TextYAlignment = Enum.TextYAlignment.Center
			item.TextTruncate = Enum.TextTruncate.AtEnd
			item.ZIndex = 7
			item.Parent = row
			return item
		end
		cell("Place", left)
		cell("Name", Enum.TextXAlignment.Left)
		cell("Score", left)
		cell("Cpm", left)
		cell("Language", left)
		rowFrames[index] = row
		return row
	end

	local function applyLayout()
		local size = root.AbsoluteSize
		if size.X < 100 or size.Y < 140 then return end
		local p = RankLayout.plan(size.X, size.Y)
		local function box(gui: GuiObject, x: number, y: number, w: number, h: number)
			gui.Position = UDim2.fromOffset(x, y)
			gui.Size = UDim2.fromOffset(w, h)
		end
		box(personal, p.left, p.top, p.personal, p.personalHeight)
		box(card, p.left + p.personal + p.gap, p.top, p.board, p.height)
		local inner = p.board - 2 * p.pad
		local side = p.personal - 2 * p.pad
		local icon = math.max(19, math.round(p.row * 0.8))
		local block = p.personalHeight - 2 * p.pad
		box(portrait, p.pad, p.pad, icon, icon)
		box(recordTitle, p.pad + icon + 5, p.pad, side - icon - 5, icon)
		recordTitle.TextSize = math.max(13, math.round(p.row * 0.55))
		box(position, p.pad, p.pad + icon, side * 0.65, block * 0.42)
		box(personalLanguage, p.pad + side * 0.66, p.pad + icon, side * 0.34, block * 0.42)
		personalLanguage.TextSize = recordTitle.TextSize
		positionFont.MaxTextSize = math.max(24, math.round(block * 0.26))
		box(bestTitle, p.pad, p.pad + block * 0.62, side * 0.54, block * 0.15)
		bestTitle.TextSize = math.max(12, math.round(p.row * 0.44))
		box(mineLabel, p.pad, p.pad + block * 0.77, side * 0.54, block * 0.23)
		bestFont.MaxTextSize = math.max(17, math.round(block * 0.17))
		box(personalCpmTitle, p.pad + side * 0.55, p.pad + block * 0.62, side * 0.45, block * 0.15)
		personalCpmTitle.TextSize = bestTitle.TextSize
		box(personalCpm, p.pad + side * 0.55, p.pad + block * 0.77, side * 0.45, block * 0.23)
		cpmFont.MaxTextSize = bestFont.MaxTextSize
		box(trophy, p.pad, p.pad + (p.title - icon) / 2, icon, icon)
		box(titleLabel, p.pad + icon + 8, p.pad, inner - icon - 20 - p.close, p.title)
		titleLabel.TextSize = math.max(20, math.round(p.row * 0.86))
		local headerY = p.pad + p.title
		local function columns(place: TextLabel, name: TextLabel, score: TextLabel, cpm: TextLabel, language: TextLabel, x: number, y: number, h: number)
			local available = inner - 8
			local first = math.floor(available * 0.13)
			local second = math.floor(available * 0.34)
			box(place, x + 4, y, first - 4, h)
			box(name, x + first, y, second - 3, h)
			local third = math.floor(available * 0.21)
			box(score, x + first + second, y, third, h)
			local fourth = math.floor(available * 0.16)
			box(cpm, x + first + second + third, y, fourth, h)
			box(language, x + first + second + third + fourth, y, available - first - second - third - fourth, h)
			for _, cell in {place, name, score, cpm, language} do
				cell.TextSize = math.max(12, math.round(p.row * 0.39))
			end
		end
		columns(placeLabel, playerLabel, scoreLabel, cpmLabel, languageLabel, p.pad, headerY, p.columns)
		box(headingRule, p.pad, headerY + p.columns - 1, inner - 8, 1)
		box(list, p.pad, headerY + p.columns, inner, p.listHeight)
		notice.Size = UDim2.new(1, -8, 0, p.row * 2)
		notice.TextSize = placeLabel.TextSize
		for _, row in rowFrames do
			row.Size = UDim2.new(1, -8, 0, p.row)
			columns(row:FindFirstChild("Place") :: TextLabel, row:FindFirstChild("Name") :: TextLabel, row:FindFirstChild("Score") :: TextLabel, row:FindFirstChild("Cpm") :: TextLabel, row:FindFirstChild("Language") :: TextLabel, 0, 0, p.row)
		end
		box(closeButton, p.board - p.pad, p.pad, p.close, p.close)
	end

	local function formatScore(score: number): string
		local digits = tostring(score):reverse():gsub("(%d%d%d)", "%1,")
		local formatted = digits:reverse():gsub("^,", "")
		return formatted
	end

	local function render()
		titleLabel.Text = Localization.getText("Rank.Title")
		cpmLabel.Text = Localization.getText("Rank.Cpm")
		languageLabel.Text = Localization.getText("Rank.Language")
		personalLanguage.Text = RankState.bestScoreLanguage() or "—"
		personalCpmTitle.Text = cpmLabel.Text
		local cpm = RankState.bestScoreCpm()
		personalCpm.Text = if cpm ~= nil then formatScore(cpm) else "—"
		placeLabel.Text = Localization.getText("Rank.Place")
		playerLabel.Text = Localization.getText("Rank.Player")
		scoreLabel.Text = Localization.getText("Rank.Score")
		recordTitle.Text = Localization.getText("Rank.Latest")
		bestTitle.Text = Localization.getText("Rank.Score")
		local best = RankState.bestScore()
		mineLabel.Text = if best ~= nil then formatScore(best) else "—"
		position.Text = "—"
		local board = RankState.status()
		local showRows = RankState.received() and (board == "ready" or board == "stale")
		local noticeKey = if board == "stale"
			then "Rank.Stale"
			elseif board == "empty" then "Rank.Empty"
			elseif board == "failed" then "Rank.Failed"
			else "Rank.Loading"
		notice.Visible = not showRows or board == "stale"
		notice.Text = Localization.getText(noticeKey)
		local mine = Players.LocalPlayer.UserId
		local entries = if showRows then RankState.rows() else {}
		
		for index, entry in entries do
			local row = ensureRow(index)
			row.Visible = true
			local mineRow = entry.userId == mine
			row.BackgroundTransparency = if mineRow then 0 else 1
			row.BackgroundColor3 = Color3.fromRGB(229, 238, 255)
			local placeCell = row:FindFirstChild("Place") :: TextLabel
			local nameCell = row:FindFirstChild("Name") :: TextLabel
			local scoreCell = row:FindFirstChild("Score") :: TextLabel
			placeCell.Text = Localization.getText("Rank.Ordinal", nil, { rank = entry.rank })
			nameCell.Text = if mineRow then Localization.getText("Rank.SelfName", nil, { name = entry.name }) else entry.name
			local languageCell = row:FindFirstChild("Language") :: TextLabel
			languageCell.Text = entry.language or "—"
			local cpmCell = row:FindFirstChild("Cpm") :: TextLabel
			cpmCell.Text = if entry.cpm ~= nil then formatScore(entry.cpm) else "—"
			scoreCell.Text = formatScore(entry.score)
		end
		local place, outside = RankState.position()
		if place then
			position.Text = Localization.getText("Rank.Ordinal", nil, { rank = formatScore(place) })
		elseif outside then
			position.Text = Localization.getText("Rank.Outside", nil, { count = formatScore(constants.Rank.PersonalLimit) })
		elseif RankState.recorded() then
			position.Text = Localization.getText("Rank.Pending")
		end
		if RankState.received() and not RankState.recorded() then
			mineLabel.Text = Localization.getText("Rank.None")
		end
		for index = #entries + 1, #rowFrames do
			rowFrames[index].Visible = false
		end
		applyLayout()
	end

	local function sync()
		local folder = ReplicatedStorage:FindFirstChild("MatchState")
		local phaseName = if folder ~= nil then folder:GetAttribute("Phase") else nil
		local phase = if type(phaseName) == "string" then phaseName else ""
		local open = root:GetAttribute("RankOpen") == true
		if open and PracticeRules.blockedByMatch(Players.LocalPlayer:GetAttribute("InMatch") == true, phase, root:GetAttribute("ResultDismissed") == true) then
			screen.Visible = false
			root:SetAttribute("RankOpen", false)
			return
		end
		if open and not screen.Visible then
			list.CanvasPosition = Vector2.zero
			RankState.request()
		end
		screen.Visible = open
		if open then
			render()
		end
	end

	closeButton.Activated:Connect(function()
		root:SetAttribute("RankOpen", false)
	end)

	local stateFolder = ReplicatedStorage:WaitForChild("MatchState")
	local connections = {
		root:GetAttributeChangedSignal("RankOpen"):Connect(sync),
		root:GetAttributeChangedSignal("ContentWidth"):Connect(applyLayout),
		root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			if screen.Visible then
				applyLayout()
			end
		end),
		Players.LocalPlayer:GetAttributeChangedSignal("InMatch"):Connect(sync),
		stateFolder:GetAttributeChangedSignal("Phase"):Connect(sync),
	}
	local stopRank = RankState.onChanged(function()
		if screen.Visible then
			render()
		end
	end)
	local stopLocale = Localization.onChanged(function()
		if screen.Visible then
			render()
		end
	end)
	local refresh = task.spawn(function()
		local lastRefresh = -math.huge
		while true do
			task.wait(5)
			local interval = if RankState.status() == "ready" or RankState.status() == "empty" then constants.Rank.CacheSeconds else 5
			if screen.Visible and os.clock() - lastRefresh >= interval then
				lastRefresh = os.clock()
				RankState.request()
			elseif not screen.Visible then
				lastRefresh = os.clock()
			end
		end
	end)
	RankState.start()
	sync()
	return function()
		for _, connection in connections do
			connection:Disconnect()
		end
		task.cancel(refresh)
		stopRank()
		stopLocale()
		screen:Destroy()
	end
end

return RankScreen

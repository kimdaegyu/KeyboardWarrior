--!strict
-- Global rank popup. The title, personal best, and close button stay put. Only the list scrolls.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local constants = require(ReplicatedStorage.Shared.IngameConstants)
local Localization = require(ReplicatedStorage.Shared.Localization)
local PracticeRules = require(ReplicatedStorage.Shared.PracticeRules)
local RankLayout = require(ReplicatedStorage.Shared.RankLayout)
local UiChrome = require(ReplicatedStorage.Shared.UiChrome)
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

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.BackgroundColor3 = UiChrome.White
	card.BorderSizePixel = 0
	card.ZIndex = 4
	card.Parent = screen
	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 10)
	cardCorner.Parent = card

	local function label(name: string, xAlign: Enum.TextXAlignment): TextLabel
		local item = Instance.new("TextLabel")
		item.Name = name
		item.BackgroundTransparency = 1
		item.Font = Enum.Font.GothamMedium
		item.TextColor3 = UiChrome.Navy
		item.TextXAlignment = xAlign
		item.TextYAlignment = Enum.TextYAlignment.Center
		item.TextTruncate = Enum.TextTruncate.AtEnd
		item.ZIndex = 5
		item.Parent = card
		return item
	end

	local titleLabel = label("Title", Enum.TextXAlignment.Center)
	local mineLabel = label("Mine", Enum.TextXAlignment.Center)
	mineLabel.Font = Enum.Font.GothamBold
	local placeLabel = label("Place", Enum.TextXAlignment.Left)
	local playerLabel = label("Player", Enum.TextXAlignment.Left)
	local scoreLabel = label("Score", Enum.TextXAlignment.Right)

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
	layout.Padding = UDim.new(0, 4)
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

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "Close"
	closeButton.Font = Enum.Font.GothamMedium
	closeButton.TextColor3 = UiChrome.Navy
	closeButton.BackgroundColor3 = UiChrome.White
	closeButton.BorderSizePixel = 0
	closeButton.AutoButtonColor = false
	closeButton.TextTruncate = Enum.TextTruncate.AtEnd
	closeButton.ZIndex = 5
	closeButton.Parent = card
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 6)
	closeCorner.Parent = closeButton

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
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = row
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
		cell("Place", Enum.TextXAlignment.Center)
		cell("Name", Enum.TextXAlignment.Left)
		cell("Score", Enum.TextXAlignment.Right)
		rowFrames[index] = row
		return row
	end

	local function applyLayout()
		local size = root.AbsoluteSize
		local height = math.max(0, size.Y - 16)
		if height > constants.UI.CompactHeight and size.X > constants.UI.CompactWidth then
			height = math.min(height, 640)
		end
		local plan = RankLayout.plan(size.X, height, constants.UI.CompactHeight, constants.UI.CompactWidth)
		plan.panelWidth = math.min(plan.panelWidth, 560)
		card.Size = UDim2.fromOffset(plan.panelWidth, height)
		UiChrome.paint(card, "panel")
		local inner = plan.panelWidth - plan.margin * 2
		local y = plan.margin
		titleLabel.Position = UDim2.fromOffset(plan.margin, y)
		titleLabel.Size = UDim2.fromOffset(inner, plan.title)
		titleLabel.TextSize = math.clamp(plan.title - 2, 14, 28)
		y += plan.title + plan.gap
		mineLabel.Position = UDim2.fromOffset(plan.margin, y)
		mineLabel.Size = UDim2.fromOffset(inner, plan.mine)
		mineLabel.TextSize = math.clamp(plan.mine - 12, 13, 20)
		y += plan.mine + plan.gap
		local placeWidth = if plan.compact then 48 else 64
		local scoreWidth = if plan.compact then 84 else 108
		placeLabel.Position = UDim2.fromOffset(plan.margin, y)
		placeLabel.Size = UDim2.fromOffset(placeWidth, plan.header)
		playerLabel.Position = UDim2.fromOffset(plan.margin + placeWidth, y)
		playerLabel.Size = UDim2.fromOffset(math.max(0, inner - placeWidth - scoreWidth), plan.header)
		scoreLabel.Position = UDim2.fromOffset(plan.margin + inner - scoreWidth, y)
		scoreLabel.Size = UDim2.fromOffset(scoreWidth, plan.header)
		placeLabel.TextSize = math.clamp(plan.header - 2, 11, 16)
		playerLabel.TextSize = placeLabel.TextSize
		scoreLabel.TextSize = placeLabel.TextSize
		y += plan.header + plan.gap
		list.Position = UDim2.fromOffset(plan.margin, y)
		list.Size = UDim2.fromOffset(inner, plan.listHeight)
		notice.Size = UDim2.new(1, -8, 0, math.max(plan.row * 2, 36))
		notice.TextSize = placeLabel.TextSize
		for _, row in rowFrames do
			row.Size = UDim2.new(1, -8, 0, plan.row)
			local mineRow = row:GetAttribute("Mine") == true
			UiChrome.paint(row, if mineRow then "selected" else "panel")
			local ink = UiChrome.ink(if mineRow then "selected" else "panel")
			local placeInk = row:FindFirstChild("Place")
			local nameInk = row:FindFirstChild("Name")
			local scoreInk = row:FindFirstChild("Score")
			if placeInk ~= nil and placeInk:IsA("TextLabel") then
				placeInk.TextColor3 = ink
			end
			if nameInk ~= nil and nameInk:IsA("TextLabel") then
				nameInk.TextColor3 = ink
			end
			if scoreInk ~= nil and scoreInk:IsA("TextLabel") then
				scoreInk.TextColor3 = ink
			end
			local placeCell = row:FindFirstChild("Place") :: TextLabel
			local nameCell = row:FindFirstChild("Name") :: TextLabel
			local scoreCell = row:FindFirstChild("Score") :: TextLabel
			placeCell.Size = UDim2.fromOffset(placeWidth, plan.row)
			nameCell.Position = UDim2.fromOffset(placeWidth, 0)
			nameCell.Size = UDim2.fromOffset(math.max(0, inner - 8 - placeWidth - scoreWidth), plan.row)
			scoreCell.Position = UDim2.fromOffset(inner - 8 - scoreWidth, 0)
			scoreCell.Size = UDim2.fromOffset(scoreWidth, plan.row)
			placeCell.TextSize = placeLabel.TextSize
			nameCell.TextSize = placeLabel.TextSize
			scoreCell.TextSize = placeLabel.TextSize
		end
		y += plan.listHeight + plan.gap
		closeButton.Position = UDim2.fromOffset(plan.margin, y)
		closeButton.Size = UDim2.fromOffset(inner, plan.close)
		UiChrome.paint(closeButton, "panel")
		closeButton.TextSize = math.clamp(plan.close - 16, 13, 20)
	end

	local function render()
		titleLabel.Text = Localization.getText("Rank.Title")
		closeButton.Text = Localization.getText("Rank.Close")
		placeLabel.Text = Localization.getText("Rank.Place")
		playerLabel.Text = Localization.getText("Rank.Player")
		scoreLabel.Text = Localization.getText("Rank.Score")
		if not RankState.received() then
			mineLabel.Text = Localization.getText("Rank.Loading")
		elseif not RankState.recorded() then
			mineLabel.Text = Localization.getText("Rank.None")
		else
			mineLabel.Text = Localization.getText("Rank.Mine", nil, { score = RankState.bestScore() or 0 })
		end
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
			row:SetAttribute("Mine", mineRow)
			local placeCell = row:FindFirstChild("Place") :: TextLabel
			local nameCell = row:FindFirstChild("Name") :: TextLabel
			local scoreCell = row:FindFirstChild("Score") :: TextLabel
			placeCell.Text = tostring(entry.rank)
			nameCell.Text = entry.name
			scoreCell.Text = tostring(entry.score)
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
		if open and PracticeRules.blockedByMatch(Players.LocalPlayer:GetAttribute("InMatch") == true, phase) then
			screen.Visible = false
			root:SetAttribute("RankOpen", false)
			return
		end
		if open and not screen.Visible then
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
	RankState.start()
	sync()
	return function()
		for _, connection in connections do
			connection:Disconnect()
		end
		stopRank()
		stopLocale()
		screen:Destroy()
	end
end

return RankScreen

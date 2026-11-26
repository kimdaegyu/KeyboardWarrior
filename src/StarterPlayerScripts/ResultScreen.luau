--!strict
local SoundManager = require(script.Parent.SoundManager)
-- Result screen for the local participant. Rank order is the server snapshot.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local constants = require(ReplicatedStorage.Shared.IngameConstants)
local Localization = require(ReplicatedStorage.Shared.Localization)
local RewardRules = require(ReplicatedStorage.Shared.RewardRules)
local TableData = require(ReplicatedStorage.Shared.TableData)
local ResultLayout = require(ReplicatedStorage.Shared.ResultLayout)
local TitleRules = require(ReplicatedStorage.Shared.TitleRules)
local ItemIconUtil = require(ReplicatedStorage.Shared.ItemIconUtil)
local UiChrome = require(ReplicatedStorage.Shared.UiChrome)

local ResultScreen = {}

function ResultScreen.bind(root: Frame): () -> ()
	local stateFolder = ReplicatedStorage:WaitForChild("MatchState")
	local levels = RewardRules.levelsFromRows(TableData.rows("LevelDataSheet"))
	local request = ReplicatedStorage:WaitForChild("ResultRequest")
	local state = ReplicatedStorage:WaitForChild("ResultState")
	assert(request:IsA("RemoteEvent") and state:IsA("RemoteEvent"))

	local screen = Instance.new("Frame")
	screen.Name = "ResultScreen"
	screen.Size = UDim2.fromScale(1, 1)
	screen.BackgroundColor3 = UiChrome.Navy
	screen.BackgroundTransparency = 1
	screen.BorderSizePixel = 0
	screen.Visible = false
	screen.ZIndex = 8
	screen.Parent = root

	local summary = Instance.new("ImageLabel")
	summary.Name = "Summary"
	summary.BackgroundColor3 = UiChrome.White
	summary.BorderSizePixel = 0
	summary.ZIndex = 9
	summary.Parent = screen
	UiChrome.paint(summary, "panel")
	local closeButton = UiChrome.closeButton(summary)

	local function stat(name: string, color: Color3, xAlign: Enum.TextXAlignment): TextLabel
		local label = Instance.new("TextLabel")
		label.Name = name
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamMedium
		label.TextColor3 = color
		label.TextXAlignment = xAlign
		label.TextYAlignment = Enum.TextYAlignment.Center
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Text = ""
		label.ZIndex = 10
		label.Parent = summary
		return label
	end

	local placeLabel = stat("Place", UiChrome.Navy, Enum.TextXAlignment.Center)
	placeLabel.Font = Enum.Font.GothamBold
	local scoreLabel = stat("Score", UiChrome.Navy, Enum.TextXAlignment.Left)
	local languageLabel = stat("Language", UiChrome.Navy, Enum.TextXAlignment.Right)
	local rewardLabel = stat("Reward", UiChrome.Navy, Enum.TextXAlignment.Left)
	local titleScroll = Instance.new("ScrollingFrame")
	titleScroll.Name = "Titles"
	titleScroll.BackgroundTransparency = 1
	titleScroll.BorderSizePixel = 0
	titleScroll.ScrollBarThickness = 6
	titleScroll.Visible = false
	titleScroll.ZIndex = 10
	titleScroll.Parent = summary
	local titleLabels: {TextLabel} = {}
	local titleCatalog = TitleRules.catalog(TableData.rows("AchievementDataSheet") :: {TitleRules.Row}) or {}
	local laidTitles = 0
	local applyLayout: () -> ()
	local levelLabel = stat("Level", UiChrome.Navy, Enum.TextXAlignment.Left)
	local saveLabel = stat("Save", UiChrome.Navy, Enum.TextXAlignment.Right)
	local nextLabel = stat("Next", UiChrome.Navy, Enum.TextXAlignment.Center)
	local goldIcon = Instance.new("ImageLabel")
	goldIcon.Name = "Gold"
	goldIcon.BackgroundTransparency = 1
	goldIcon.ZIndex = 11
	goldIcon.Parent = summary
	goldIcon.Visible = ItemIconUtil.apply(goldIcon, 1)
	goldIcon.ScaleType = Enum.ScaleType.Fit

	local barBack = Instance.new("Frame")
	barBack.Name = "ExpBar"
	barBack.BackgroundColor3 = Color3.fromRGB(220, 226, 236)
	barBack.BorderSizePixel = 0
	barBack.ZIndex = 10
	barBack.Parent = summary
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 4)
	barCorner.Parent = barBack
	local barFill = Instance.new("Frame")
	barFill.Name = "Fill"
	barFill.BackgroundColor3 = UiChrome.Blue
	barFill.BorderSizePixel = 0
	barFill.Size = UDim2.fromScale(0, 1)
	barFill.ZIndex = 11
	barFill.Parent = barBack
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 4)
	fillCorner.Parent = barFill

	local listPanel = Instance.new("ImageLabel")
	listPanel.Name = "Ranks"
	listPanel.BackgroundColor3 = UiChrome.White
	listPanel.BorderSizePixel = 0
	listPanel.ZIndex = 9
	listPanel.Parent = screen
	UiChrome.paint(listPanel, "panel")

	local list = Instance.new("ScrollingFrame")
	list.Name = "Rows"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.CanvasSize = UDim2.new()
	list.ClipsDescendants = true
	list.Position = UDim2.fromOffset(10, 8)
	list.Size = UDim2.new(1, -20, 1, -16)
	list.ZIndex = 10
	list.Parent = listPanel

	local rowLabels: {TextLabel} = {}
	local view: {[string]: any}? = nil
	local lastRewardSound: string? = nil
	local asked = false
	local animationId: string? = nil
	local startExp, targetExp, startedAt = 0, -1, 0
	local lastDisplayedExp, lastSeconds = -1, -1
	local floorExp, nextExp = 0, nil :: number?

	local function updateProgress(current: {[string]: any})
		if type(current.totalExp) ~= "number" then
			barBack.Visible = false
			levelLabel.Text = Localization.getText("Result.LevelUnknown")
			return
		end
		if animationId ~= current.settlementId or targetExp ~= current.totalExp then
			animationId = current.settlementId
			targetExp = current.totalExp
			startExp = math.max(0, targetExp - (current.exp or 0))
			startedAt = os.clock()
			lastDisplayedExp = -1
		end
		local elapsed = math.clamp((os.clock() - startedAt) / 1.1, 0, 1)
		local animated = startExp + (targetExp - startExp) * elapsed
		local displayed = math.floor(animated)
		if displayed ~= lastDisplayedExp then
			lastDisplayedExp = displayed
			local level: number
			level, floorExp, nextExp = RewardRules.progress(displayed, levels)
			local progress = if nextExp then Localization.getText("Result.ExpBar", nil, {current = displayed, next = nextExp})
				else Localization.getText("Result.ExpMax", nil, {current = displayed})
			levelLabel.Text = Localization.getText("Result.Level", nil, {level = level}) .. "  " .. progress
		elseif elapsed >= 1 then
			return
		end
		local ratio = if nextExp then math.clamp((animated - floorExp) / (nextExp - floorExp), 0, 1) else 1
		barFill.Size = UDim2.fromScale(ratio, 1)
		barBack.Visible = true
	end

	local function updateCountdown()
		local endsAt = stateFolder:GetAttribute("PhaseEndsAt")
		if type(endsAt) ~= "number" then return end
		local seconds = math.max(0, math.ceil(endsAt + constants.Match.RestSeconds - Workspace:GetServerTimeNow()))
		if seconds == lastSeconds then return end
		lastSeconds = seconds
		nextLabel.Text = Localization.getText("Result.Next", nil, { seconds = seconds })
	end

	local function showing(): boolean
		local folder = ReplicatedStorage:FindFirstChild("MatchState")
		local phase = if folder ~= nil then folder:GetAttribute("Phase") else nil
		return phase == "Result"
			and root:GetAttribute("ResultDismissed") ~= true
			and Players.LocalPlayer:GetAttribute("InMatch") == true
			and root:GetAttribute("PracticeOpen") ~= true
			and root:GetAttribute("SettingsOpen") ~= true
			and root:GetAttribute("TutorialOpen") ~= true
			and root:GetAttribute("RankOpen") ~= true
			and root:GetAttribute("ShopOpen") ~= true
	end

	local function ensureRow(index: number): TextLabel
		local existing = rowLabels[index]
		if existing ~= nil then
			return existing
		end
		local row = Instance.new("TextLabel")
		row.BackgroundTransparency = 1
		row.Font = Enum.Font.GothamMedium
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextYAlignment = Enum.TextYAlignment.Center
		row.TextTruncate = Enum.TextTruncate.AtEnd
		row.ZIndex = 11
		UiChrome.round(row, 6)
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 7)
		row.Parent = list
		padding.Parent = row
		rowLabels[index] = row
		return row
	end

	local function titleIds(): {number}
		local current = view
		if current == nil or type(current.titles) ~= "table" then
			return {}
		end
		local ids: {number} = {}
		for _, id in current.titles do
			if type(id) == "number" then
				table.insert(ids, id)
			end
		end
		return ids
	end

	local function render()
		local current = view
		local show = showing() and current ~= nil
		screen.Visible = show
		if not show or current == nil then
			return
		end
		if #titleIds() ~= laidTitles then
			applyLayout()
			return
		end
		placeLabel.Text = Localization.getText("Result.Place", nil, {
			rank = tostring(current.rank),
			count = tostring(current.count),
		})
		scoreLabel.Text = Localization.getText("Result.Score", nil, { score = tostring(current.score) })
		if current.cpm ~= nil then
			scoreLabel.Text ..= "   ·   " .. Localization.getText("Match.CpmValue", nil, { value = current.cpm })
		end
		languageLabel.Text = Localization.getText("Result.Language", nil, {
			language = if type(current.language) == "string" then current.language else Localization.getText("Match.Language"),
		})
		rewardLabel.Text = Localization.getText("Result.Gold", nil, { gold = tostring(current.gold) })
			.. "   "
			.. Localization.getText("Result.Exp", nil, { exp = tostring(current.exp) })
		updateProgress(current)
		local saveKey = "Result.Saving"
		local saveColor = Color3.fromRGB(73, 86, 108)
		if current.saveState == "saved" then
			saveKey = "Result.Saved"
			saveColor = Color3.fromRGB(21, 111, 66)
		elseif current.saveState == "failed" then
			saveKey = "Result.SaveFailed"
			saveColor = Color3.fromRGB(165, 52, 52)
		elseif current.saveState == "unavailable" then
			saveKey = "Result.SaveUnavailable"
			saveColor = Color3.fromRGB(150, 77, 24)
		end
		saveLabel.Text = Localization.getText(saveKey)
		saveLabel.TextColor3 = saveColor
		updateCountdown()

		local rows = if type(current.rows) == "table" then current.rows else {}
		for index = 1, math.max(#rows, #rowLabels) do
			local row = rows[index]
			local label = if row ~= nil then ensureRow(index) else rowLabels[index]
			if label ~= nil then
				label.Visible = row ~= nil
				if type(row) == "table" then
					local mine = row.userId == Players.LocalPlayer.UserId
					local name = if type(row.name) == "string" then row.name else tostring(row.userId)
					local language = if type(row.language) == "string" then row.language else "EN"
					label.Text = `{row.rank}  {name}  {language}  {row.score}`
					if row.cpm ~= nil then
						label.Text ..= "   " .. Localization.getText("Match.CpmValue", nil, { value = row.cpm })
					end
					label.BackgroundColor3 = if mine then UiChrome.Blue else UiChrome.White
					label.BackgroundTransparency = if mine then 0 else 1
					label.TextColor3 = if mine then UiChrome.White else UiChrome.Navy
					label.TextSize = 16
					label.Size = UDim2.new(1, -16, 0, ResultLayout.rowStride - 2)
					label.Position = UDim2.fromOffset(8, (index - 1) * ResultLayout.rowStride)
				end
			end
		end
		list.CanvasSize = UDim2.fromOffset(0, math.max(#rows, 1) * ResultLayout.rowStride)
		local earned = titleIds()
		for index = 1, math.max(#earned, #titleLabels) do
			local titleId = earned[index]
			local label = titleLabels[index]
			if titleId ~= nil and label == nil then
				label = Instance.new("TextLabel")
				label.BackgroundTransparency = 1
				label.Font = Enum.Font.GothamMedium
				label.TextXAlignment = Enum.TextXAlignment.Left
				label.TextColor3 = UiChrome.Navy
				label.TextTruncate = Enum.TextTruncate.AtEnd
				label.ZIndex = 11
				label.Parent = titleScroll
				titleLabels[index] = label
			end
			if label ~= nil then
				label.Visible = titleId ~= nil
				if titleId ~= nil then
					local achievement = TitleRules.find(titleCatalog, titleId)
					local titleName = if achievement ~= nil then Localization.getText(achievement.titleKey) else tostring(titleId)
					local rimName = if achievement ~= nil then Localization.getText("Shop.Name." .. achievement.shopId) else ""
					label.Text = Localization.getText("Result.TitleLine", nil, { title = titleName, rim = rimName })
					label.TextSize = 14
					label.Size = UDim2.new(1, -8, 0, 16)
					label.Position = UDim2.fromOffset(0, (index - 1) * 18)
				end
			end
		end
		titleScroll.CanvasSize = UDim2.fromOffset(0, math.max(#earned, 1) * 18)
	end

	applyLayout = function()
		local size = root.AbsoluteSize
		if size.X < 50 or size.Y < 50 then
			return
		end
		local content = root:GetAttribute("ContentWidth")
		local viewport = size.X
		if type(content) == "number" then
			viewport = math.min(viewport, content)
		end
		local plan = ResultLayout.plan(viewport, size.Y, constants.UI.CompactHeight, constants.UI.CompactWidth)
		local earnedCount = #titleIds()
		laidTitles = earnedCount
		local titleBox = 0
		if earnedCount > 0 then
			titleBox = math.min(if plan.compact then 54 else 72, earnedCount * 18)
		end
		viewport = math.min(viewport, 600)
		local origin = math.floor((size.X - viewport) / 2)
		local x = origin + plan.margin
		local width = math.max(0, viewport - plan.margin * 2)
		summary.Position = UDim2.fromOffset(x, plan.margin)
		summary.Size = UDim2.fromOffset(width, plan.summaryHeight + titleBox)

		listPanel.Position = UDim2.fromOffset(x, plan.margin + plan.summaryHeight + titleBox + plan.gap)
		listPanel.Size = UDim2.fromOffset(width, math.max(0, plan.listHeight - titleBox))

		local textSize = if plan.compact then 14 else 18
		local placeSize = if plan.compact then 22 else 32
		placeLabel.TextSize = placeSize
		scoreLabel.TextSize = textSize + 2
		languageLabel.TextSize = textSize
		rewardLabel.TextSize = textSize
		levelLabel.TextSize = textSize
		saveLabel.TextSize = textSize - 1
		nextLabel.TextSize = textSize - 1
		local side = if plan.compact then 32 else 40
		closeButton.Position = UDim2.new(1, -4, 0, 3)
		closeButton.Size = UDim2.fromOffset(side, side)
		local y = 8
		placeLabel.Position = UDim2.fromOffset(side + 6, y)
		placeLabel.Size = UDim2.new(1, -2 * (side + 6), 0, placeSize + 4)
		y += placeSize + 4
		scoreLabel.Position = UDim2.fromOffset(12, y)
		scoreLabel.Size = UDim2.new(0.58, -12, 0, textSize + 6)
		languageLabel.Position = UDim2.new(0.58, 0, 0, y)
		languageLabel.Size = UDim2.new(0.42, -12, 0, textSize + 6)
		y += textSize + 6
		local rewardShift = if goldIcon.Visible then textSize + 8 else 0
		goldIcon.Position = UDim2.fromOffset(12, y)
		goldIcon.Size = UDim2.fromOffset(textSize + 4, textSize + 4)
		rewardLabel.Position = UDim2.fromOffset(12 + rewardShift, y)
		rewardLabel.Size = UDim2.new(1, -24 - rewardShift, 0, textSize + 6)
		y += textSize + 8
		titleScroll.Visible = titleBox > 0
		titleScroll.Position = UDim2.fromOffset(12, y)
		titleScroll.Size = UDim2.new(1, -24, 0, titleBox)
		y += titleBox
		levelLabel.Position = UDim2.fromOffset(12, y)
		levelLabel.Size = UDim2.new(0.62, -12, 0, textSize + 6)
		saveLabel.Position = UDim2.new(0.62, 0, 0, y)
		saveLabel.Size = UDim2.new(0.38, -12, 0, textSize + 6)
		y += textSize + 8
		barBack.Position = UDim2.fromOffset(12, y)
		barBack.Size = UDim2.new(1, -24, 0, 8)
		y += 12
		nextLabel.Position = UDim2.fromOffset(12, y)
		nextLabel.Size = UDim2.new(1, -24, 0, textSize + 4)
		render()
	end

	local function sync()
		if stateFolder:GetAttribute("Phase") ~= "Result" then
			root:SetAttribute("ResultDismissed", nil)
		end
		local show = showing()
		if not show then
			asked = false
			view = nil
			screen.Visible = false
			return
		end
		if not asked then
			asked = true
			request:FireServer()
		end
		applyLayout()
	end

	local function onResult(message: any)
		if type(message) ~= "table" or type(message.settlementId) ~= "string" or type(message.rows) ~= "table" then
			return
		end
		if not showing() or message.matchId ~= stateFolder:GetAttribute("MatchId") then
			return
		end
		if lastRewardSound ~= message.settlementId then
			lastRewardSound = message.settlementId
			SoundManager.play("Reward")
		end
		view = message
		render()
	end

	closeButton.Activated:Connect(function()
		SoundManager.play("UIClose")
		root:SetAttribute("ResultDismissed", true)
		sync()
	end)
	applyLayout()
	local connections = {
		root:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout),
		root:GetAttributeChangedSignal("ContentWidth"):Connect(applyLayout),
		stateFolder:GetAttributeChangedSignal("Phase"):Connect(sync),
		Players.LocalPlayer:GetAttributeChangedSignal("InMatch"):Connect(sync),
		root:GetAttributeChangedSignal("PracticeOpen"):Connect(sync),
		root:GetAttributeChangedSignal("SettingsOpen"):Connect(sync),
		root:GetAttributeChangedSignal("TutorialOpen"):Connect(sync),
		root:GetAttributeChangedSignal("RankOpen"):Connect(sync),
		root:GetAttributeChangedSignal("ShopOpen"):Connect(sync),
		state.OnClientEvent:Connect(onResult),
		RunService.Heartbeat:Connect(function()
			if screen.Visible and view then
				updateProgress(view)
				updateCountdown()
			end
		end),
	}
	local stopLocale = Localization.onChanged(function()
		lastDisplayedExp, lastSeconds = -1, -1
		render()
	end)
	sync()

	return function()
		for _, connection in connections do
			connection:Disconnect()
		end
		stopLocale()
		screen:Destroy()
	end
end

return ResultScreen

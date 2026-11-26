--!strict
local SoundManager = require(script.Parent.SoundManager)
-- Shared typing screen. The physical keyboard and the touch keys share one buffer.
-- English mode consumes Latin keys so an OS keyboard and Hangul composition never enter the buffer.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local Layout = require(script.Parent.Layout)
local Workspace = game:GetService("Workspace")

local constants = require(ReplicatedStorage.Shared.IngameConstants)
local Localization = require(ReplicatedStorage.Shared.Localization)
local QuestionRules = require(ReplicatedStorage.Shared.QuestionRules)
local TypingLayout = require(ReplicatedStorage.Shared.TypingLayout)
local UiChrome = require(ReplicatedStorage.Shared.UiChrome)
local MatchCamera = require(script.Parent.MatchCamera)
local SettingsState = require(script.Parent.SettingsState)
local TypingPad = require(script.Parent.TypingPad)

local TypingScreen = {}

local function formatTime(seconds: number): string
	local shown = math.max(0, math.ceil(seconds - 1e-4))
	local minutes = math.floor(shown / 60)
	local remainder = shown % 60
	return string.format("%d:%02d", minutes, remainder)
end

function TypingScreen.bind(root: Frame): () -> ()
	local request = ReplicatedStorage:WaitForChild("QuestionRequest")
	local submit = ReplicatedStorage:WaitForChild("QuestionSubmit")
	local feedback = ReplicatedStorage:WaitForChild("QuestionFeedback")
	local scoreRequest = ReplicatedStorage:WaitForChild("ScoreRequest")
	local scoreState = ReplicatedStorage:WaitForChild("ScoreState")
	local leaveMatch = ReplicatedStorage:WaitForChild("MatchLeave")
	assert(request:IsA("RemoteEvent") and submit:IsA("RemoteEvent") and feedback:IsA("RemoteEvent"))
	assert(scoreRequest:IsA("RemoteEvent") and scoreState:IsA("RemoteEvent") and leaveMatch:IsA("RemoteEvent"))

	local screen = Instance.new("Frame")
	screen.Name = "TypingScreen"
	screen.Size = UDim2.fromScale(1, 1)
	screen.BackgroundColor3 = Color3.fromRGB(12, 8, 24)
	screen.BackgroundTransparency = 1
	screen.BorderSizePixel = 0
	screen.Visible = false
	screen.Active = false
	screen.ZIndex = 4
	screen.Parent = root

	local column = Instance.new("Frame")
	column.Name = "Prompt"
	column.BackgroundTransparency = 1
	column.ZIndex = 5
	column.Parent = screen

	local leaveButton = Instance.new("TextButton")
	leaveButton.Name = "Leave"
	leaveButton.Text = ""
	leaveButton.AutoButtonColor = false
	leaveButton.ZIndex = 6
	leaveButton.Parent = column
	UiChrome.paint(leaveButton, "panel")
	local leaveIcon = UiChrome.icon(leaveButton, 10078)
	leaveIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	leaveIcon.Position = UDim2.fromScale(0.5, 0.5)

	local timeLabel = Instance.new("TextLabel")
	timeLabel.Name = "Time"
	timeLabel.BackgroundColor3 = UiChrome.White
	timeLabel.BackgroundTransparency = 0.2
	timeLabel.Font = Enum.Font.GothamMedium
	timeLabel.TextColor3 = UiChrome.Navy
	timeLabel.TextXAlignment = Enum.TextXAlignment.Center
	timeLabel.TextYAlignment = Enum.TextYAlignment.Center
	timeLabel.Text = ""
	timeLabel.TextTruncate = Enum.TextTruncate.AtEnd
	timeLabel.ZIndex = 6
	UiChrome.round(timeLabel)
	timeLabel.Parent = column

	local scoreLabel = Instance.new("TextLabel")
	scoreLabel.Name = "MyScore"
	scoreLabel.BackgroundColor3 = UiChrome.White
	scoreLabel.BackgroundTransparency = 0.2
	scoreLabel.Font = Enum.Font.GothamMedium
	scoreLabel.TextColor3 = UiChrome.Navy
	scoreLabel.TextXAlignment = Enum.TextXAlignment.Center
	scoreLabel.TextYAlignment = Enum.TextYAlignment.Center
	scoreLabel.Text = ""
	scoreLabel.TextTruncate = Enum.TextTruncate.AtEnd
	scoreLabel.ZIndex = 6
	UiChrome.round(scoreLabel)
	scoreLabel.Parent = column

	local rankButton = Instance.new("TextButton")
	rankButton.Name = "MyRank"
	rankButton.BackgroundColor3 = UiChrome.White
	rankButton.BackgroundTransparency = 0.2
	rankButton.AutoButtonColor = false
	rankButton.Font = Enum.Font.GothamMedium
	rankButton.TextColor3 = UiChrome.Navy
	rankButton.TextXAlignment = Enum.TextXAlignment.Center
	rankButton.TextYAlignment = Enum.TextYAlignment.Center
	rankButton.Text = ""
	rankButton.TextTruncate = Enum.TextTruncate.AtEnd
	rankButton.ZIndex = 6
	UiChrome.round(rankButton)
	rankButton.Parent = column

	local questionPanel = Instance.new("ImageLabel")
	questionPanel.Name = "Question"
	questionPanel.BackgroundColor3 = UiChrome.White
	questionPanel.BorderSizePixel = 0
	questionPanel.ZIndex = 6
	questionPanel.Parent = column
	UiChrome.paint(questionPanel, "panel")
	questionPanel.BackgroundTransparency = 0.2

	local questionText = Instance.new("TextLabel")
	questionText.Name = "PromptText"
	questionText.BackgroundTransparency = 1
	questionText.Position = UDim2.fromOffset(8, 6)
	questionText.Size = UDim2.new(1, -16, 1, -12)
	questionText.Font = Enum.Font.GothamMedium
	questionText.TextColor3 = UiChrome.Navy
	questionText.TextWrapped = false
	questionText.TextXAlignment = Enum.TextXAlignment.Center
	questionText.TextYAlignment = Enum.TextYAlignment.Center
	questionText.Text = ""
	questionText.ZIndex = 7
	questionText.Parent = questionPanel

	local glossLabel = Instance.new("TextLabel")
	glossLabel.Name = "Gloss"
	glossLabel.BackgroundTransparency = 1
	glossLabel.Font = Enum.Font.Gotham
	glossLabel.TextColor3 = UiChrome.Navy
	glossLabel.TextWrapped = true
	glossLabel.TextXAlignment = Enum.TextXAlignment.Center
	glossLabel.TextYAlignment = Enum.TextYAlignment.Center
	glossLabel.Text = ""
	glossLabel.Visible = false
	glossLabel.ZIndex = 7
	glossLabel.Parent = questionPanel

	local pointsLabel = Instance.new("TextLabel")
	pointsLabel.Name = "Points"
	pointsLabel.BackgroundTransparency = 1
	pointsLabel.Font = Enum.Font.GothamBold
	pointsLabel.TextColor3 = Color3.fromRGB(255, 214, 102)
	pointsLabel.TextXAlignment = Enum.TextXAlignment.Right
	pointsLabel.TextYAlignment = Enum.TextYAlignment.Center
	pointsLabel.Text = ""
	pointsLabel.ZIndex = 8
	pointsLabel.Parent = questionPanel

	local rankPanel = Instance.new("ImageLabel")
	rankPanel.Name = "Ranks"
	rankPanel.BackgroundColor3 = UiChrome.White
	rankPanel.BorderSizePixel = 0
	rankPanel.ZIndex = 9
	rankPanel.Visible = false
	rankPanel.Parent = screen
	UiChrome.paint(rankPanel, "panel")

	local rankList = Instance.new("ScrollingFrame")
	rankList.Name = "Rows"
	rankList.BackgroundTransparency = 1
	rankList.BorderSizePixel = 0
	rankList.ScrollBarThickness = 4
	rankList.ScrollingDirection = Enum.ScrollingDirection.Y
	rankList.CanvasSize = UDim2.new()
	rankList.ZIndex = 7
	rankList.Parent = rankPanel

	local inputLabel = Instance.new("TextLabel")
	inputLabel.Name = "Input"
	inputLabel.BackgroundColor3 = UiChrome.White
	inputLabel.BackgroundTransparency = 0.2
	inputLabel.Font = Enum.Font.GothamMedium
	inputLabel.TextXAlignment = Enum.TextXAlignment.Center
	inputLabel.TextYAlignment = Enum.TextYAlignment.Center
	inputLabel.TextTruncate = Enum.TextTruncate.AtEnd
	inputLabel.Text = ""
	inputLabel.ZIndex = 6
	UiChrome.round(inputLabel)
	inputLabel.Parent = column

	local session: QuestionRules.ClientSession? = nil
	local buffer = ""
	local locked = false
	local echo = ""
	local sentMark = ""
	local open = false
	local trackingId = 0
	local lastReason: string? = nil
	local standings: {QuestionRules.Standing} = {}
	local rankNames: {[number]: string} = {}
	local rankLanguages: {[number]: string} = {}
	local lastPlayId = 0
	local ranksOpen = false
	local pendingLeaveId = 0
	local compactRanks = false
	local lastQuestionHeight = 0
	local lastTextSize = 28

	local measuredText, measuredWidth, measuredSize = "", -1, -1
	local function layoutGloss(questionHeight: number, textSize: number)
		lastQuestionHeight = questionHeight
		lastTextSize = textSize
		local gloss = if session ~= nil then SettingsState.glossText(session.questionId) else ""
		glossLabel.Text = gloss
		local band = TypingLayout.matchDetailHeight(questionHeight)
		glossLabel.Visible = gloss ~= ""
		glossLabel.Position = UDim2.new(0, 8, 1, -band)
		glossLabel.Size = UDim2.new(1, -16, 0, band)
		glossLabel.TextSize = math.clamp(band - 3, 10, 18)
		pointsLabel.Position = UDim2.new(1, -80, 1, -band)
		pointsLabel.Size = UDim2.fromOffset(72, band)
		pointsLabel.TextSize = math.clamp(band - 3, 10, 22)
		questionText.Size = UDim2.new(1, -16, 0, math.max(1, questionHeight - band - 4))
		local width = math.max(1, questionPanel.Size.X.Offset - 16)
		local preferred = math.max(1, math.min(textSize, questionHeight - band - 6))
		local prompt = questionText.Text
		if prompt ~= measuredText or width ~= measuredWidth or preferred ~= measuredSize then
			measuredText, measuredWidth, measuredSize = prompt, width, preferred
			local function fits(size: number): boolean
				return TextService:GetTextSize(prompt, size, questionText.Font, Vector2.new(100000, 1000)).X <= width
			end
			local low, high = 1, preferred
			while low < high do
				local mid = math.ceil((low + high) / 2)
				if fits(mid) then low = mid else high = mid - 1 end
			end
			questionText.TextSize = low
		end
	end
	local rankRows: {TextLabel} = {}

	local function activeMatchId(): number
		local folder = ReplicatedStorage:FindFirstChild("MatchState")
		local phase = if folder ~= nil then folder:GetAttribute("Phase") else nil
		local matchId = if folder ~= nil then folder:GetAttribute("MatchId") else nil
		return QuestionRules.clientMatchId(
			if type(phase) == "string" then phase else nil,
			Players.LocalPlayer:GetAttribute("InMatch") == true,
			if type(matchId) == "number" then matchId else nil
		)
	end

	local function colorFromHex(hex: string): Color3
		local digits = string.match(hex, "^#(%x%x%x%x%x%x)$")
		local value = if digits ~= nil then tonumber(digits, 16) else nil
		if value == nil then
			return Color3.fromRGB(255, 255, 255)
		end
		return Color3.fromRGB(math.floor(value / 65536) % 256, math.floor(value / 256) % 256, value % 256)
	end

	local function mine(): QuestionRules.Standing?
		local userId = Players.LocalPlayer.UserId
		for _, row in standings do
			if row.userId == userId then
				return row
			end
		end
		return nil
	end

	local function ensureRankRow(index: number): TextLabel
		local existing = rankRows[index]
		if existing ~= nil then
			return existing
		end
		local row = Instance.new("TextLabel")
		row.BackgroundTransparency = 1
		row.Font = Enum.Font.GothamMedium
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextYAlignment = Enum.TextYAlignment.Center
		row.TextTruncate = Enum.TextTruncate.AtEnd
		row.ZIndex = 8
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = row
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 6)
		padding.Parent = row
		row.Parent = rankList
		rankRows[index] = row
		return row
	end

	local function renderBoard()
		local rows = standings
		if compactRanks then
			rows = QuestionRules.visibleRanks(standings, Players.LocalPlayer.UserId, 5)
		end
		local shown = if rankPanel.Visible then #rows else 0
		for index = 1, math.max(shown, #rankRows) do
			local row = rows[index]
			local label = rankRows[index]
			if row ~= nil and label == nil then
				label = ensureRankRow(index)
			end
			if label ~= nil then
				label.Visible = row ~= nil and rankPanel.Visible
				if row ~= nil then
					local displayName = rankNames[row.userId] or tostring(row.userId)
					local language = rankLanguages[row.userId] or Localization.getText("Match.Language")
					label.Text = `{row.rank}  {displayName}  {language}  {row.score}`
					local mineRow = row.userId == Players.LocalPlayer.UserId
					label.BackgroundColor3 = if mineRow then UiChrome.Blue else UiChrome.White
					label.BackgroundTransparency = if mineRow then 0 else 1
					label.TextColor3 = if mineRow then UiChrome.White else UiChrome.Navy
					label.TextSize = 14
					label.Size = UDim2.new(1, -12, 0, 22)
					label.Position = UDim2.fromOffset(8, (index - 1) * 24)
				end
			end
		end
		rankList.CanvasSize = UDim2.fromOffset(0, math.max(shown, 1) * 24)
	end

	local function render()
		local folder = ReplicatedStorage:FindFirstChild("MatchState")
		local endsAt = if folder ~= nil then folder:GetAttribute("PhaseEndsAt") else nil
		local remain = 0
		if type(endsAt) == "number" then
			remain = math.max(0, endsAt - Workspace:GetServerTimeNow())
		end
		local timeText = Localization.getText("Lobby.TimeLeft", nil, { time = formatTime(remain) })
		if remain > 0 and remain <= constants.Match.DoubleScoreSeconds then
			timeText ..= " " .. Localization.getText("Match.DoubleTime")
		end
		timeLabel.Text = timeText
		local self = mine()
		local total = if self ~= nil then self.score else (if session ~= nil then session.total else 0)
		local rankText = if self ~= nil then tostring(self.rank) else "-"
		scoreLabel.Text = Localization.getText("Match.MyScore", nil, { score = tostring(total) })
		local rankLine = Localization.getText("Match.MyRank", nil, { rank = rankText })
		local toggle = if ranksOpen then Localization.getText("Match.HideRanks") else Localization.getText("Match.ShowRanks")
		rankButton.Text = rankLine .. " " .. toggle
		if session ~= nil and session.text ~= "" then
			questionText.Text = string.gsub(session.text, "[\r\n]+", " ")
			pointsLabel.Text = Localization.getText("Match.Points", nil, { points = tostring(session.points) })
			pointsLabel.TextColor3 = colorFromHex(session.colorHex)
			questionPanel.ImageColor3 = Color3.new(1, 1, 1)
			questionPanel.BackgroundColor3 = UiChrome.White
			inputLabel.Text = if buffer == "" then Localization.getText("Match.TypeHere") else buffer
			inputLabel.TextTransparency = if buffer == "" then 0.35 else 0
			inputLabel.TextColor3 = UiChrome.Navy
		elseif lastReason == "closed" then
			questionText.Text = Localization.getText("Match.NoQuestion")
			pointsLabel.Text = ""
			questionPanel.ImageColor3 = Color3.new(1, 1, 1)
			questionPanel.BackgroundColor3 = UiChrome.White
			inputLabel.Text = ""
		else
			questionText.Text = ""
			pointsLabel.Text = ""
			questionPanel.ImageColor3 = Color3.new(1, 1, 1)
			questionPanel.BackgroundColor3 = UiChrome.White
			inputLabel.Text = if buffer == "" then Localization.getText("Match.TypeHere") else buffer
			inputLabel.TextColor3 = UiChrome.Navy
			inputLabel.TextTransparency = if buffer == "" then 0.35 else 0
		end
		if lastQuestionHeight > 0 then
			layoutGloss(lastQuestionHeight, lastTextSize)
		end
		renderBoard()
	end

	local setDraft: (string) -> ()
	local submitEnter: () -> ()
	local pad = TypingPad.mount(screen, "KeyboardWarriorTyping", function(text: string)
		setDraft(text)
	end, function()
		submitEnter()
	end)

	local function send()
		local current = session
		if current == nil or buffer == "" then
			return
		end
		local mark = tostring(current.issue) .. "\0" .. buffer
		if mark == sentMark then
			return
		end
		sentMark = mark
		local payload = buffer
		local method = pad:inputMethod()
		local answering = current.text ~= "" and QuestionRules.matches(buffer, current.text)
		if answering then
			echo = payload
			buffer = ""
			locked = false
			pad:settleField(payload)
			pad:composeSettled()
			pad:setText("")
		end
		submit:FireServer(current.matchId, current.issue, payload, method)
	end

	local function echoBlocks(nextText: string): boolean
		local current = session
		if echo == "" or nextText ~= echo or current == nil then
			return false
		end
		local completing = QuestionRules.continuesAnswer(buffer, echo, current.text)
			and sentMark ~= tostring(current.issue) .. "\0" .. echo
		return not completing
	end

	function setDraft(nextText: string)
		if not open or session == nil then
			pad:setText(buffer)
			return
		end
		nextText = QuestionRules.clip(nextText, QuestionRules.MaxInputLength)
		if echoBlocks(nextText) then
			pad:setText(buffer)
			return
		end
		if nextText == buffer then
			pad:setText(buffer)
			return
		end
		buffer = nextText
		pad:setText(buffer)
		render()
		local current = session
		if current ~= nil and QuestionRules.autoSubmits(current.typing) and current.text ~= "" and QuestionRules.matches(buffer, current.text) then
			send()
			render()
		end
	end

	function submitEnter()
		if not open or session == nil or not QuestionRules.acceptEnter(locked, buffer) then
			return
		end
		send()
		render()
	end


	local function applyLayout()
		local size = root.AbsoluteSize
		if size.X < 50 or size.Y < 50 then
			return
		end
		local metrics = Layout.metrics(size)
		local viewport = metrics.contentWidth
		local plan = TypingLayout.plan(
			viewport,
			size.Y,
			root:GetAttribute("TouchControls") == true,
			constants.UI.CompactHeight,
			constants.UI.CompactWidth,
			metrics.margin
		)
		local origin = math.floor((size.X - viewport) / 2)
		local x = if plan.compact then math.floor((size.X - plan.questionWidth) / 2) else origin + plan.margin
		compactRanks = plan.compact
		local promptWidth = plan.questionWidth
		column.Position = UDim2.fromOffset(x, plan.margin)
		column.Size = UDim2.fromOffset(promptWidth, plan.blockHeight)
		local side = plan.timeHeight
		local infoWidth = math.max(0, promptWidth - side - plan.gap)
		local cell = math.floor(infoWidth / 3)
		local infoSpare = infoWidth - cell * 3
		local infoX = side + plan.gap
		leaveButton.Position = UDim2.fromOffset(0, 0)
		leaveButton.Size = UDim2.fromOffset(side, side)
		local iconSide = math.max(1, math.floor(side * 0.62))
		leaveIcon.Size = UDim2.fromOffset(iconSide, iconSide)
		timeLabel.Position = UDim2.fromOffset(infoX, 0)
		timeLabel.TextSize = math.clamp(plan.timeHeight - 8, 12, if plan.compact then 18 else 28)
		scoreLabel.TextSize = timeLabel.TextSize
		rankButton.TextSize = timeLabel.TextSize
		timeLabel.Size = UDim2.fromOffset(cell, side)
		scoreLabel.Position = UDim2.fromOffset(infoX + cell, 0)
		scoreLabel.Size = UDim2.fromOffset(cell, side)
		rankButton.Position = UDim2.fromOffset(infoX + cell * 2, 0)
		rankButton.Size = UDim2.fromOffset(cell + infoSpare, side)
		questionPanel.Position = UDim2.fromOffset(0, plan.timeHeight + plan.gap)
		questionPanel.Size = UDim2.fromOffset(promptWidth, plan.questionHeight)

		questionText.Position = UDim2.fromOffset(8, 4)
		layoutGloss(plan.questionHeight, plan.textSize)
		inputLabel.Position = UDim2.fromOffset(0, plan.timeHeight + plan.gap + plan.questionHeight + plan.gap)
		inputLabel.Size = UDim2.fromOffset(promptWidth, plan.inputHeight)
		inputLabel.TextSize = plan.inputTextSize
		pad:placeInput(inputLabel)
		rankPanel.Visible = ranksOpen
		rankPanel.Position = UDim2.fromOffset(x, plan.margin + plan.timeHeight + plan.gap)
		rankPanel.Size = UDim2.fromOffset(promptWidth, plan.questionHeight)
		rankList.Size = UDim2.fromScale(1, 1)
		local keyWidth = math.max(0, viewport - plan.margin * 2)
		pad:layout(
			UDim2.fromOffset(origin + plan.margin, size.Y - plan.margin - plan.keyBlock),
			keyWidth,
			plan.rowHeight,
			plan.gap,
			plan.showKeys
		)
	end

	local function syncMode()
		local id = activeMatchId()
		if id ~= trackingId then
			trackingId = id
			session = nil
			buffer = ""
			echo = ""
			sentMark = ""
			pad:composeSettled()
			pad:setText("")
			locked = false
			lastReason = nil
			standings = {}
			table.clear(rankNames)
			table.clear(rankLanguages)
			ranksOpen = false
			if id > 0 then
				lastPlayId = id
				request:FireServer()
				scoreRequest:FireServer()
			end
		end
		if activeMatchId() ~= pendingLeaveId then
			pendingLeaveId = 0
		end
		leaveButton.Active = pendingLeaveId == 0
		local overlay = root:GetAttribute("PracticeOpen") == true
			or root:GetAttribute("SettingsOpen") == true
			or root:GetAttribute("TutorialOpen") == true
			or root:GetAttribute("RankOpen") == true
			or root:GetAttribute("ShopOpen") == true
		local playing = id > 0 and not overlay
		if playing ~= open then
			open = playing
			pad:setEngaged(open)
		end
		pad:setIme(session ~= nil and QuestionRules.usesIme(session.typing))
		local folder = ReplicatedStorage:FindFirstChild("MatchState")
		local phase = if folder ~= nil then folder:GetAttribute("Phase") else nil
		MatchCamera.setOrbit(phase == "Result" and Players.LocalPlayer:GetAttribute("InMatch") == true)
		MatchCamera.setPlaying(playing)
		screen.Visible = playing
		applyLayout()
		render()
	end

	local function onFeedback(message: any)
		if type(message) ~= "table" then
			return
		end
		local previous = if session ~= nil then session.issue else 0
		local matchId = activeMatchId()
		session, buffer = QuestionRules.applyClient(session, buffer, message, matchId)
		if matchId > 0 and message.matchId == matchId and previous > 0 and message.issue == previous then
			if message.ok and session and session.issue ~= previous then
				SoundManager.play("UIConfirm")
			elseif message.reason == "mismatch" and locked then
				SoundManager.play("UIError")
			end
		end
		pad:setIme(session ~= nil and QuestionRules.usesIme(session.typing))
		if session == nil or session.issue ~= previous then
			sentMark = ""
			locked = false
			pad:composeSettled()
		elseif message.reason == "mismatch" then
			locked = false
		end
		pad:setText(buffer)
		if type(message.reason) == "string" then
			lastReason = message.reason
		end
		if session ~= nil and buffer ~= "" and QuestionRules.autoSubmits(session.typing) and session.text ~= "" and QuestionRules.matches(buffer, session.text) then
			send()
		end
		render()
	end

	local function onScore(message: any)
		if type(message) ~= "table" or type(message.matchId) ~= "number" or type(message.rows) ~= "table" then
			return
		end
		local live = activeMatchId()
		if live > 0 then
			if message.matchId ~= live then
				return
			end
		elseif message.sealed ~= true or message.matchId ~= lastPlayId then
			return
		end
		local nextRows: {QuestionRules.Standing} = {}
		local nextNames: {[number]: string} = {}
		local nextLanguages: {[number]: string} = {}
		for _, row in message.rows do
			if type(row) == "table" and type(row.userId) == "number" and type(row.score) == "number" and type(row.rank) == "number" then
				table.insert(nextRows, {
					userId = row.userId,
					score = row.score,
					reachedAt = 0,
					rank = row.rank,
				})
				nextNames[row.userId] = if type(row.name) == "string" then row.name else tostring(row.userId)
				nextLanguages[row.userId] = if type(row.language) == "string" then row.language else "EN"
			end
		end
		standings = nextRows
		rankNames = nextNames
		rankLanguages = nextLanguages
		render()
	end

	leaveButton.Activated:Connect(function()
		local id = activeMatchId()
		if id <= 0 or pendingLeaveId == id then
			return
		end
		pendingLeaveId = id
		leaveButton.Active = false
		leaveMatch:FireServer(id)
	end)

	rankButton.Activated:Connect(function()
		ranksOpen = not ranksOpen
		applyLayout()
		pad:setText(buffer)
		render()
	end)

	pad:refreshLabels()
	applyLayout()
	render()

	local stateFolder = ReplicatedStorage:WaitForChild("MatchState")
	local connections = {
		root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			applyLayout()
		end),
		root:GetAttributeChangedSignal("ContentWidth"):Connect(applyLayout),
		root:GetAttributeChangedSignal("TouchControls"):Connect(applyLayout),
		stateFolder:GetAttributeChangedSignal("Phase"):Connect(syncMode),
		stateFolder:GetAttributeChangedSignal("MatchId"):Connect(syncMode),
		Players.LocalPlayer:GetAttributeChangedSignal("InMatch"):Connect(syncMode),
		root:GetAttributeChangedSignal("PracticeOpen"):Connect(syncMode),
		root:GetAttributeChangedSignal("SettingsOpen"):Connect(syncMode),
		root:GetAttributeChangedSignal("TutorialOpen"):Connect(syncMode),
		root:GetAttributeChangedSignal("RankOpen"):Connect(syncMode),
		root:GetAttributeChangedSignal("ShopOpen"):Connect(syncMode),
		feedback.OnClientEvent:Connect(onFeedback),
		scoreState.OnClientEvent:Connect(onScore),
		RunService.Heartbeat:Connect(function()
			pad:syncJump()
			if screen.Visible then
				render()
			end
		end),
	}
	local stopLocale = Localization.onChanged(function()
		pad:refreshLabels()
		render()
	end)
	local stopSettings = SettingsState.onChanged(function()
		if screen.Visible then
			render()
			applyLayout()
		end
	end)
	syncMode()

	return function()
		for _, connection in connections do
			connection:Disconnect()
		end
		stopLocale()
		stopSettings()
		MatchCamera.setPlaying(false)
		pad:destroy()
		screen:Destroy()
	end
end

return TypingScreen

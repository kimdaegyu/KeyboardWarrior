--!strict
-- Personal practice. The deck and the solved count stay on this client.
-- Typing here does not submit a match answer, update a rank, or save a profile.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local constants = require(ReplicatedStorage.Shared.IngameConstants)
local Localization = require(ReplicatedStorage.Shared.Localization)
local PracticeRules = require(ReplicatedStorage.Shared.PracticeRules)
local QuestionRules = require(ReplicatedStorage.Shared.QuestionRules)
local TableData = require(ReplicatedStorage.Shared.TableData)
local TypingLayout = require(ReplicatedStorage.Shared.TypingLayout)
local UiChrome = require(ReplicatedStorage.Shared.UiChrome)
local SettingsState = require(script.Parent.SettingsState)
local TypingPad = require(script.Parent.TypingPad)

local PracticeScreen = {}

local questionRows = TableData.rows("QuestionDataSheet")
local deckLanguage = "en"
local words, sentences = PracticeRules.catalog(questionRows, deckLanguage)

local function showTouchKeys(root: Frame): boolean
	local size = root.AbsoluteSize
	local compact = size.Y <= constants.UI.CompactHeight or size.X <= constants.UI.CompactWidth
	if compact then
		return true
	end
	if UserInputService:GetLastInputType() == Enum.UserInputType.Keyboard then
		return false
	end
	return UserInputService.TouchEnabled
end

function PracticeScreen.bind(root: Frame): () -> ()
	local screen = Instance.new("Frame")
	screen.Name = "PracticeScreen"
	screen.Size = UDim2.fromScale(1, 1)
	screen.BackgroundColor3 = UiChrome.Navy
	screen.BackgroundTransparency = 1
	screen.BorderSizePixel = 0
	screen.Visible = false
	screen.Active = true
	screen.ZIndex = 3
	screen.Parent = root

	local toolbar = Instance.new("Frame")
	toolbar.Name = "Toolbar"
	toolbar.BackgroundTransparency = 1
	toolbar.ZIndex = 5
	toolbar.Parent = screen
	UiChrome.paint(toolbar, "panel")

	local function button(name: string, role: string): TextButton
		local item = Instance.new("TextButton")
		item.Name = name
		item.Font = Enum.Font.GothamMedium
		item.TextColor3 = UiChrome.ink(role)
		item.BackgroundColor3 = if role == "primary" then UiChrome.Yellow else UiChrome.White
		item.BackgroundTransparency = 0
		item.BorderSizePixel = 0
		item.AutoButtonColor = false
		item.TextTruncate = Enum.TextTruncate.AtEnd
		item:SetAttribute("Face", role)
		item.ZIndex = 6
		item.Parent = toolbar
		return item
	end

	local exitButton = button("Exit", "panel")
	local wordButton = button("Words", "panel")
	local sentenceButton = button("Sentences", "panel")
	local solvedLabel = Instance.new("TextLabel")
	solvedLabel.Name = "Solved"
	solvedLabel.BackgroundTransparency = 1
	solvedLabel.Font = Enum.Font.GothamMedium
	solvedLabel.TextColor3 = UiChrome.Navy
	solvedLabel.TextXAlignment = Enum.TextXAlignment.Center
	solvedLabel.TextYAlignment = Enum.TextYAlignment.Center
	solvedLabel.TextTruncate = Enum.TextTruncate.AtEnd
	solvedLabel.ZIndex = 6
	solvedLabel.Parent = toolbar

	local questionPanel = Instance.new("ImageLabel")
	questionPanel.Name = "Question"
	questionPanel.BackgroundColor3 = UiChrome.White
	questionPanel.BorderSizePixel = 0
	questionPanel.ZIndex = 5
	questionPanel.Parent = screen
	UiChrome.paint(questionPanel, "panel")

	local questionText = Instance.new("TextLabel")
	questionText.Name = "Prompt"
	questionText.BackgroundTransparency = 1
	questionText.Font = Enum.Font.GothamBold
	questionText.TextColor3 = UiChrome.Navy
	questionText.TextWrapped = true
	questionText.TextXAlignment = Enum.TextXAlignment.Center
	questionText.TextYAlignment = Enum.TextYAlignment.Center
	questionText.ZIndex = 6
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
	glossLabel.ZIndex = 6
	glossLabel.Parent = questionPanel

	local inputLabel = Instance.new("TextLabel")
	inputLabel.Name = "Input"
	inputLabel.BackgroundColor3 = UiChrome.White
	inputLabel.BackgroundTransparency = 0.05
	inputLabel.TextColor3 = UiChrome.Navy
	inputLabel.Font = Enum.Font.GothamMedium
	inputLabel.TextXAlignment = Enum.TextXAlignment.Center
	inputLabel.TextYAlignment = Enum.TextYAlignment.Center
	inputLabel.TextTruncate = Enum.TextTruncate.AtEnd
	inputLabel.ZIndex = 6
	inputLabel.Parent = screen

	local session: PracticeRules.Session? = nil
	local echo = ""
	local lastQuestionHeight = 0
	local lastTextSize = 28

	local function layoutGloss(questionHeight: number, textSize: number)
		lastQuestionHeight = questionHeight
		lastTextSize = textSize
		local current = session
		local prompt = if current ~= nil then PracticeRules.prompt(current, words, sentences) else nil
		local gloss = if prompt ~= nil then SettingsState.glossText(prompt.id) else ""
		glossLabel.Text = gloss
		local band = TypingLayout.glossBand(questionHeight, gloss ~= "")
		glossLabel.Visible = band > 0
		glossLabel.Position = UDim2.new(0, 8, 1, -band - 3)
		glossLabel.Size = UDim2.new(1, -16, 0, math.max(0, band - 2))
		glossLabel.TextSize = math.clamp(textSize - 6, 12, 18)
		questionText.Size = UDim2.new(1, -16, 1, -(11 + band))
		questionText.TextSize = if band > 0 then math.clamp(math.floor((questionHeight - band) * 0.42), 14, 28) else textSize
	end
	local onDraft: (string) -> ()
	local onEnter: () -> ()
	local pad = TypingPad.mount(screen, "KeyboardWarriorPractice", function(text: string)
		onDraft(text)
	end, function()
		onEnter()
	end)

	local function render()
		local current = session
		local prompt = if current ~= nil then PracticeRules.prompt(current, words, sentences) else nil
		if prompt == nil then
			questionText.Text = Localization.getText("Practice.Empty")
			inputLabel.Text = ""
		else
			questionText.Text = prompt.text
			local draft = if current ~= nil then current.buffer else ""
			inputLabel.Text = if draft == "" then Localization.getText("Match.TypeHere") else draft
			inputLabel.TextTransparency = if draft == "" then 0.35 else 0
			inputLabel.TextColor3 = UiChrome.Navy
		end
		local solved = if current ~= nil then current.solved else 0
		solvedLabel.Text = Localization.getText("Practice.Solved", nil, { count = solved })
		exitButton.Text = Localization.getText("Practice.Exit")
		wordButton.Text = Localization.getText("Practice.Words")
		sentenceButton.Text = Localization.getText("Practice.Sentences")
		local mode = if current ~= nil then current.mode else "Word"
		wordButton:SetAttribute("Face", if mode == "Word" then "selected" else "panel")
		sentenceButton:SetAttribute("Face", if mode == "Sentence" then "selected" else "panel")
		local function paintMode(item: TextButton)
			local face = item:GetAttribute("Face")
			local role = if type(face) == "string" then face else "panel"
			UiChrome.paint(item, role)
			item.TextColor3 = UiChrome.ink(role)
		end
		paintMode(wordButton)
		paintMode(sentenceButton)
		paintMode(exitButton)
		if lastQuestionHeight > 0 then
			layoutGloss(lastQuestionHeight, lastTextSize)
		end
		pad:refreshLabels()
	end

	function onDraft(text: string)
		local current = session
		if current == nil then
			pad:setText("")
			return
		end
		if echo ~= "" and text == echo then
			local prompt = PracticeRules.prompt(current, words, sentences)
			local completing = prompt ~= nil
				and prompt.text == echo
				and current.buffer ~= ""
				and current.buffer ~= echo
				and string.sub(echo, 1, #current.buffer) == current.buffer
			if not completing then
				pad:setText(current.buffer)
				return
			end
		end
		local before = current.solved
		PracticeRules.applyText(current, words, sentences, text, not QuestionRules.autoSubmits(deckLanguage))
		if current.solved > before then
			echo = text
			pad:settleField(text)
			pad:composeSettled()
		end
		pad:setText(current.buffer)
		render()
	end

	function onEnter()
		local current = session
		if current == nil or current.buffer == "" then
			return
		end
		PracticeRules.enter(current, words, sentences)
		pad:setText(current.buffer)
		render()
	end

	local function applyLayout()
		if not screen.Visible then
			return
		end
		local size = root.AbsoluteSize
		if size.X < 50 or size.Y < 50 then
			return
		end
		local content = root:GetAttribute("ContentWidth")
		local viewport = size.X
		if type(content) == "number" then
			viewport = math.min(viewport, content)
		end
		local plan = TypingLayout.practicePlan(
			viewport,
			size.Y,
			showTouchKeys(root),
			constants.UI.CompactHeight,
			constants.UI.CompactWidth
		)
		local origin = math.floor((size.X - viewport) / 2)
		local x = origin + plan.margin
		local width = math.max(0, viewport - plan.margin * 2)
		local textSize = math.clamp(plan.toolbarHeight - 14, 12, 18)
		toolbar.Position = UDim2.fromOffset(x, plan.margin)
		toolbar.Size = UDim2.fromOffset(width, plan.toolbarHeight)
		local exitWidth = math.clamp(math.floor(width * 0.22), 72, 140)
		local modeWidth = math.clamp(math.floor(width * 0.24), 84, 180)
		local cursor = 0
		exitButton.Position = UDim2.fromOffset(cursor, 0)
		exitButton.Size = UDim2.fromOffset(exitWidth, plan.toolbarHeight)
		cursor += exitWidth + plan.gap
		wordButton.Position = UDim2.fromOffset(cursor, 0)
		wordButton.Size = UDim2.fromOffset(modeWidth, plan.toolbarHeight)
		cursor += modeWidth + plan.gap
		sentenceButton.Position = UDim2.fromOffset(cursor, 0)
		sentenceButton.Size = UDim2.fromOffset(modeWidth, plan.toolbarHeight)
		cursor += modeWidth + plan.gap
		solvedLabel.Position = UDim2.fromOffset(cursor, 0)
		solvedLabel.Size = UDim2.fromOffset(math.max(0, width - cursor), plan.toolbarHeight)
		for _, item in { exitButton, wordButton, sentenceButton, solvedLabel } do
			item.TextSize = textSize
		end
		local questionY = plan.margin + plan.toolbarHeight + plan.gap
		questionPanel.Position = UDim2.fromOffset(x, questionY)
		questionPanel.Size = UDim2.fromOffset(width, plan.questionHeight)

		questionText.Position = UDim2.fromOffset(8, 4)
		layoutGloss(plan.questionHeight, plan.textSize)
		local inputY = questionY + plan.questionHeight + plan.gap
		inputLabel.Position = UDim2.fromOffset(x, inputY)
		inputLabel.Size = UDim2.fromOffset(width, plan.inputHeight)
		inputLabel.TextSize = plan.inputTextSize
		pad:placeInput(inputLabel)
		pad:layout(
			UDim2.fromOffset(x, inputY + plan.inputHeight + plan.gap),
			width,
			plan.rowHeight,
			plan.gap,
			plan.showKeys
		)
	end

	local function closeSession()
		session = nil
		echo = ""
		pad:composeSettled()
		pad:setText("")
		pad:setEngaged(false)
		screen.Visible = false
	end

	local function sync()
		local folder = ReplicatedStorage:FindFirstChild("MatchState")
		local phaseName = if folder ~= nil then folder:GetAttribute("Phase") else nil
		local phase = if type(phaseName) == "string" then phaseName else ""
		local inMatch = Players.LocalPlayer:GetAttribute("InMatch") == true
		local open = root:GetAttribute("PracticeOpen") == true
		if open and PracticeRules.blockedByMatch(inMatch, phase) then
			closeSession()
			root:SetAttribute("PracticeOpen", false)
			return
		end
		if not open then
			closeSession()
			return
		end
		local nextLanguage = SettingsState.sessionTyping()
		if nextLanguage ~= deckLanguage then
			words, sentences = PracticeRules.catalog(questionRows, nextLanguage)
			deckLanguage = nextLanguage
			if session ~= nil then
				session.buffer = ""
				echo = ""
				pad:composeSettled()
				pad:setText("")
			end
		end
		pad:setIme(QuestionRules.usesIme(deckLanguage))
		if session == nil then
			session = PracticeRules.begin()
			pad:setText("")
		end
		local covered = root:GetAttribute("TutorialOpen") == true or root:GetAttribute("RankOpen") == true or root:GetAttribute("ShopOpen") == true
		screen.Visible = not covered
		pad:setEngaged(not covered)
		applyLayout()
		render()
	end

	exitButton.Activated:Connect(function()
		root:SetAttribute("PracticeOpen", false)
	end)
	wordButton.Activated:Connect(function()
		local current = session
		if current == nil then
			return
		end
		PracticeRules.setMode(current, "Word")
		pad:setText("")
		render()
	end)
	sentenceButton.Activated:Connect(function()
		local current = session
		if current == nil then
			return
		end
		PracticeRules.setMode(current, "Sentence")
		pad:setText("")
		render()
	end)

	local stateFolder = ReplicatedStorage:WaitForChild("MatchState")
	local connections = {
		root:GetAttributeChangedSignal("PracticeOpen"):Connect(sync),
		root:GetAttributeChangedSignal("TutorialOpen"):Connect(sync),
		root:GetAttributeChangedSignal("RankOpen"):Connect(sync),
		root:GetAttributeChangedSignal("ShopOpen"):Connect(sync),
		root:GetAttributeChangedSignal("ContentWidth"):Connect(applyLayout),
		root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			applyLayout()
			if screen.Visible then
				render()
			end
		end),
		UserInputService.LastInputTypeChanged:Connect(applyLayout),
		Players.LocalPlayer:GetAttributeChangedSignal("InMatch"):Connect(sync),
		stateFolder:GetAttributeChangedSignal("Phase"):Connect(sync),
	}
	local stopLocale = Localization.onChanged(function()
		if screen.Visible then
			render()
		end
	end)
	local stopSettings = SettingsState.onChanged(function()
		if root:GetAttribute("PracticeOpen") == true then
			sync()
		end
	end)
	sync()

	return function()
		for _, connection in connections do
			connection:Disconnect()
		end
		stopLocale()
		stopSettings()
		closeSession()
		pad:destroy()
		screen:Destroy()
	end
end

return PracticeScreen

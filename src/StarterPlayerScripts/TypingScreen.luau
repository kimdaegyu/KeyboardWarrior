--!strict
-- Shared typing screen. The physical keyboard and the touch keys share one buffer.
-- English mode consumes Latin keys so an OS keyboard and Hangul composition never enter the buffer.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local constants = require(ReplicatedStorage.Shared.IngameConstants)
local Localization = require(ReplicatedStorage.Shared.Localization)
local QuestionRules = require(ReplicatedStorage.Shared.QuestionRules)
local TypingLayout = require(ReplicatedStorage.Shared.TypingLayout)
local UIImageUtil = require(ReplicatedStorage.Shared.UIImageUtil)

local ACTION = "KeyboardWarriorTyping"
local KEY_PRIORITY = 4000

local LETTER_ROWS = {
	{ "q", "w", "e", "r", "t", "y", "u", "i", "o", "p" },
	{ "a", "s", "d", "f", "g", "h", "j", "k", "l" },
	{ "z", "x", "c", "v", "b", "n", "m" },
}

local KEY_CHARS: {[Enum.KeyCode]: string} = {}
for _, row in LETTER_ROWS do
	for _, letter in row do
		KEY_CHARS[Enum.KeyCode[string.upper(letter)]] = letter
	end
end

local TypingScreen = {}

local function formatTime(seconds: number): string
	local shown = math.max(0, math.ceil(seconds - 1e-4))
	local minutes = math.floor(shown / 60)
	local remainder = shown % 60
	return string.format("%d:%02d", minutes, remainder)
end

local function makeButton(parent: Frame, name: string, text: string, color: Color3): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = text
	button.Font = Enum.Font.GothamMedium
	button.TextColor3 = Color3.new(1, 1, 1)
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.TextTruncate = Enum.TextTruncate.AtEnd
	button.ZIndex = 6
	button.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = button
	return button
end

function TypingScreen.bind(root: Frame): () -> ()
	local request = ReplicatedStorage:WaitForChild("QuestionRequest")
	local submit = ReplicatedStorage:WaitForChild("QuestionSubmit")
	local feedback = ReplicatedStorage:WaitForChild("QuestionFeedback")
	assert(request:IsA("RemoteEvent") and submit:IsA("RemoteEvent") and feedback:IsA("RemoteEvent"))

	local screen = Instance.new("Frame")
	screen.Name = "TypingScreen"
	screen.Size = UDim2.fromScale(1, 1)
	screen.BackgroundColor3 = Color3.fromRGB(12, 8, 24)
	screen.BackgroundTransparency = 0.35
	screen.BorderSizePixel = 0
	screen.Visible = false
	screen.Active = true
	screen.ZIndex = 4
	screen.Parent = root

	local column = Instance.new("Frame")
	column.Name = "Prompt"
	column.BackgroundTransparency = 1
	column.ZIndex = 5
	column.Parent = screen

	local timeLabel = Instance.new("TextLabel")
	timeLabel.Name = "Time"
	timeLabel.BackgroundTransparency = 1
	timeLabel.Font = Enum.Font.GothamMedium
	timeLabel.TextColor3 = Color3.fromRGB(90, 230, 255)
	timeLabel.TextXAlignment = Enum.TextXAlignment.Center
	timeLabel.TextYAlignment = Enum.TextYAlignment.Center
	timeLabel.Text = ""
	timeLabel.ZIndex = 6
	timeLabel.Parent = column

	local questionPanel = Instance.new("ImageLabel")
	questionPanel.Name = "Question"
	questionPanel.BackgroundColor3 = Color3.fromRGB(40, 20, 70)
	questionPanel.BorderSizePixel = 0
	questionPanel.ZIndex = 6
	questionPanel.Parent = column
	if UIImageUtil.apply(questionPanel, "panel-9slice") then
		questionPanel.BackgroundTransparency = 1
	else
		questionPanel.BackgroundTransparency = 0.15
	end

	local questionText = Instance.new("TextLabel")
	questionText.Name = "PromptText"
	questionText.BackgroundTransparency = 1
	questionText.Position = UDim2.fromOffset(8, 6)
	questionText.Size = UDim2.new(1, -16, 1, -12)
	questionText.Font = Enum.Font.GothamMedium
	questionText.TextColor3 = Color3.new(1, 1, 1)
	questionText.TextWrapped = true
	questionText.TextXAlignment = Enum.TextXAlignment.Center
	questionText.TextYAlignment = Enum.TextYAlignment.Center
	questionText.Text = ""
	questionText.ZIndex = 7
	questionText.Parent = questionPanel

	local inputLabel = Instance.new("TextLabel")
	inputLabel.Name = "Input"
	inputLabel.BackgroundTransparency = 1
	inputLabel.Font = Enum.Font.GothamMedium
	inputLabel.TextXAlignment = Enum.TextXAlignment.Center
	inputLabel.TextYAlignment = Enum.TextYAlignment.Center
	inputLabel.TextTruncate = Enum.TextTruncate.AtEnd
	inputLabel.Text = ""
	inputLabel.ZIndex = 6
	inputLabel.Parent = column

	-- The default camera and Studio shortcuts sink I and O before a context action.
	-- A focused box still receives those characters. Touch mode never focuses it, so the OS keyboard stays hidden.
	local hardware = Instance.new("TextBox")
	hardware.Name = "HardwareInput"
	hardware.Size = UDim2.fromOffset(1, 1)
	hardware.Position = UDim2.fromOffset(-40, -40)
	hardware.BackgroundTransparency = 1
	hardware.TextTransparency = 1
	hardware.TextSize = 1
	hardware.ClearTextOnFocus = false
	hardware.MultiLine = false
	hardware.TextEditable = true
	hardware.Text = ""
	hardware.ZIndex = 1
	hardware.Parent = screen

	local keyboard = Instance.new("Frame")
	keyboard.Name = "Keyboard"
	keyboard.BackgroundTransparency = 1
	keyboard.Visible = false
	keyboard.ZIndex = 5
	keyboard.Parent = screen

	local session: QuestionRules.ClientSession? = nil
	local buffer = ""
	local locked = false
	local open = false
	local keysBound = false
	local trackingId = 0
	local lastReason: string? = nil

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

	local function render()
		local folder = ReplicatedStorage:FindFirstChild("MatchState")
		local endsAt = if folder ~= nil then folder:GetAttribute("PhaseEndsAt") else nil
		local remain = 0
		if type(endsAt) == "number" then
			remain = math.max(0, endsAt - Workspace:GetServerTimeNow())
		end
		timeLabel.Text = Localization.getText("Lobby.TimeLeft", nil, { time = formatTime(remain) })
		if session ~= nil then
			questionText.Text = session.text
		elseif lastReason == "closed" then
			questionText.Text = Localization.getText("Match.NoQuestion")
		else
			questionText.Text = ""
		end
		if buffer == "" then
			inputLabel.Text = Localization.getText("Match.TypeHere")
			inputLabel.TextColor3 = Color3.fromRGB(160, 160, 175)
		else
			inputLabel.Text = buffer
			inputLabel.TextColor3 = Color3.fromRGB(120, 255, 255)
		end
	end

	local mirroring = false

	local function send()
		local current = session
		if current == nil then
			return
		end
		submit:FireServer(current.matchId, current.issue, buffer)
	end

	local function pushHardware(text: string)
		if hardware.Text == text then
			return
		end
		mirroring = true
		hardware.Text = text
		mirroring = false
	end

	local function setDraft(nextText: string)
		if not open or locked or session == nil then
			pushHardware(buffer)
			return
		end
		if #nextText > QuestionRules.MaxInputLength then
			nextText = string.sub(nextText, 1, QuestionRules.MaxInputLength)
		end
		if nextText == buffer then
			pushHardware(buffer)
			return
		end
		buffer = nextText
		pushHardware(buffer)
		render()
		local current = session
		if current ~= nil and current.text ~= "" and QuestionRules.matches(buffer, current.text) then
			locked = true
			send()
		end
	end

	local function append(char: string)
		setDraft(buffer .. char)
	end

	local function backspace()
		if buffer == "" then
			return
		end
		setDraft(string.sub(buffer, 1, #buffer - 1))
	end

	local function submitEnter()
		if not open or session == nil then
			return
		end
		local current = session
		if current.text ~= "" and QuestionRules.matches(buffer, current.text) then
			locked = true
		end
		send()
	end

	hardware:GetPropertyChangedSignal("Text"):Connect(function()
		if mirroring or not hardware:IsFocused() then
			return
		end
		setDraft(hardware.Text)
	end)

	local function captureHardware()
		if UserInputService.TouchEnabled then
			return
		end
		if not open then
			return
		end
		hardware:CaptureFocus()
		local caret = #hardware.Text + 1
		hardware.CursorPosition = caret
		hardware.SelectionStart = caret
	end

	local function releaseHardware()
		if hardware:IsFocused() then
			hardware:ReleaseFocus()
		end
	end

	hardware.FocusLost:Connect(function(enterPressed: boolean)
		if not open or UserInputService.TouchEnabled then
			return
		end
		if enterPressed then
			submitEnter()
		end
		task.defer(captureHardware)
	end)

	local function onAction(_name: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
		if not open then
			return Enum.ContextActionResult.Pass
		end
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Sink
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.Backspace then
			backspace()
		elseif key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter then
			submitEnter()
		elseif key == Enum.KeyCode.Space then
			append(" ")
		else
			local char = KEY_CHARS[key]
			if char ~= nil then
				local upper = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
					or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
					or UserInputService:IsKeyDown(Enum.KeyCode.CapsLock)
				append(if upper then string.upper(char) else char)
			end
		end
		return Enum.ContextActionResult.Sink
	end

	local keyCodes = {}
	for key in KEY_CHARS do
		table.insert(keyCodes, key)
	end
	table.insert(keyCodes, Enum.KeyCode.Space)
	table.insert(keyCodes, Enum.KeyCode.Backspace)
	table.insert(keyCodes, Enum.KeyCode.Return)
	table.insert(keyCodes, Enum.KeyCode.KeypadEnter)

	local function bindKeys()
		if keysBound then
			return
		end
		keysBound = true
		if UserInputService.TouchEnabled then
			ContextActionService:BindActionAtPriority(ACTION, onAction, false, KEY_PRIORITY, table.unpack(keyCodes))
			return
		end
		task.defer(captureHardware)
	end

	local function unbindKeys()
		if not keysBound then
			return
		end
		keysBound = false
		ContextActionService:UnbindAction(ACTION)
		releaseHardware()
	end

	local rowButtons: {{TextButton}} = {}
	local rowWeights: {{number}?} = {}
	local letterColor = Color3.fromRGB(32, 18, 54)
	for index, letters in LETTER_ROWS do
		local row = Instance.new("Frame")
		row.Name = "Letters" .. index
		row.BackgroundTransparency = 1
		row.ZIndex = 5
		row.Parent = keyboard
		local buttons = {}
		for _, letter in letters do
			local button = makeButton(row, string.upper(letter), string.upper(letter), letterColor)
			button.Activated:Connect(function()
				append(letter)
			end)
			table.insert(buttons, button)
		end
		rowButtons[index] = buttons
		rowWeights[index] = nil
	end

	local actionRow = Instance.new("Frame")
	actionRow.Name = "Actions"
	actionRow.BackgroundTransparency = 1
	actionRow.ZIndex = 5
	actionRow.Parent = keyboard
	local backspaceButton = makeButton(actionRow, "Backspace", "", letterColor)
	local spaceButton = makeButton(actionRow, "Space", "", letterColor)
	local enterButton = makeButton(actionRow, "Enter", "", Color3.fromRGB(28, 86, 72))
	backspaceButton.Activated:Connect(backspace)
	spaceButton.Activated:Connect(function()
		append(" ")
	end)
	enterButton.Activated:Connect(submitEnter)
	rowButtons[4] = { backspaceButton, spaceButton, enterButton }
	rowWeights[4] = { 1.8, 3.2, 1.8 }

	local function refreshKeyLabels()
		backspaceButton.Text = Localization.getText("Match.Backspace")
		spaceButton.Text = Localization.getText("Match.Space")
		enterButton.Text = Localization.getText("Match.Enter")
	end

	local function showTouchKeys(): boolean
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

	local function placeRow(buttons: {TextButton}, weights: {number}?, width: number, rowHeight: number, gap: number, y: number)
		local parent = buttons[1].Parent
		if parent ~= nil and parent:IsA("GuiObject") then
			parent.Position = UDim2.fromOffset(0, y)
			parent.Size = UDim2.fromOffset(width, rowHeight)
		end
		local weightSum = 0
		if weights ~= nil then
			for _, weight in weights do
				weightSum += weight
			end
		else
			weightSum = #buttons
		end
		if weightSum <= 0 or width <= 0 or rowHeight <= 0 then
			return
		end
		local totalGap = gap * math.max(0, #buttons - 1)
		local usable = math.max(0, width - totalGap)
		local widths = table.create(#buttons)
		local used = 0
		for index, button in buttons do
			local weight = if weights ~= nil then weights[index] else 1
			local keyWidth = math.floor(usable * weight / weightSum)
			widths[index] = keyWidth
			used += keyWidth
			button.TextSize = math.clamp(rowHeight - 10, 12, 22)
		end
		local cursor = math.floor((usable - used) / 2)
		for index, button in buttons do
			button.Position = UDim2.fromOffset(cursor, 0)
			button.Size = UDim2.fromOffset(widths[index], rowHeight)
			cursor += widths[index] + gap
		end
	end

	local jumpSuppressed = false
	local watchedJumps: {[GuiObject]: boolean} = {}

	local function touchJumpButtons(): {GuiObject}
		local buttons = {}
		local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
		if playerGui == nil then
			return buttons
		end
		local touchGui = playerGui:FindFirstChild("TouchGui")
		if touchGui == nil then
			return buttons
		end
		for _, descendant in touchGui:GetDescendants() do
			if descendant.Name == "JumpButton" and descendant:IsA("GuiObject") then
				table.insert(buttons, descendant)
			end
		end
		return buttons
	end

	local function watchJumpButton(button: GuiObject)
		if watchedJumps[button] then
			return
		end
		watchedJumps[button] = true
		button:GetPropertyChangedSignal("Visible"):Connect(function()
			if jumpSuppressed and button.Visible then
				button.Visible = false
				button.Active = false
			end
		end)
		button.Destroying:Connect(function()
			watchedJumps[button] = nil
		end)
	end

	local function syncJumpButton()
		local hide = screen.Visible and keyboard.Visible
		if not hide and not jumpSuppressed then
			return
		end
		jumpSuppressed = hide
		for _, button in touchJumpButtons() do
			watchJumpButton(button)
			button.Visible = not hide
			button.Active = not hide
		end
	end

	local function restoreJumpButton()
		jumpSuppressed = false
		for _, button in touchJumpButtons() do
			button.Visible = true
			button.Active = true
		end
	end

	local function applyLayout()
		local size = root.AbsoluteSize
		if size.X < 50 or size.Y < 50 then
			return
		end
		local plan = TypingLayout.plan(
			size.X,
			size.Y,
			showTouchKeys(),
			constants.UI.CompactHeight,
			constants.UI.CompactWidth
		)
		local content = root:GetAttribute("ContentWidth")
		local width = size.X - plan.margin * 2
		if type(content) == "number" then
			width = math.min(width, content)
		end
		local x = math.floor((size.X - width) / 2)
		column.Position = UDim2.fromOffset(x, plan.margin)
		column.Size = UDim2.fromOffset(width, plan.blockHeight)
		timeLabel.Position = UDim2.fromOffset(0, 0)
		timeLabel.Size = UDim2.fromOffset(width, plan.timeHeight)
		timeLabel.TextSize = math.clamp(plan.timeHeight - 4, 14, 28)
		questionPanel.Position = UDim2.fromOffset(0, plan.timeHeight + plan.gap)
		questionPanel.Size = UDim2.fromOffset(width, plan.questionHeight)
		questionText.TextSize = plan.textSize
		inputLabel.Position = UDim2.fromOffset(0, plan.timeHeight + plan.gap + plan.questionHeight + plan.gap)
		inputLabel.Size = UDim2.fromOffset(width, plan.inputHeight)
		inputLabel.TextSize = plan.inputTextSize
		keyboard.Visible = plan.showKeys
		keyboard.Position = UDim2.fromOffset(x, plan.margin + plan.blockHeight + plan.gap)
		keyboard.Size = UDim2.fromOffset(width, plan.keyBlock)
		if plan.showKeys then
			for index, buttons in rowButtons do
				placeRow(buttons, rowWeights[index], width, plan.rowHeight, plan.gap, (index - 1) * (plan.rowHeight + plan.gap))
			end
		end
		syncJumpButton()
	end

	local function syncMode()
		local id = activeMatchId()
		if id ~= trackingId then
			trackingId = id
			session = nil
			buffer = ""
			pushHardware("")
			locked = false
			lastReason = nil
			if id > 0 then
				request:FireServer()
			end
		end
		local playing = id > 0
		if playing ~= open then
			open = playing
			if open then
				bindKeys()
			else
				unbindKeys()
			end
		end
		screen.Visible = playing
		applyLayout()
		render()
	end

	local function onFeedback(message: any)
		if type(message) ~= "table" then
			return
		end
		local previous = if session ~= nil then session.issue else 0
		session, buffer = QuestionRules.applyClient(session, buffer, message, activeMatchId())
		pushHardware(buffer)
		if type(message.reason) == "string" then
			lastReason = message.reason
		end
		if message.reason == "mismatch" or session == nil or session.issue ~= previous then
			locked = false
		end
		render()
	end

	refreshKeyLabels()
	applyLayout()
	render()

	local stateFolder = ReplicatedStorage:WaitForChild("MatchState")
	local connections = {
		root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			applyLayout()
		end),
		root:GetAttributeChangedSignal("ContentWidth"):Connect(applyLayout),
		UserInputService.LastInputTypeChanged:Connect(applyLayout),
		stateFolder:GetAttributeChangedSignal("Phase"):Connect(syncMode),
		stateFolder:GetAttributeChangedSignal("MatchId"):Connect(syncMode),
		Players.LocalPlayer:GetAttributeChangedSignal("InMatch"):Connect(syncMode),
		feedback.OnClientEvent:Connect(onFeedback),
		RunService.Heartbeat:Connect(function()
			syncJumpButton()
			if screen.Visible then
				render()
			end
		end),
		Players.LocalPlayer:WaitForChild("PlayerGui").DescendantAdded:Connect(function(descendant)
			if descendant.Name == "JumpButton" and descendant:IsA("GuiObject") then
				watchJumpButton(descendant)
				if jumpSuppressed then
					descendant.Visible = false
					descendant.Active = false
				end
			end
		end),
	}
	local stopLocale = Localization.onChanged(function()
		refreshKeyLabels()
		render()
	end)
	syncMode()

	return function()
		for _, connection in connections do
			connection:Disconnect()
		end
		stopLocale()
		unbindKeys()
		restoreJumpButton()
		screen:Destroy()
	end
end

return TypingScreen

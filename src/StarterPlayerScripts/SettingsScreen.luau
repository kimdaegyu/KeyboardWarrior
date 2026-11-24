--!strict
-- Lobby settings. A language row opens a scrolling list. Apply stores the choice. Close throws away unsent edits.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local constants = require(ReplicatedStorage.Shared.IngameConstants)
local Localization = require(ReplicatedStorage.Shared.Localization)
local PracticeRules = require(ReplicatedStorage.Shared.PracticeRules)
local SettingsLayout = require(ReplicatedStorage.Shared.SettingsLayout)
local SettingsRules = require(ReplicatedStorage.Shared.SettingsRules)
local UiChrome = require(ReplicatedStorage.Shared.UiChrome)
local SettingsState = require(script.Parent.SettingsState)

local SettingsScreen = {}

local function copyChoice(choice: SettingsState.Choice): SettingsState.Choice
	return { uiLocale = choice.uiLocale, gloss = choice.gloss, typing = choice.typing }
end

function SettingsScreen.bind(root: Frame): () -> ()
	SettingsState.start()
	local languages = SettingsState.languages()

	local screen = Instance.new("Frame")
	screen.Name = "SettingsScreen"
	screen.Size = UDim2.fromScale(1, 1)
	screen.BackgroundColor3 = UiChrome.Navy
	screen.BackgroundTransparency = 1
	screen.BorderSizePixel = 0
	screen.Visible = false
	screen.Active = true
	screen.ZIndex = 3
	screen.Parent = root

	local panel = Instance.new("ScrollingFrame")
	panel.ScrollBarThickness = 4
	panel.ScrollingDirection = Enum.ScrollingDirection.Y
	panel.ClipsDescendants = true
	panel.Name = "Panel"
	panel.BackgroundColor3 = UiChrome.White
	panel.BorderSizePixel = 0
	panel.ZIndex = 4
	panel.Parent = screen
	UiChrome.paint(panel, "panel")

	local function label(name: string, color: Color3, parent: Instance): TextLabel
		local text = Instance.new("TextLabel")
		text.Name = name
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.GothamMedium
		text.TextColor3 = color
		text.TextXAlignment = Enum.TextXAlignment.Left
		text.TextYAlignment = Enum.TextYAlignment.Center
		text.TextTruncate = Enum.TextTruncate.AtEnd
		text.ZIndex = 6
		text.Parent = parent
		return text
	end

	local function valueButton(name: string): (TextButton, TextLabel, TextLabel)
		local button = Instance.new("TextButton")
		button.Name = name
		button.Text = ""
		button.AutoButtonColor = false
		button.BackgroundColor3 = UiChrome.White
		button.BackgroundTransparency = 0
		button.BorderSizePixel = 0
		button.ZIndex = 6
		button.Parent = panel
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = button
		local caption = label("Caption", UiChrome.Navy, button)
		caption.ZIndex = 7
		local extra = label("Extra", UiChrome.Navy, button)
		extra.ZIndex = 7
		extra.TextXAlignment = Enum.TextXAlignment.Right
		return button, caption, extra
	end

	local function actionButton(name: string): TextButton
		local button = Instance.new("TextButton")
		button.Name = name
		button.Font = Enum.Font.GothamMedium
		button.TextColor3 = UiChrome.Navy
		button.BackgroundColor3 = UiChrome.White
		button.BackgroundTransparency = 0
		button.AutoButtonColor = false
		button.BorderSizePixel = 0
		button.TextTruncate = Enum.TextTruncate.AtEnd
		button.ZIndex = 6
		button.Parent = panel
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = button
		return button
	end

	local titleLabel = label("Title", UiChrome.Navy, panel)
	local uiLabel = label("UiLanguage", UiChrome.Navy, panel)
	local typingLabel = label("TypingLanguage", UiChrome.Navy, panel)
	local glossLabel = label("GlossLanguage", UiChrome.Navy, panel)
	local statusLabel = label("Status", UiChrome.Navy, panel)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Center
	titleLabel.Font = Enum.Font.GothamBold
	local uiButton, uiCaption, uiArrow = valueButton("UiValue")
	local typingButton, typingCaption, typingNote = valueButton("TypingValue")
	typingNote.TextXAlignment = Enum.TextXAlignment.Left
	typingNote.TextYAlignment = Enum.TextYAlignment.Top
	local glossButton, glossCaption, glossArrow = valueButton("GlossValue")
	local applyButton = actionButton("Apply")
	local closeButton = actionButton("Close")
	local replayButton = actionButton("Replay")
	applyButton:SetAttribute("Face", "primary")

	local picker = Instance.new("Frame")
	picker.Name = "LanguageList"
	picker.Size = UDim2.fromScale(1, 1)
	picker.BackgroundColor3 = UiChrome.Navy
	picker.BackgroundTransparency = 1
	picker.BorderSizePixel = 0
	picker.Visible = false
	picker.Active = true
	picker.ZIndex = 8
	picker.Parent = screen

	local pickerPanel = Instance.new("ImageLabel")
	pickerPanel.Name = "ListPanel"
	pickerPanel.BackgroundColor3 = UiChrome.White
	pickerPanel.BorderSizePixel = 0
	pickerPanel.ZIndex = 9
	pickerPanel.Parent = picker
	UiChrome.paint(pickerPanel, "panel")

	local scroller = Instance.new("ScrollingFrame")
	scroller.Name = "Languages"
	scroller.BackgroundTransparency = 1
	scroller.BorderSizePixel = 0
	scroller.ScrollBarThickness = 6
	scroller.ScrollingDirection = Enum.ScrollingDirection.Y
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroller.CanvasSize = UDim2.new()
	scroller.ZIndex = 10
	scroller.Parent = pickerPanel
	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 4)
	listLayout.Parent = scroller
	local backButton = actionButton("Back", Color3.fromRGB(72, 48, 110))
	backButton.Parent = pickerPanel
	backButton.ZIndex = 10

	local draft = copyChoice(SettingsState.applied())
	local typingId = ""
	local dirty = false
	local shown = false
	local pickerKind: string? = nil
	local pickerButtons: {TextButton} = {}

	local function same(left: SettingsState.Choice, right: SettingsState.Choice): boolean
		return left.uiLocale == right.uiLocale and left.gloss == right.gloss
	end

	local function choicesFor(kind: string): {SettingsRules.Choice}
		if kind == "gloss" then
			return SettingsRules.glossChoices(languages)
		end
		if kind == "typing" then
			return SettingsRules.typingChoices(languages, false)
		end
		return SettingsRules.uiChoices(languages)
	end

	local function choiceName(id: string, nativeName: string): string
		if id == "auto" then
			return Localization.getText("Settings.Auto")
		end
		if id == "off" then
			return Localization.getText("Settings.GlossOff")
		end
		return nativeName
	end

	local function selectedId(kind: string): string
		if kind == "gloss" then
			return draft.gloss
		end
		if kind == "typing" then
			return typingId
		end
		return draft.uiLocale
	end

	local function currentName(kind: string): string
		local selected = selectedId(kind)
		for _, choice in choicesFor(kind) do
			if choice.id == selected then
				return choiceName(choice.id, choice.nativeName)
			end
		end
		if kind == "gloss" then
			return Localization.getText("Settings.GlossOff")
		end
		if kind == "typing" then
			return ""
		end
		return Localization.getText("Settings.Auto")
	end

	local function clearList()
		for _, button in pickerButtons do
			button:Destroy()
		end
		table.clear(pickerButtons)
	end

	local function closeList()
		pickerKind = nil
		panel.Visible = true
		picker.Visible = false
		clearList()
	end

	local function viewport(): (number, number, number)
		local size = root.AbsoluteSize
		local content = root:GetAttribute("ContentWidth")
		local width = size.X
		if type(content) == "number" then
			width = math.min(width, content)
		end
		return size.X, size.Y, width
	end

	local function layoutList()
		local kind = pickerKind
		if kind == nil or not picker.Visible then
			return
		end
		local sizeX, sizeY, width = viewport()
		if sizeX < 50 or sizeY < 50 then
			return
		end
		local choices = choicesFor(kind)
		local plan = SettingsLayout.listPlan(width, sizeY - 16, #choices, constants.UI.CompactHeight, constants.UI.CompactWidth)
		local origin = math.floor((sizeX - width) / 2)
		local x = origin + math.floor((width - plan.panelWidth) / 2)
		pickerPanel.Position = UDim2.fromOffset(x, plan.margin)
		pickerPanel.Size = UDim2.fromOffset(plan.panelWidth, plan.listHeight + plan.gap + plan.back + 16)

		scroller.Position = UDim2.fromOffset(8, 8)
		scroller.Size = UDim2.fromOffset(plan.panelWidth - 16, plan.listHeight)
		listLayout.Padding = UDim.new(0, plan.gap)
		for _, button in pickerButtons do
			button.Size = UDim2.new(1, -12, 0, plan.row)
			button.TextSize = math.clamp(plan.row - 14, 12, 18)
			local face = button:GetAttribute("Face")
			local role = if type(face) == "string" then face else "panel"
			UiChrome.paint(button, role)
			button.TextColor3 = UiChrome.ink(role)
		end
		backButton.Position = UDim2.fromOffset(8, 8 + plan.listHeight + plan.gap)
		backButton.Size = UDim2.fromOffset(math.max(0, plan.panelWidth - 16), plan.back)
		UiChrome.paint(backButton, "panel")
		backButton.TextSize = math.clamp(plan.back - 14, 12, 18)
	end

	local function refreshList()
		local kind = pickerKind
		if kind == nil then
			return
		end
		local selected = selectedId(kind)
		for _, button in pickerButtons do
			local id = button:GetAttribute("ChoiceId")
			local nativeName = button:GetAttribute("NativeName")
			local picked = type(id) == "string" and id == selected
			button:SetAttribute("Face", if picked then "selected" else "panel")
			local mark = if picked then "✓  " else ""
			local name = if type(id) == "string" then choiceName(id, if type(nativeName) == "string" then nativeName else "") else ""
			button.Text = mark .. name
		end
		backButton.Text = Localization.getText("Settings.Back")
	end

	local render: () -> ()
	local applyLayout: () -> ()

	local function openList(kind: string)
		if kind == "typing" and UserInputService.TouchEnabled then
			return
		end
		if #choicesFor(kind) <= 1 then
			return
		end
		closeList()
		pickerKind = kind
		local choices = choicesFor(kind)
		for index, choice in choices do
			local button = Instance.new("TextButton")
			button.Name = "Language"
			button.LayoutOrder = index
			button.Font = Enum.Font.GothamMedium
			button.TextColor3 = UiChrome.Navy
			button.BackgroundColor3 = UiChrome.White
			button.BackgroundTransparency = 0
			button.AutoButtonColor = false
			button.BorderSizePixel = 0
			button.AutoButtonColor = true
			button.TextXAlignment = Enum.TextXAlignment.Left
			button.TextTruncate = Enum.TextTruncate.AtEnd
			button.ZIndex = 11
			button:SetAttribute("ChoiceId", choice.id)
			button:SetAttribute("NativeName", choice.nativeName)
			button.Parent = scroller
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 6)
			corner.Parent = button
			local inset = Instance.new("UIPadding")
			inset.PaddingLeft = UDim.new(0, 8)
			inset.PaddingRight = UDim.new(0, 8)
			inset.Parent = button
			local picked = choice.id
			button.Activated:Connect(function()
				if pickerKind == "gloss" then
					if draft.gloss ~= picked then
						draft.gloss = picked
						dirty = true
					end
				elseif pickerKind == "typing" then
					if typingId ~= picked then
						typingId = picked
						dirty = true
					end
				elseif draft.uiLocale ~= picked then
					draft.uiLocale = picked
					dirty = true
				end
				closeList()
				render()
				applyLayout()
			end)
			table.insert(pickerButtons, button)
		end
		panel.Visible = false
		picker.Visible = true
		scroller.CanvasPosition = Vector2.zero
		refreshList()
		layoutList()
	end

	function render()
		local state = SettingsState.saveState()
		local typingChoices = choicesFor("typing")
		if typingId == "" and typingChoices[1] ~= nil then
			typingId = typingChoices[1].id
		end
		titleLabel.Text = Localization.getText("Settings.Title")
		uiLabel.Text = Localization.getText("Settings.UiLanguage")
		typingLabel.Text = Localization.getText("Settings.TypingLanguage")
		glossLabel.Text = Localization.getText("Settings.Gloss")
		uiCaption.Text = currentName("ui")
		uiArrow.Text = if #choicesFor("ui") > 1 then "›" else ""
		typingCaption.Text = currentName("typing")
		local typingSelectable = not UserInputService.TouchEnabled and #typingChoices > 1
		local typingNoteKey = if UserInputService.TouchEnabled then "Settings.TypingMobile" else "Settings.TypingNote"
		typingNote.Text = if typingSelectable then "›" else Localization.getText(typingNoteKey)
		typingNote.TextXAlignment = if typingSelectable then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left
		typingNote.Visible = true
		typingButton.Active = typingSelectable
		glossCaption.Text = currentName("gloss")
		glossArrow.Text = if #choicesFor("gloss") > 1 then "›" else ""
		uiButton.Active = #choicesFor("ui") > 1
		glossButton.Active = #choicesFor("gloss") > 1
		applyButton.Text = Localization.getText("Settings.Apply")
		closeButton.Text = Localization.getText("Settings.Close")
		replayButton.Text = Localization.getText("Tutorial.Replay")
		local statusKey: string? = nil
		if state == "saving" then
			statusKey = "Settings.Saving"
		elseif state == "failed" then
			statusKey = "Settings.SaveFailed"
		elseif state == "unavailable" then
			statusKey = "Settings.Unavailable"
		elseif state == "saved" and not dirty then
			statusKey = "Settings.Saved"
		end
		statusLabel.Text = if statusKey ~= nil then Localization.getText(statusKey) else ""
		local canApply = state ~= "saving" and state ~= "loading"
		applyButton.Active = canApply
		applyButton.AutoButtonColor = canApply
		refreshList()
	end

	function applyLayout()
		if not screen.Visible then
			return
		end
		local sizeX, sizeY, width = viewport()
		if sizeX < 50 or sizeY < 50 then
			return
		end
		local plan = SettingsLayout.plan(width, math.max(1, sizeY - 16), constants.UI.CompactHeight, constants.UI.CompactWidth)
		local origin = math.floor((sizeX - width) / 2)
		local x = origin + math.floor((width - plan.panelWidth) / 2)
		local body = SettingsLayout.usedHeight(plan) - plan.margin * 2 + 16
		local height = math.min(body, sizeY - 12)
		panel.Position = UDim2.fromOffset(x, math.floor((sizeY - height) / 2))
		panel.Size = UDim2.fromOffset(plan.panelWidth, height)
		panel.CanvasSize = UDim2.fromOffset(0, body)

		local inner = 14
		local rowWidth = math.max(0, plan.panelWidth - inner * 2)
		local cursorY = 8
		local function placeLabel(item: TextLabel, height: number)
			item.Position = UDim2.fromOffset(inner, cursorY)
			item.Size = UDim2.fromOffset(rowWidth, height)
			item.TextSize = math.clamp(height - 4, 12, 22)
			cursorY += height + plan.gap
		end
		local function placeRow(button: TextButton, caption: TextLabel, extra: TextLabel, height: number, note: boolean)
			button.Position = UDim2.fromOffset(inner, cursorY)
			button.Size = UDim2.fromOffset(rowWidth, height)
			UiChrome.paint(button, "panel")
			if note then
				caption.Position = UDim2.fromOffset(8, 1)
				caption.Size = UDim2.new(1, -16, 0, math.floor(height * 0.5))
				caption.TextSize = math.clamp(math.floor(height * 0.42), 12, 18)
				extra.Position = UDim2.fromOffset(8, math.floor(height * 0.48))
				extra.Size = UDim2.new(1, -16, 0, math.floor(height * 0.48))
				extra.TextSize = math.clamp(math.floor(height * 0.34), 10, 14)
			else
				caption.Position = UDim2.fromOffset(8, 0)
				caption.Size = UDim2.new(1, -36, 1, 0)
				caption.TextSize = math.clamp(height - 14, 12, 18)
				extra.Position = UDim2.new(1, -28, 0, 0)
				extra.Size = UDim2.fromOffset(20, height)
				extra.TextSize = math.clamp(height - 12, 14, 22)
			end
			cursorY += height + plan.gap
		end
		local function placeActions(buttons: {TextButton}, height: number)
			local gap = plan.gap
			local buttonWidth = math.floor((rowWidth - gap) / 2)
			local cursor = inner
			for _, button in buttons do
				button.Position = UDim2.fromOffset(cursor, cursorY)
				button.Size = UDim2.fromOffset(buttonWidth, height)
				button.TextSize = math.clamp(height - 14, 12, 18)
				local face = button:GetAttribute("Face")
				local role = if type(face) == "string" then face else "panel"
				UiChrome.paint(button, role)
				button.TextColor3 = UiChrome.ink(role)
				cursor += buttonWidth + gap
			end
		end
		titleLabel.TextSize = math.clamp(plan.title - 2, 14, 28)
		placeLabel(titleLabel, plan.title)
		placeLabel(uiLabel, plan.label)
		placeRow(uiButton, uiCaption, uiArrow, plan.row, false)
		placeLabel(typingLabel, plan.label)
		placeRow(typingButton, typingCaption, typingNote, plan.row, not typingButton.Active)
		placeLabel(glossLabel, plan.label)
		placeRow(glossButton, glossCaption, glossArrow, plan.row, false)
		replayButton.Position = UDim2.fromOffset(inner, cursorY)
		replayButton.Size = UDim2.fromOffset(rowWidth, plan.row)
		UiChrome.paint(replayButton, "panel")
		replayButton.TextSize = math.clamp(plan.row - 14, 12, 18)
		cursorY += plan.row + plan.gap
		placeLabel(statusLabel, plan.status)
		placeActions({ applyButton, closeButton }, plan.row)
		layoutList()
	end

	local function sync()
		local folder = ReplicatedStorage:FindFirstChild("MatchState")
		local phaseName = if folder ~= nil then folder:GetAttribute("Phase") else nil
		local phase = if type(phaseName) == "string" then phaseName else ""
		local inMatch = Players.LocalPlayer:GetAttribute("InMatch") == true
		local open = root:GetAttribute("SettingsOpen") == true
		if open and PracticeRules.blockedByMatch(inMatch, phase) then
			closeList()
			draft = copyChoice(SettingsState.applied())
			dirty = false
			shown = false
			screen.Visible = false
			root:SetAttribute("SettingsOpen", false)
			return
		end
		if open and not shown then
			draft = copyChoice(SettingsState.applied())
			typingId = draft.typing
			dirty = false
			shown = true
			closeList()
		end
		if not open then
			closeList()
			draft = copyChoice(SettingsState.applied())
			dirty = false
			shown = false
		end
		screen.Visible = open
		if open then
			render()
			applyLayout()
		end
	end

	uiButton.Activated:Connect(function()
		openList("ui")
	end)
	typingButton.Activated:Connect(function()
		openList("typing")
	end)
	glossButton.Activated:Connect(function()
		openList("gloss")
	end)
	backButton.Activated:Connect(function()
		closeList()
		render()
		applyLayout()
	end)
	applyButton.Activated:Connect(function()
		local state = SettingsState.saveState()
		if state == "saving" or state == "loading" then
			return
		end
		SettingsState.apply(draft.uiLocale, draft.gloss, typingId)
		render()
	end)
	closeButton.Activated:Connect(function()
		root:SetAttribute("SettingsOpen", false)
	end)
	replayButton.Activated:Connect(function()
		root:SetAttribute("TutorialReplay", true)
		root:SetAttribute("TutorialOpen", true)
	end)

	local stateFolder = ReplicatedStorage:WaitForChild("MatchState")
	local connections = {
		root:GetAttributeChangedSignal("SettingsOpen"):Connect(sync),
		root:GetAttributeChangedSignal("ContentWidth"):Connect(applyLayout),
		root:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout),
		Players.LocalPlayer:GetAttributeChangedSignal("InMatch"):Connect(sync),
		stateFolder:GetAttributeChangedSignal("Phase"):Connect(sync),
	}
	local stopSettings = SettingsState.onChanged(function()
		if shown and not dirty then
			draft = copyChoice(SettingsState.applied())
			typingId = draft.typing
		elseif shown and same(draft, SettingsState.applied()) and typingId == SettingsState.applied().typing then
			dirty = false
		end
		if screen.Visible then
			render()
		end
	end)
	local stopLocale = Localization.onChanged(function()
		if screen.Visible then
			render()
		end
	end)
	sync()

	return function()
		for _, connection in connections do
			connection:Disconnect()
		end
		stopSettings()
		stopLocale()
		screen:Destroy()
	end
end

return SettingsScreen

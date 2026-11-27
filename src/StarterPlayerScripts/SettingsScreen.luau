--!strict
-- Lobby settings. A language row opens a scrolling list. The latest choice saves itself. Close sends a pending edit.

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
local SoundManager = require(script.Parent.SoundManager)


local SettingsScreen = {}

local function copyChoice(choice: SettingsState.Choice): SettingsState.Choice
	return {
		uiLocale = choice.uiLocale,
		gloss = choice.gloss,
		typing = choice.typing,
		bgmVolume = choice.bgmVolume,
		sfxVolume = choice.sfxVolume,
	}
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
	local card = surface("SettingsCard")
	local panel = Instance.new("ScrollingFrame")
	panel.ScrollBarThickness = 4
	panel.ScrollingDirection = Enum.ScrollingDirection.Y
	panel.ClipsDescendants = true
	panel.Name = "Panel"
	panel.BackgroundColor3 = UiChrome.White
	panel.BorderSizePixel = 0
	panel.ZIndex = 4
	panel.Parent = card
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundTransparency = 1

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

	local titleLabel = label("Title", UiChrome.Navy, card)
	local uiLabel = label("UiLanguage", UiChrome.Navy, panel)
	local typingLabel = label("TypingLanguage", UiChrome.Navy, panel)
	local glossLabel = label("GlossLanguage", UiChrome.Navy, panel)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Font = Enum.Font.GothamBold
	local uiButton, uiCaption, uiArrow = valueButton("UiValue")
	local typingButton, typingCaption, typingNote = valueButton("TypingValue")
	typingNote.TextXAlignment = Enum.TextXAlignment.Left
	typingNote.TextYAlignment = Enum.TextYAlignment.Top
	local glossButton, glossCaption, glossArrow = valueButton("GlossValue")
	local closeButton = UiChrome.closeButton(card)
	local replayButton = actionButton("Replay")
	local statusLabel = Instance.new("TextButton")
	statusLabel.Name = "Status"
	statusLabel.Font = Enum.Font.GothamMedium
	statusLabel.Text = ""
	statusLabel.TextColor3 = UiChrome.Navy
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.TextYAlignment = Enum.TextYAlignment.Center
	statusLabel.TextTruncate = Enum.TextTruncate.AtEnd
	statusLabel.BackgroundTransparency = 1
	statusLabel.AutoButtonColor = false
	statusLabel.BorderSizePixel = 0
	statusLabel.ZIndex = 6
	statusLabel.Parent = panel

	local tutorialLabel = label("Tutorial", UiChrome.Navy, panel)
	local gear = UiChrome.icon(card, 10063)
	local function volumeControl(name: string, bus: string)
		local title = label(name, UiChrome.Navy, panel)
		title.Font = Enum.Font.GothamBold
		local host = Instance.new("Frame")
		host.Name = name .. "Value"
		host.BackgroundTransparency = 1
		host.BorderSizePixel = 0
		host.ZIndex = 6
		host.Parent = panel
		local percent = label("Percent", UiChrome.Navy, host)
		percent.TextXAlignment = Enum.TextXAlignment.Right
		percent.ZIndex = 8
		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.Text = ""
		hit.AutoButtonColor = false
		hit.BackgroundTransparency = 1
		hit.ZIndex = 7
		hit.Parent = host
		local track = Instance.new("Frame")
		track.Name = "Track"
		track.BackgroundColor3 = Color3.fromRGB(216, 227, 250)
		track.BorderSizePixel = 0
		track.Active = false
		track.ZIndex = 7
		track.Parent = hit
		local trackCorner = Instance.new("UICorner")
		trackCorner.CornerRadius = UDim.new(1, 0)
		trackCorner.Parent = track
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.BackgroundColor3 = UiChrome.Blue
		fill.BorderSizePixel = 0
		fill.Active = false
		fill.ZIndex = 8
		fill.Parent = track
		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = UDim.new(1, 0)
		fillCorner.Parent = fill
		local knob = Instance.new("Frame")
		knob.Name = "Knob"
		knob.AnchorPoint = Vector2.new(0.5, 0.5)
		knob.BackgroundColor3 = UiChrome.Blue
		knob.BorderSizePixel = 0
		knob.Active = false
		knob.ZIndex = 9
		knob.Parent = track
		local knobCorner = Instance.new("UICorner")
		knobCorner.CornerRadius = UDim.new(1, 0)
		knobCorner.Parent = knob
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.BackgroundTransparency = 1
		icon.ZIndex = 6
		icon.Parent = panel
		return {
			title = title,
			button = host,
			icon = icon,
			bus = bus,
			track = track,
			fill = fill,
			knob = knob,
			percent = percent,
			hit = hit,
		}
	end
	local bgmRow = volumeControl("Music", "bgm")
	local sfxRow = volumeControl("Effects", "sfx")
	local rows = {
		{ title = uiLabel, button = uiButton, icon = UiChrome.icon(panel, "Language") },
		{ title = glossLabel, button = glossButton, icon = UiChrome.icon(panel, "Language") },
		{ title = typingLabel, button = typingButton, icon = UiChrome.icon(panel, "Practice") },
		bgmRow,
		sfxRow,
		{ title = tutorialLabel, button = replayButton, icon = UiChrome.icon(panel, "Tutorial") },
	}
	local rules: {Frame} = {}
	for index, row in rows do
		row.title.Font = Enum.Font.GothamBold
		local rule = Instance.new("Frame")
		rule.Name = "Separator"
		rule.BackgroundColor3 = Color3.fromRGB(216, 227, 250)
		rule.BorderSizePixel = 0
		rule.Parent = panel
		rules[index] = rule
	end

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
	scroller.Active = true
	scroller.ClipsDescendants = true
	scroller.ZIndex = 10
	scroller.Parent = pickerPanel
	local listInset = Instance.new("UIPadding")
	listInset.Name = "ListInset"
	listInset.PaddingTop = UDim.new(0, 2)
	listInset.PaddingBottom = UDim.new(0, 2)
	listInset.PaddingLeft = UDim.new(0, 2)
	listInset.PaddingRight = UDim.new(0, 2)
	listInset.Parent = scroller
	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 4)
	listLayout.Parent = scroller
	local backButton = actionButton("Back")
	backButton.Parent = pickerPanel
	backButton.ZIndex = 10

	local draft = copyChoice(SettingsState.applied())
	local typingId = ""
	local dirty = false
	local shown = false
	local pickerKind: string? = nil
	local pickerButtons: {TextButton} = {}
	local drag: { bus: string, touch: InputObject?, origin: number }? = nil

	local function volumeOf(bus: string): number
		return if bus == "bgm" then draft.bgmVolume else draft.sfxVolume
	end

	local function assignVolume(bus: string, percent: number)
		if bus == "bgm" then
			if draft.bgmVolume ~= percent then
				draft.bgmVolume = percent
				dirty = true
			end
		elseif draft.sfxVolume ~= percent then
			draft.sfxVolume = percent
			dirty = true
		end
		SoundManager.setVolumes(draft.bgmVolume, draft.sfxVolume)
	end

	local function snap(alpha: number): number
		return math.clamp(math.round(math.clamp(alpha, 0, 1) * 20) * 5, 0, 100)
	end

	local function alphaFrom(hit: TextButton, x: number): number
		local width = hit.AbsoluteSize.X
		if width <= 0 then
			return 0
		end
		return (x - hit.AbsolutePosition.X) / width
	end

	local function paintVolume(row, trackWidth: number?, knobSize: number?)
		local percent = volumeOf(row.bus)
		row.percent.Text = string.format("%d%%", percent)
		row.fill.Size = UDim2.new(percent / 100, 0, 1, 0)
		local width = if trackWidth ~= nil then trackWidth else row.track.AbsoluteSize.X
		local knob = if knobSize ~= nil then knobSize else row.knob.AbsoluteSize.X
		local height = if trackWidth ~= nil then row.track.Size.Y.Offset else row.track.AbsoluteSize.Y
		if width > 0 and knob > 0 then
			local travel = math.max(0, width - knob)
			row.knob.Position = UDim2.fromOffset(knob / 2 + travel * percent / 100, height / 2)
		end
	end

	local function rowFor(bus: string)
		return if bus == "bgm" then bgmRow else sfxRow
	end

	local function beginDrag(row, input: InputObject)
		if drag ~= nil then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		drag = {
			bus = row.bus,
			touch = if input.UserInputType == Enum.UserInputType.Touch then input else nil,
			origin = volumeOf(row.bus),
		}
		assignVolume(row.bus, snap(alphaFrom(row.hit, input.Position.X)))
		paintVolume(row)
	end

	local function same(left: SettingsState.Choice, right: SettingsState.Choice): boolean
		return left.uiLocale == right.uiLocale and left.gloss == right.gloss and left.bgmVolume == right.bgmVolume and left.sfxVolume == right.sfxVolume
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

	local function currentChoice(): SettingsState.Choice
		return {
			uiLocale = draft.uiLocale,
			gloss = draft.gloss,
			typing = typingId,
			bgmVolume = draft.bgmVolume,
			sfxVolume = draft.sfxVolume,
		}
	end

	local function submitNow()
		if typingId == "" then
			local first = choicesFor("typing")[1]
			if first ~= nil then
				typingId = first.id
			end
		end
		SettingsState.queue(currentChoice())
		SettingsState.flush()
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
		card.Visible = true
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
		local top = 4
		local plan = SettingsLayout.listPlan(width, sizeY - top - 16, #choices, constants.UI.CompactHeight, constants.UI.CompactWidth)
		local origin = math.floor((sizeX - width) / 2)
		local x = origin + math.floor((width - plan.panelWidth) / 2)
		pickerPanel.Position = UDim2.fromOffset(x, top + plan.margin)
		pickerPanel.Size = UDim2.fromOffset(plan.panelWidth, plan.listHeight + plan.gap + plan.back + 16)

		scroller.Position = UDim2.fromOffset(8, 8)
		scroller.Size = UDim2.fromOffset(plan.panelWidth - 16, plan.listHeight)
		listLayout.Padding = UDim.new(0, plan.gap)
		for _, button in pickerButtons do
			button.Size = UDim2.new(1, -scroller.ScrollBarThickness, 0, plan.row)
			button.TextSize = math.clamp(plan.row - 14, 12, 18)
			local face = button:GetAttribute("Face")
			local role = if type(face) == "string" then face else "panel"
			UiChrome.paint(button, role)
			button.TextColor3 = UiChrome.ink(role)
			for _, child in button:GetChildren() do
				if child:IsA("UIStroke") then
					child.Color = Color3.fromRGB(70, 92, 122)
					child.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
					child.Thickness = 1
				end
			end
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
				SettingsState.queue(currentChoice())
				render()
				applyLayout()
			end)
			table.insert(pickerButtons, button)
		end
		card.Visible = false
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
		uiLabel.Text = Localization.getText("Settings.GameLanguage")
		typingLabel.Text = Localization.getText(if UserInputService.TouchEnabled then "Settings.MobileInput" else "Settings.TypingLanguage")
		glossLabel.Text = Localization.getText("Settings.TranslationLanguage")
		uiCaption.Text = currentName("ui")
		uiArrow.Text = if #choicesFor("ui") > 1 then "›" else ""
		local mobile = UserInputService.TouchEnabled
		local typingSelectable = not mobile and #typingChoices > 1
		typingCaption.Text = if mobile then "English (QWERTY)" else currentName("typing")
		typingNote.Text = "▾"
		typingNote.Visible = typingSelectable
		typingNote.TextXAlignment = Enum.TextXAlignment.Center
		typingNote.TextYAlignment = Enum.TextYAlignment.Center
		typingButton.Active = typingSelectable
		glossCaption.Text = currentName("gloss")
		glossArrow.Text = if #choicesFor("gloss") > 1 then "›" else ""
		uiButton.Active = #choicesFor("ui") > 1
		glossButton.Active = #choicesFor("gloss") > 1
		bgmRow.title.Text = Localization.getText("Settings.MusicVolume")
		sfxRow.title.Text = Localization.getText("Settings.SoundEffectsVolume")
		paintVolume(bgmRow)
		paintVolume(sfxRow)
		tutorialLabel.Text = Localization.getText("Settings.TutorialLabel")
		replayButton.Text = Localization.getText("Settings.Replay")
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
		statusLabel.Active = state == "failed" or state == "unavailable"
		refreshList()
	end

	function applyLayout()
		if not screen.Visible then
			return
		end
		local sizeX, sizeY = viewport()
		if sizeX < 50 or sizeY < 50 then
			return
		end
		local plan = SettingsLayout.plan(sizeX, sizeY, constants.UI.CompactHeight, constants.UI.CompactWidth)
		local pad = plan.margin
		local function box(obj: GuiObject, x: number, y: number, w: number, h: number)
			obj.Position = UDim2.fromOffset(x, y)
			obj.Size = UDim2.fromOffset(w, h)
		end

		local body = SettingsLayout.usedHeight(plan, #rows)
		local top = 6
		local height = math.min(body, sizeY - top - 6)
		local w = plan.panelWidth
		card.Position = UDim2.fromOffset(math.floor((sizeX - w) / 2), math.max(top, math.floor((sizeY - height) / 2)))
		card.Size = UDim2.fromOffset(w, height)
		local headerHeight = pad + plan.title
		panel.Position = UDim2.fromOffset(0, headerHeight)
		panel.Size = UDim2.new(1, 0, 1, -headerHeight)
		panel.CanvasSize = UDim2.fromOffset(0, body - headerHeight)
		local mark = math.clamp(math.round(plan.row * 0.68), 18, 36)
		local right = w - pad
		local textX = pad + mark + 8
		local font = math.clamp(math.round(plan.row * 0.47), 14, 25)
		box(gear, pad, pad + (plan.title - mark) / 2, mark, mark)
		box(titleLabel, textX, pad, right - textX - plan.row, plan.title)
		titleLabel.TextSize = math.clamp(math.round(plan.title * 0.72), 19, 40)
		for index, row in rows do
			local y = (index - 1) * plan.stride
			local volume = row.bus ~= nil
			local bw = if volume then math.floor((w - 2 * pad) * 0.58) else math.min(math.floor((w - 2 * pad) * 0.48), if index == 3 then plan.row * 4.9 else math.max(118, plan.row * 3.4))
			local bx = right - bw
			box(row.icon, pad, y + (plan.stride - mark) / 2, mark, mark)
			box(row.title, textX, y, bx - textX - 6, plan.stride)
			row.title.TextSize = font
			box(row.button, bx, y + (plan.stride - plan.row) / 2, bw, plan.row)
			if volume then
				local percentWidth = math.max(58, math.round(font * 3.4))
				row.percent.Position = UDim2.new(1, -percentWidth, 0, 0)
				row.percent.Size = UDim2.fromOffset(percentWidth, plan.row)
				row.percent.TextSize = font
				local trackWidth = math.max(0, bw - percentWidth - 8)
				row.hit.Position = UDim2.fromOffset(0, 0)
				row.hit.Size = UDim2.fromOffset(trackWidth, plan.row)
				local trackHeight = math.max(8, math.floor(plan.row * 0.28))
				row.track.Position = UDim2.fromOffset(0, math.floor((plan.row - trackHeight) / 2))
				row.track.Size = UDim2.fromOffset(trackWidth, trackHeight)
				local knobSize = math.max(trackHeight + 6, math.floor(plan.row * 0.46))
				row.knob.Size = UDim2.fromOffset(knobSize, knobSize)
				paintVolume(row, trackWidth, knobSize)
			else
				UiChrome.paint(row.button, "panel")
				row.button.TextSize = font
			end
			box(rules[index], pad, y + plan.stride - 1, right - pad, 1)
		end
		local function captionLayout(caption: TextLabel, arrow: TextLabel, enabled: boolean)
			local inset = if enabled then 26 else 8
			caption.Position = UDim2.fromOffset(6, 0)
			caption.Size = UDim2.new(1, -6 - inset, 1, 0)
			caption.TextXAlignment = Enum.TextXAlignment.Center
			caption.TextSize = font
			arrow.Position = UDim2.new(1, -24, 0, 0)
			arrow.Size = UDim2.new(0, 18, 1, 0)
			arrow.TextSize = font
		end
		captionLayout(uiCaption, uiArrow, uiButton.Active)
		captionLayout(glossCaption, glossArrow, glossButton.Active)
		captionLayout(typingCaption, typingNote, typingButton.Active)
		local y = #rows * plan.stride + plan.gap
		box(closeButton, right, pad, plan.title, plan.title)
		box(statusLabel, pad, y, right - pad, plan.status)
		statusLabel.TextSize = math.min(14, font)
		closeButton.TextSize = font
		UiChrome.paint(closeButton, "panel")
		layoutList()
	end

	local function sync()
		local folder = ReplicatedStorage:FindFirstChild("MatchState")
		local phaseName = if folder ~= nil then folder:GetAttribute("Phase") else nil
		local phase = if type(phaseName) == "string" then phaseName else ""
		local inMatch = Players.LocalPlayer:GetAttribute("InMatch") == true
		local open = root:GetAttribute("SettingsOpen") == true
		if open and PracticeRules.blockedByMatch(inMatch, phase, root:GetAttribute("ResultDismissed") == true) then
			closeList()
			drag = nil
			submitNow()
			shown = false
			screen.Visible = false
			root:SetAttribute("SettingsOpen", false)
			return
		end
		if open and not shown then
			panel.CanvasPosition = Vector2.zero
			local held = SettingsState.pending()
			draft = copyChoice(if held ~= nil then held else SettingsState.applied())
			typingId = draft.typing
			dirty = held ~= nil
			shown = true
			closeList()
		end
		if not open then
			if shown then
				submitNow()
			end
			closeList()
			drag = nil
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
	statusLabel.Activated:Connect(function()
		SettingsState.retry()
	end)
	closeButton.Activated:Connect(function()
		root:SetAttribute("SettingsOpen", false)
	end)
	replayButton.Activated:Connect(function()
		root:SetAttribute("TutorialReplay", true)
		root:SetAttribute("TutorialOpen", true)
	end)

	for _, row in { bgmRow, sfxRow } do
		row.hit.InputBegan:Connect(function(input: InputObject)
			beginDrag(row, input)
		end)
	end
	local dragChanged = UserInputService.InputChanged:Connect(function(input: InputObject)
		local active = drag
		if active == nil then
			return
		end
		local fromTouch = active.touch ~= nil and input == active.touch
		local fromMouse = active.touch == nil and input.UserInputType == Enum.UserInputType.MouseMovement
		if not fromTouch and not fromMouse then
			return
		end
		assignVolume(active.bus, snap(alphaFrom(rowFor(active.bus).hit, input.Position.X)))
		paintVolume(rowFor(active.bus))
	end)
	local dragEnded = UserInputService.InputEnded:Connect(function(input: InputObject)
		local active = drag
		if active == nil then
			return
		end
		local fromTouch = active.touch ~= nil and input == active.touch
		local fromMouse = active.touch == nil and input.UserInputType == Enum.UserInputType.MouseButton1
		if not fromTouch and not fromMouse then
			return
		end
		drag = nil
		if active.bus == "sfx" and volumeOf(active.bus) ~= active.origin then
			SoundManager.play("UIConfirm")
		end
		SettingsState.queue(currentChoice())
	end)
	local stateFolder = ReplicatedStorage:WaitForChild("MatchState")
	local connections = {
		root:GetAttributeChangedSignal("SettingsOpen"):Connect(sync),
		root:GetAttributeChangedSignal("ContentWidth"):Connect(applyLayout),
		root:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout),
		Players.LocalPlayer:GetAttributeChangedSignal("InMatch"):Connect(sync),
		stateFolder:GetAttributeChangedSignal("Phase"):Connect(sync),
		dragChanged,
		dragEnded,
	}
	local stopSettings = SettingsState.onChanged(function()
		local held = SettingsState.pending()
		if shown and drag ~= nil then
			SoundManager.setVolumes(draft.bgmVolume, draft.sfxVolume)
		elseif shown and held ~= nil then
			draft = copyChoice(held)
			typingId = draft.typing
			dirty = true
			SoundManager.setVolumes(draft.bgmVolume, draft.sfxVolume)
		elseif shown and not dirty then
			draft = copyChoice(SettingsState.applied())
			typingId = draft.typing
		elseif shown and same(draft, SettingsState.applied()) and typingId == SettingsState.applied().typing then
			dirty = false
		elseif shown and dirty then
			SoundManager.setVolumes(draft.bgmVolume, draft.sfxVolume)
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

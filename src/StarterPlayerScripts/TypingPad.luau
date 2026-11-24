--!strict
-- Shared keyboard for the match and practice screens.
-- One owner edits the draft. Touch display never focuses a text box, so the OS keyboard stays closed.
-- A physical key still types on a touch device. The text box is the English PC path for ordinary letters.
-- While typing, I and O are released from the camera. A focused English field reads them like any other letter.
-- If that field does not change, the key state inserts the letter once.
-- One physical press is one character even when both routes report it. The next press counts after release.
-- Korean is assembled from those keys in the game, because the OS syllable is missing until Space.
-- Chat, the Roblox menu, another text box, and a blurred window take ownership.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local HangulInput = require(ReplicatedStorage.Shared.HangulInput)
local InputPress = require(ReplicatedStorage.Shared.InputPress)
local Localization = require(ReplicatedStorage.Shared.Localization)
local QuestionRules = require(ReplicatedStorage.Shared.QuestionRules)
local UiChrome = require(ReplicatedStorage.Shared.UiChrome)

local KEY_PRIORITY = 10000
local typingOwners = 0
local cameraWasEnabled = false

local function cameraInput(): any
	local player = Players.LocalPlayer
	local scripts = if player ~= nil then player:FindFirstChild("PlayerScripts") else nil
	local playerModule = if scripts ~= nil then scripts:FindFirstChild("PlayerModule") else nil
	local cameraModule = if playerModule ~= nil then playerModule:FindFirstChild("CameraModule") else nil
	local input = if cameraModule ~= nil then cameraModule:FindFirstChild("CameraInput") else nil
	if input == nil or not input:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(require, input)
	if ok and type(result) == "table" then
		return result
	end
	return nil
end

-- I and O zoom the camera. While someone is typing, that binding is removed so the
-- field receives them the same way it receives every other letter.
local function silenceCameraKeys(typing: boolean)
	local input = cameraInput()
	if typing then
		ContextActionService:UnbindAction("RbxCameraKeypress")
		if input ~= nil and type(input.setInputEnabled) == "function" and type(input.getInputEnabled) == "function" and input.getInputEnabled() then
			cameraWasEnabled = true
			input.setInputEnabled(false)
		end
		return
	end
	if cameraWasEnabled and input ~= nil and type(input.setInputEnabled) == "function" then
		cameraWasEnabled = false
		input.setInputEnabled(true)
	end
end

local function setTypingOwner(active: boolean)
	if active then
		typingOwners += 1
	else
		typingOwners = math.max(0, typingOwners - 1)
	end
	silenceCameraKeys(typingOwners > 0)
end

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

local claims: {[string]: boolean} = {}
local controlClaims: {[string]: boolean} = {}
local controlsReady = false

local function playerControls(): any
	local scripts = Players.LocalPlayer:FindFirstChild("PlayerScripts")
	if scripts == nil then
		return nil
	end
	local module = scripts:FindFirstChild("PlayerModule")
	if module == nil or not module:IsA("ModuleScript") then
		return nil
	end
	local okModule, playerModule = pcall(require, module)
	if not okModule or typeof(playerModule) ~= "table" then
		return nil
	end
	local getControls = (playerModule :: any).GetControls
	if type(getControls) ~= "function" then
		return nil
	end
	local okControls, result = pcall(function()
		return getControls(playerModule)
	end)
	if okControls then
		return result
	end
	return nil
end

local function setControlClaim(name: string, on: boolean)
	if on then
		controlClaims[name] = true
	else
		controlClaims[name] = nil
	end
	local controls = playerControls()
	if controls == nil then
		controlsReady = false
		return
	end
	controlsReady = true
	local anyClaim = false
	for _ in controlClaims do
		anyClaim = true
		break
	end
	if anyClaim then
		pcall(function()
			controls:Disable()
		end)
	else
		pcall(function()
			controls:Enable()
		end)
	end
end

local function jumpButtons(): {GuiObject}
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

local function jumpClaimed(): boolean
	for _, claimed in claims do
		if claimed then
			return true
		end
	end
	return false
end

local jumpWasHidden = false

local function applyJump()
	local hide = jumpClaimed()
	if hide then
		for _, button in jumpButtons() do
			button.Visible = false
			button.Active = false
		end
	elseif jumpWasHidden then
		for _, button in jumpButtons() do
			button.Visible = true
			button.Active = true
		end
	end
	jumpWasHidden = hide
end

local function makeButton(parent: Frame, name: string, text: string, role: string): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = text
	button.Font = Enum.Font.GothamMedium
	button.TextColor3 = UiChrome.ink(role)
	button.BackgroundColor3 = if role == "primary" then UiChrome.Yellow else UiChrome.White
	button.BackgroundTransparency = 0
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.TextTruncate = Enum.TextTruncate.AtEnd
	button:SetAttribute("Face", role)
	button.ZIndex = 6
	button.Parent = parent
	return button
end

export type Pad = {
	setEngaged: (self: Pad, engaged: boolean) -> (),
	setText: (self: Pad, text: string) -> (),
	setIme: (self: Pad, enabled: boolean) -> (),
	composeSettled: (self: Pad) -> (),
	settleField: (self: Pad, answer: string) -> (),
	placeInput: (self: Pad, target: GuiObject) -> (),
	inputMethod: (self: Pad) -> string,
	layout: (self: Pad, position: UDim2, width: number, rowHeight: number, gap: number, showKeys: boolean) -> (),
	syncJump: (self: Pad) -> (),
	refreshLabels: (self: Pad) -> (),
	destroy: (self: Pad) -> (),
}

local TypingPad = {}

function TypingPad.mount(parent: GuiObject, actionName: string, onDraft: (string) -> (), onEnter: () -> ()): Pad
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
	hardware.Parent = parent

	local keyboard = Instance.new("Frame")
	keyboard.Name = "Keyboard"
	keyboard.BackgroundTransparency = 1
	keyboard.Visible = false
	keyboard.ZIndex = 5
	keyboard.Parent = parent

	local mirroring = false
	local engaged = false
	local ime = false
	local compose = QuestionRules.composeIdle()
	local hold = false
	local sawKeyboard = false
	local sawTouch = false
	local sealed = ""
	local syllable = HangulInput.begin()
	local strokes = InputPress.beginState()
	local heldCameraKey: {[Enum.KeyCode]: boolean} = {}
	local mirrorSeen = ""
	local applyHangul: (Enum.KeyCode) -> ()
	local keysBound = false
	local alive = true
	local mirror = ""
	local resumeToken = 0
	local watched: {[GuiObject]: boolean} = {}

	local pad = {} :: Pad

	function pad:setText(text: string)
		mirror = text
		if hardware.Text == text then
			return
		end
		if ime and hardware:IsFocused() and text ~= "" then
			local shown = QuestionRules.fieldAnswer(hardware.Text, hardware.CursorPosition, hardware.ContentText)
			if shown == text or string.sub(shown, 1, #text) == text then
				return
			end
		end
		mirroring = true
		hardware.Text = text
		mirroring = false
	end

	local function shouldYield(): boolean
		if not UserInputService.WindowFocused then
			return true
		end
		if GuiService.MenuIsOpen then
			return true
		end
		local focused = UserInputService:GetFocusedTextBox()
		return focused ~= nil and focused ~= hardware
	end

	local function caretAtEnd(text: string): number
		local count = utf8.len(text)
		if count == nil then
			return 1
		end
		return count + 1
	end

	local function applyInputChrome()
		hardware.Parent = parent
		hardware.Position = UDim2.fromOffset(-40, -40)
		hardware.Size = UDim2.fromOffset(1, 1)
		hardware.TextTransparency = 1
		hardware.BackgroundTransparency = 1
		hardware.TextSize = 1
		hardware.PlaceholderText = ""
		hardware.ZIndex = 1
	end

	local function captureHardware()
		if UserInputService.TouchEnabled then
			return
		end
		if not engaged or not alive or shouldYield() or hardware:IsFocused() then
			return
		end
		hardware:CaptureFocus()
		local caret = caretAtEnd(hardware.Text)
		hardware.CursorPosition = caret
		hardware.SelectionStart = caret
	end

	local function releaseHardware()
		if hardware.IsFocused then
			hardware:ReleaseFocus()
		end
	end

	local function insertText(extra: string)
		onDraft(mirror .. extra)
	end

	local function eraseText()
		local count = utf8.len(mirror)
		if count == nil or count <= 0 then
			onDraft("")
			return
		end
		local offset = utf8.offset(mirror, count)
		if offset == nil or offset <= 1 then
			onDraft("")
			return
		end
		onDraft(string.sub(mirror, 1, offset - 1))
	end

	local boundNames: {string} = {}

	local function markKeyboard()
		sawKeyboard = true
	end

	local function markTouch()
		sawTouch = true
	end

	local function applyKey(key: Enum.KeyCode)
		markKeyboard()
		if ime then
			applyHangul(key)
			return
		end
		local edits = key ~= Enum.KeyCode.Space and key ~= Enum.KeyCode.Return and key ~= Enum.KeyCode.KeypadEnter
		if hold and not edits then
			return
		end
		if hold then
			hold = false
		end
		if key == Enum.KeyCode.Backspace then
			eraseText()
		elseif key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter then
			onEnter()
		elseif key == Enum.KeyCode.Space then
			insertText(" ")
		else
			local char = KEY_CHARS[key]
			if char == nil then
				return
			end
			local upper = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
				or UserInputService:IsKeyDown(Enum.KeyCode.CapsLock)
			insertText(if upper then string.upper(char) else char)
		end
	end

	-- The camera binds I and O for zoom. They stay above that binding and are sunk while typing.
	local function keyPriority(key: Enum.KeyCode): number
		if key == Enum.KeyCode.O or key == Enum.KeyCode.I then
			return KEY_PRIORITY + 100000
		end
		return KEY_PRIORITY
	end

	local function keyToken(key: Enum.KeyCode): string?
		if key == Enum.KeyCode.Space then
			return "space"
		end
		if key == Enum.KeyCode.Backspace then
			return "backspace"
		end
		if key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter then
			return "return"
		end
		return KEY_CHARS[key]
	end

	local function consume(route: InputPress.Route, phase: InputPress.Phase, key: Enum.KeyCode, gameProcessed: boolean, sampled: boolean): (InputPress.Decision, InputPress.Gate)
		local token = keyToken(key) or ""
		local sample: InputPress.Gate = {
			engaged = engaged,
			alive = alive,
			yield = shouldYield(),
			ime = ime,
			touch = UserInputService.TouchEnabled,
			focused = hardware:IsFocused(),
			gameProcessed = gameProcessed,
			route = route,
			phase = phase,
			key = token,
		}
		local down = UserInputService:IsKeyDown(key)
		local decision: InputPress.Decision = if token == ""
			then "ignored"
			elseif sampled then InputPress.sample(strokes, sample, down)
			else InputPress.event(strokes, sample, down)
		if decision == "textbox" and InputPress.releasesHold(decision, token) then
			hold = false
		elseif decision == "apply" then
			applyKey(key)
		end
		return decision, sample
	end

	local function deliverKey(route: InputPress.Route, phase: InputPress.Phase, key: Enum.KeyCode, gameProcessed: boolean): (InputPress.Decision, InputPress.Gate)
		return consume(route, phase, key, gameProcessed, false)
	end

	local function unbindAction()
		if keysBound then
			keysBound = false
			for _, name in boundNames do
				ContextActionService:UnbindAction(name)
			end
			table.clear(boundNames)
		end
	end

	local function bindKeys()
		if keysBound or not engaged or not alive or shouldYield() then
			return
		end
		keysBound = true
		local function bindOne(key: Enum.KeyCode)
			local name = actionName .. "_" .. key.Name
			table.insert(boundNames, name)
			ContextActionService:BindActionAtPriority(name, function(_name: string, state: Enum.UserInputState, input: InputObject)
				local phase: InputPress.Phase? = if state == Enum.UserInputState.Begin
					then "begin"
					elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then "end"
					else nil
				if phase == nil then
					return Enum.ContextActionResult.Pass
				end
				local decision, sample = deliverKey("cas", phase, input.KeyCode, false)
				local action = InputPress.casAction(decision, sample)
				return if action == "sink" then Enum.ContextActionResult.Sink else Enum.ContextActionResult.Pass
			end, false, keyPriority(key), key)
		end
		for key in KEY_CHARS do
			bindOne(key)
		end
		bindOne(Enum.KeyCode.Space)
		bindOne(Enum.KeyCode.Backspace)
		bindOne(Enum.KeyCode.Return)
		bindOne(Enum.KeyCode.KeypadEnter)
	end

	local function applyOwnership()
		if not alive then
			return
		end
		if not engaged then
			unbindAction()
			releaseHardware()
			setControlClaim(actionName, false)
			return
		end
		setControlClaim(actionName, true)
		if shouldYield() then
			unbindAction()
			releaseHardware()
			return
		end
		if ime and not UserInputService.TouchEnabled then
			releaseHardware()
			bindKeys()
			return
		end
		if UserInputService.TouchEnabled then
			releaseHardware()
			bindKeys()
			return
		end
		if hardware:IsFocused() then
			bindKeys()
			return
		end
		bindKeys()
		captureHardware()
	end

	local function scheduleResume()
		resumeToken += 1
		local token = resumeToken
		task.defer(function()
			if token ~= resumeToken or not alive then
				return
			end
			applyOwnership()
		end)
	end

	local function yieldNow()
		resumeToken += 1
		InputPress.holdQuiet(strokes)
		unbindAction()
		releaseHardware()
	end

	local function readField(): string
		local content = hardware.ContentText
		if content == hardware.PlaceholderText then
			content = hardware.Text
		end
		return QuestionRules.fieldAnswer(hardware.Text, hardware.CursorPosition, content)
	end

	local function clearField()
		if hardware.Text == "" then
			return
		end
		mirroring = true
		hardware.Text = ""
		mirroring = false
	end

	local function publishDraft()
		if mirroring or not alive or not engaged then
			return
		end
		if not hardware:IsFocused() then
			if hold then
				clearField()
			end
			return
		end
		local text = if ime then HangulInput.text(syllable) else readField()
		local nextState = QuestionRules.composeEvent(compose, "text", text, nil)
		compose = nextState
		if hold then
			clearField()
			return
		end
		if sealed ~= "" and QuestionRules.revives(text, sealed) then
			if hardware.Text == "" or QuestionRules.revives(hardware.Text, sealed) then
				clearField()
			end
			return
		end
		if sealed ~= "" and text ~= "" then
			sealed = ""
		end
		markKeyboard()
		onDraft(text)
	end

	function pad:composeSettled()
		compose = QuestionRules.composeIdle()
	end

	function pad:settleField(answer: string)
		hold = true
		sealed = answer
		sawKeyboard = false
		sawTouch = false
		HangulInput.clear(syllable)
		compose = QuestionRules.composeIdle()
	end

	function pad:inputMethod(): string
		if sawKeyboard and sawTouch then
			return "mixed"
		end
		if sawKeyboard then
			return "keyboard"
		end
		if sawTouch then
			return "touch"
		end
		return "unknown"
	end

	local function publishHangul()
		if not alive or not engaged or hold then
			return
		end
		onDraft(HangulInput.text(syllable))
	end

	applyHangul = function(key: Enum.KeyCode)
		local releases = key ~= Enum.KeyCode.Return and key ~= Enum.KeyCode.KeypadEnter and key ~= Enum.KeyCode.Space
		if hold and releases then
			hold = false
			HangulInput.clear(syllable)
		end
		if key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter then
			if hold then
				return
			end
			local nextState = QuestionRules.composeEvent(compose, "enter", HangulInput.text(syllable), true)
			compose = nextState
			publishHangul()
			onEnter()
			return
		end
		if hold then
			return
		end
		if key == Enum.KeyCode.Space then
			HangulInput.space(syllable)
		elseif key == Enum.KeyCode.Backspace then
			HangulInput.backspace(syllable)
		else
			local ch = KEY_CHARS[key]
			if ch == nil then
				return
			end
			local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			if shift then
				ch = string.upper(ch)
			end
			HangulInput.key(syllable, ch)
		end
		publishHangul()
	end

	function pad:setIme(enabled: boolean)
		if enabled == ime then
			applyInputChrome()
			return
		end
		HangulInput.clear(syllable)
		compose = QuestionRules.composeIdle()
		ime = enabled
		applyInputChrome()
		if engaged then
			applyOwnership()
		end
	end

	function pad:placeInput(_target: GuiObject)
		applyInputChrome()
	end

	function pad:setEngaged(nextEngaged: boolean)
		if nextEngaged == engaged then
			if engaged and not controlsReady then
				setControlClaim(actionName, true)
			end
			self:syncJump()
			return
		end
		engaged = nextEngaged
		setTypingOwner(engaged)
		if not engaged then
			HangulInput.clear(syllable)
			compose = QuestionRules.composeIdle()
		end
		resumeToken += 1
		applyOwnership()
		self:syncJump()
	end

	hardware:GetPropertyChangedSignal("Text"):Connect(publishDraft)
	hardware:GetPropertyChangedSignal("CursorPosition"):Connect(publishDraft)
	hardware:GetPropertyChangedSignal("SelectionStart"):Connect(publishDraft)

	hardware.Focused:Connect(function()
		if UserInputService.TouchEnabled or ime then
			releaseHardware()
		end
		if alive and engaged then
			bindKeys()
		end
	end)

	hardware.FocusLost:Connect(function(enterPressed: boolean)
		InputPress.holdQuiet(strokes)
		if not engaged or UserInputService.TouchEnabled then
			return
		end
		if enterPressed and not hold then
			publishDraft()
			onEnter()
		end
		scheduleResume()
	end)

	local ownership = {
		UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
			if input.UserInputType ~= Enum.UserInputType.Keyboard then
				return
			end
			deliverKey("uis", "begin", input.KeyCode, gameProcessed)
		end),
		UserInputService.InputEnded:Connect(function(input: InputObject)
			if input.UserInputType ~= Enum.UserInputType.Keyboard then
				return
			end
			deliverKey("uis", "end", input.KeyCode, false)
			if not alive or not engaged or not ime then
				return
			end
			publishDraft()
		end),
		UserInputService.TextBoxFocused:Connect(function(box)
			if not alive or not engaged or box == hardware then
				return
			end
			yieldNow()
		end),
		UserInputService.TextBoxFocusReleased:Connect(function()
			if alive and engaged then
				scheduleResume()
			end
		end),
		UserInputService.WindowFocusReleased:Connect(function()
			if alive and engaged then
				yieldNow()
			end
		end),
		UserInputService.WindowFocused:Connect(function()
			if alive and engaged then
				scheduleResume()
			end
		end),
		GuiService.MenuOpened:Connect(function()
			if alive and engaged then
				yieldNow()
			end
		end),
		GuiService.MenuClosed:Connect(function()
			if alive and engaged then
				scheduleResume()
			end
		end),
		-- The camera binding is removed while typing. If I or O is down and the field
		-- did not already change, that letter is inserted once.
		RunService.Heartbeat:Connect(function()
			if not alive then
				return
			end
			if engaged then
				silenceCameraKeys(true)
			end
			for _, key in { Enum.KeyCode.O, Enum.KeyCode.I } do
				local down = UserInputService:IsKeyDown(key)
				local was = heldCameraKey[key] == true
				if down and not was and mirror == mirrorSeen and engaged and not shouldYield() then
					local token = keyToken(key)
					local before = mirror
					if token ~= nil and hardware:IsFocused() and not ime then
						if hold then
							hold = false
						end
						local extra = token
						if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
							or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
							or UserInputService:IsKeyDown(Enum.KeyCode.CapsLock)
						then
							extra = string.upper(token)
						end
						mirroring = true
						local text = hardware.Text .. extra
						hardware.Text = text
						local caret = caretAtEnd(text)
						hardware.CursorPosition = caret
						hardware.SelectionStart = caret
						mirroring = false
						publishDraft()
					else
						applyKey(key)
					end
					if mirror ~= before and token ~= nil then
						mirrorSeen = mirror
						InputPress.claim(strokes, token)
					end
				elseif not down and was then
					consume("cas", "end", key, false, true)
				end
				heldCameraKey[key] = down
			end
			mirrorSeen = mirror
		end),
	}

	local rowButtons: {{TextButton}} = {}
	local rowWeights: {{number}?} = {}
	for index, letters in LETTER_ROWS do
		local row = Instance.new("Frame")
		row.Name = "Letters" .. index
		row.BackgroundTransparency = 1
		row.ZIndex = 5
		row.Parent = keyboard
		local buttons = {}
		for _, letter in letters do
			local button = makeButton(row, string.upper(letter), string.upper(letter), "keycap")
			button.Activated:Connect(function()
				markTouch()
				insertText(letter)
			end)
			table.insert(buttons, button)
		end
		rowButtons[index] = buttons
	end

	local actionRow = Instance.new("Frame")
	actionRow.Name = "Actions"
	actionRow.BackgroundTransparency = 1
	actionRow.ZIndex = 5
	actionRow.Parent = keyboard
	local backspaceButton = makeButton(actionRow, "Backspace", "", "keycap")
	local spaceButton = makeButton(actionRow, "Space", "", "keycap")
	local enterButton = makeButton(actionRow, "Enter", "", "primary")
	backspaceButton.Activated:Connect(function()
		markTouch()
		eraseText()
	end)
	spaceButton.Activated:Connect(function()
		markTouch()
		insertText(" ")
	end)
	enterButton.Activated:Connect(function()
		markTouch()
		onEnter()
	end)
	rowButtons[4] = { backspaceButton, spaceButton, enterButton }
	rowWeights[4] = { 1.8, 3.2, 1.8 }

	function pad:refreshLabels()
		backspaceButton.Text = Localization.getText("Match.Backspace")
		spaceButton.Text = Localization.getText("Match.Space")
		enterButton.Text = Localization.getText("Match.Enter")
	end

	local function placeRow(buttons: {TextButton}, weights: {number}?, width: number, rowHeight: number, gap: number, y: number)
		local rowParent = buttons[1].Parent
		if rowParent ~= nil and rowParent:IsA("GuiObject") then
			rowParent.Position = UDim2.fromOffset(0, y)
			rowParent.Size = UDim2.fromOffset(width, rowHeight)
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
			local face = button:GetAttribute("Face")
			local role = if type(face) == "string" then face else "keycap"
			UiChrome.paint(button, role)
			button.TextColor3 = UiChrome.ink(role)
			cursor += widths[index] + gap
		end
	end

	function pad:layout(position: UDim2, width: number, rowHeight: number, gap: number, showKeys: boolean)
		keyboard.Visible = showKeys
		keyboard.Position = position
		keyboard.Size = UDim2.fromOffset(width, rowHeight * 4 + gap * 3)
		if showKeys then
			for index, buttons in rowButtons do
				placeRow(buttons, rowWeights[index], width, rowHeight, gap, (index - 1) * (rowHeight + gap))
			end
		end
		self:syncJump()
	end

	local function watchJump(button: GuiObject)
		if watched[button] then
			return
		end
		watched[button] = true
		button:GetPropertyChangedSignal("Visible"):Connect(function()
			if jumpClaimed() and button.Visible then
				button.Visible = false
				button.Active = false
			end
		end)
		button.Destroying:Connect(function()
			watched[button] = nil
		end)
	end

	function pad:syncJump()
		if engaged and not controlsReady then
			setControlClaim(actionName, true)
		end
		claims[actionName] = engaged and keyboard.Visible
		applyJump()
		if claims[actionName] then
			for _, button in jumpButtons() do
				watchJump(button)
			end
		end
	end

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local added = playerGui.DescendantAdded:Connect(function(descendant)
		if descendant.Name == "JumpButton" and descendant:IsA("GuiObject") and jumpClaimed() then
			watchJump(descendant)
			descendant.Visible = false
			descendant.Active = false
		end
	end)

	function pad:destroy()
		if not alive then
			return
		end
		alive = false
		resumeToken += 1
		if engaged then
			engaged = false
			setTypingOwner(false)
		end
		unbindAction()
		releaseHardware()
		setControlClaim(actionName, false)
		claims[actionName] = nil
		applyJump()
		added:Disconnect()
		for _, connection in ownership do
			connection:Disconnect()
		end
		keyboard:Destroy()
		hardware:Destroy()
	end

	pad:refreshLabels()
	return pad
end

return TypingPad

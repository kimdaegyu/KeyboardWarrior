--!strict
-- The first-join loading screen: status, fade, failure, and the input cover.
-- An empty or failed image keeps the solid background and the Typing GOD text.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local constants = require(Shared:WaitForChild("IngameConstants"))
local LoadingArt = require(Shared:WaitForChild("LoadingArt"))
local LoadingInputLock = require(Shared:WaitForChild("LoadingInputLock"))
local LoadingPolicy = require(Shared:WaitForChild("LoadingPolicy"))
local Localization = require(Shared:WaitForChild("Localization"))
local Layout = require(script.Parent.Layout)

local SCREEN_NAME = "LoadingScreen"
local SINK_ACTION = "LoadingInputSink"
local BOOTSTRAP_SINK = "LoadingBootstrapSink"
local MARBLE = Color3.fromRGB(214, 204, 188)
local INK = Color3.fromRGB(23, 41, 69)
local PAPER = Color3.fromRGB(255, 248, 236)

local LoadingPresenter = {}

local screen: ScreenGui? = nil
local statusLabel: TextLabel? = nil
local titleImage: ImageLabel? = nil
local titleText: TextLabel? = nil
local failurePanel: Frame? = nil
local retryButton: TextButton? = nil
local failureMessage: TextLabel? = nil
local failureCode: TextLabel? = nil
local phrase = LoadingPolicy.FallbackText.PlayerData
local phaseName = LoadingPolicy.Phase.PlayerData
local showGeneration = 0
local fadeStarted = false
local dotsRunning = false
local showingFailure = false
local sinkBound = false
local controlsDisabled = false
local retryConnection: RBXScriptConnection? = nil
local localeConnection: (() -> ())? = nil
local layoutConnections: { RBXScriptConnection } = {}

local function text(name: string, args: { [string]: string }?): string
	local key = LoadingPolicy.messageKey(name)
	local fallback = LoadingPolicy.FallbackText[name] or LoadingPolicy.FallbackText.Failed
	local ok, value = pcall(function()
		return Localization.getText(key, nil, args)
	end)
	if not ok or typeof(value) ~= "string" or value == "" or value == key then
		if args ~= nil and string.find(fallback, "{", 1, true) ~= nil then
			local formatted = fallback
			for token, replacement in args do
				formatted = string.gsub(formatted, "{" .. token .. "}", replacement)
			end
			return formatted
		end
		return fallback
	end
	return value
end

local function playerGui(): PlayerGui
	local player = Players.LocalPlayer
	local gui = player:FindFirstChild("PlayerGui")
	if gui ~= nil and gui:IsA("PlayerGui") then
		return gui
	end
	return player:WaitForChild("PlayerGui") :: PlayerGui
end

local function setCover(active: boolean)
	playerGui():SetAttribute("LoadingCover", active)
end

local function playerModuleControls(): any
	local scripts = Players.LocalPlayer:FindFirstChild("PlayerScripts")
	if scripts == nil then
		return nil
	end
	local moduleScript = scripts:FindFirstChild("PlayerModule")
	if moduleScript == nil or not moduleScript:IsA("ModuleScript") then
		return nil
	end
	local ok, playerModule = pcall(require, moduleScript)
	if not ok or typeof(playerModule) ~= "table" or (playerModule :: any).GetControls == nil then
		return nil
	end
	return (playerModule :: any):GetControls()
end

local function setControlsEnabled(enabled: boolean)
	local controls = playerModuleControls()
	if controls == nil then
		if not enabled then
			task.spawn(function()
				local scripts = Players.LocalPlayer:WaitForChild("PlayerScripts", 5)
				if scripts == nil or not LoadingInputLock.isLocked() then
					return
				end
				local moduleScript = scripts:FindFirstChild("PlayerModule")
				if moduleScript == nil or not moduleScript:IsA("ModuleScript") then
					return
				end
				local ok, playerModule = pcall(require, moduleScript)
				if not ok or typeof(playerModule) ~= "table" or (playerModule :: any).GetControls == nil then
					return
				end
				if not LoadingInputLock.isLocked() then
					return
				end
				local lateControls = (playerModule :: any):GetControls()
				lateControls:Disable()
				controlsDisabled = true
			end)
		end
		return
	end
	if enabled then
		controls:Enable()
		controlsDisabled = false
	else
		controls:Disable()
		controlsDisabled = true
	end
end

local function sinkAction(_name: string, _state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonStart then
		return Enum.ContextActionResult.Pass
	end
	return Enum.ContextActionResult.Sink
end

local function bindSink()
	if sinkBound then
		return
	end
	sinkBound = true
	local ok = pcall(function()
		ContextActionService:BindActionAtPriority(
			SINK_ACTION,
			sinkAction,
			false,
			Enum.ContextActionPriority.High.Value + 1000,
			Enum.UserInputType.Keyboard,
			Enum.UserInputType.MouseButton1,
			Enum.UserInputType.MouseButton2,
			Enum.UserInputType.Touch,
			Enum.KeyCode.Thumbstick1,
			Enum.KeyCode.ButtonA,
			Enum.KeyCode.ButtonB,
			Enum.KeyCode.ButtonX,
			Enum.KeyCode.ButtonY,
			Enum.KeyCode.ButtonL1,
			Enum.KeyCode.ButtonR1,
			Enum.KeyCode.DPadUp,
			Enum.KeyCode.DPadDown,
			Enum.KeyCode.DPadLeft,
			Enum.KeyCode.DPadRight
		)
	end)
	if not ok then
		sinkBound = false
	end
end

local function unbindSink()
	if sinkBound then
		sinkBound = false
		ContextActionService:UnbindAction(SINK_ACTION)
	end
	pcall(function()
		ContextActionService:UnbindAction(BOOTSTRAP_SINK)
	end)
end

local function lockInput()
	LoadingInputLock.setLocked(true)
	bindSink()
	setControlsEnabled(false)
end

local function unlockInput()
	LoadingInputLock.setLocked(false)
	unbindSink()
	if controlsDisabled then
		setControlsEnabled(true)
	end
	if retryButton ~= nil and GuiService.SelectedObject == retryButton then
		GuiService.SelectedObject = nil
	end
end

local function safeBounds(): (Vector2, Vector2)
	local gui = playerGui()
	local ui = gui:FindFirstChild("KeyboardWarriorUI")
	local root = if ui ~= nil then ui:FindFirstChild("SafeRoot") else nil
	if root ~= nil and root:IsA("GuiObject") then
		local size = root.AbsoluteSize
		if size.X >= 1 and size.Y >= 1 then
			return root.AbsolutePosition, size
		end
	end
	local camera = Workspace.CurrentCamera
	local viewport = if camera ~= nil then camera.ViewportSize else Vector2.new(1280, 720)
	local inset = GuiService:GetGuiInset()
	local topLeft = Vector2.new(math.max(8, inset.X), math.max(8, inset.Y))
	return topLeft, Vector2.new(
		math.max(0, viewport.X - topLeft.X - math.max(8, inset.X)),
		math.max(0, viewport.Y - topLeft.Y - math.max(8, inset.Y))
	)
end

local function layout()
	local current = screen
	local status = statusLabel
	if current == nil or status == nil then
		return
	end
	local origin, size = safeBounds()
	local metrics = Layout.metrics(size)
	local plate = status.Parent
	if plate ~= nil and plate:IsA("GuiObject") then
		local plateHeight = if metrics.compact then 36 else 44
		plate.AnchorPoint = Vector2.new(0.5, 1)
		plate.Position = UDim2.fromOffset(origin.X + size.X * 0.5, origin.Y + size.Y - metrics.margin)
		plate.Size = UDim2.fromOffset(math.max(160, size.X - metrics.margin * 2), plateHeight)
		status.TextSize = if metrics.compact then 16 else 20
	end
	local panel = failurePanel
	if panel ~= nil then
		local panelWidth = math.min(size.X - metrics.margin * 2, if metrics.compact then 420 else 480)
		local panelHeight = if metrics.compact then 168 else 188
		panel.AnchorPoint = Vector2.new(0.5, 1)
		panel.Position = UDim2.fromOffset(origin.X + size.X * 0.5, origin.Y + size.Y - metrics.margin)
		panel.Size = UDim2.fromOffset(panelWidth, panelHeight)
	end
	if plate ~= nil and plate:IsA("GuiObject") then
		plate.Visible = not showingFailure
	end
end

local function watchLayout(current: ScreenGui)
	for _, connection in layoutConnections do
		connection:Disconnect()
	end
	table.clear(layoutConnections)
	local function bindRoot(root: GuiObject)
		table.insert(layoutConnections, root:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout))
		table.insert(layoutConnections, root:GetPropertyChangedSignal("AbsolutePosition"):Connect(layout))
	end
	local gui = current.Parent
	local ui = if gui ~= nil then gui:FindFirstChild("KeyboardWarriorUI") else nil
	local root = if ui ~= nil then ui:FindFirstChild("SafeRoot") else nil
	if root ~= nil and root:IsA("GuiObject") then
		bindRoot(root)
	elseif gui ~= nil then
		table.insert(layoutConnections, gui.ChildAdded:Connect(function(child)
			if child.Name ~= "KeyboardWarriorUI" then
				return
			end
			local safe = child:WaitForChild("SafeRoot", 5)
			if safe ~= nil and safe:IsA("GuiObject") then
				bindRoot(safe)
			end
			layout()
		end))
	end
	local camera = Workspace.CurrentCamera
	if camera ~= nil then
		table.insert(layoutConnections, camera:GetPropertyChangedSignal("ViewportSize"):Connect(layout))
	end
	table.insert(layoutConnections, Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		local nextCamera = Workspace.CurrentCamera
		if nextCamera ~= nil then
			table.insert(layoutConnections, nextCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layout))
		end
		layout()
	end))
end

local function syncTitle()
	local image = titleImage
	local label = titleText
	if image == nil or label == nil then
		return
	end
	local showImage = LoadingPolicy.artMode(image.Image, nil, image.IsLoaded) == "image"
	image.Visible = showImage
	label.Visible = not showImage
end

local function ensureDots()
	if dotsRunning then
		return
	end
	dotsRunning = true
	task.spawn(function()
		local step = 0
		while dotsRunning do
			step += 1
			local label = statusLabel
			local current = screen
			if label ~= nil and current ~= nil and current.Enabled and not fadeStarted and not showingFailure then
				label.Text = phrase .. string.rep(".", (step % 3) + 1)
			end
			task.wait(constants.Loading.StatusDotIntervalSeconds)
		end
	end)
end

local function setPhrase(phase: string)
	phaseName = phase
	local fallbackName = if LoadingPolicy.FallbackText[phase] ~= nil then phase else "PlayerData"
	phrase = text(fallbackName)
	local label = statusLabel
	if label ~= nil and not showingFailure then
		label.Text = phrase
	end
end

local function hideFailure()
	showingFailure = false
	if failurePanel ~= nil then
		failurePanel.Visible = false
	end
	if retryConnection ~= nil then
		retryConnection:Disconnect()
		retryConnection = nil
	end
	if retryButton ~= nil and GuiService.SelectedObject == retryButton then
		GuiService.SelectedObject = nil
	end
	layout()
end

local function findNamed(parent: Instance, name: string, className: string): Instance?
	local found = parent:FindFirstChild(name)
	if found ~= nil and found.ClassName == className then
		return found
	end
	return nil
end

local function buildScreen(): ScreenGui
	local gui = playerGui()
	local found = gui:FindFirstChild(SCREEN_NAME)
	local current: ScreenGui
	if found ~= nil and found:IsA("ScreenGui") then
		current = found
	else
		current = Instance.new("ScreenGui")
		current.Name = SCREEN_NAME
		current.Parent = gui
	end
	screen = current
	current.ResetOnSpawn = false
	current.IgnoreGuiInset = true
	current.ClipToDeviceSafeArea = false
	current.DisplayOrder = 100000
	current.Enabled = true
	current.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	current:SetAttribute("PresenterOwned", true)

	local background = findNamed(current, "Background", "Frame")
	if background == nil then
		local created = Instance.new("Frame")
		created.Name = "Background"
		created.Parent = current
		background = created
	end
	background = background :: Frame
	background.BackgroundColor3 = MARBLE
	background.BorderSizePixel = 0
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundTransparency = 0

	local art = findNamed(background, "BackgroundArt", "ImageLabel")
	if art == nil then
		local created = Instance.new("ImageLabel")
		created.Name = "BackgroundArt"
		created.Parent = background
		art = created
	end
	art = art :: ImageLabel
	art.BackgroundTransparency = 1
	art.Size = UDim2.fromScale(1, 1)
	art.ScaleType = Enum.ScaleType.Crop
	art.Image = LoadingArt.backgroundUrl()

	local title = findNamed(current, "Title", "ImageLabel")
	if title == nil then
		local created = Instance.new("ImageLabel")
		created.Name = "Title"
		created.Parent = current
		title = created
	end
	title = title :: ImageLabel
	title.BackgroundTransparency = 1
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.fromScale(constants.Loading.TitleCenterX, constants.Loading.TitleCenterY)
	title.Size = UDim2.fromScale(constants.Loading.TitleWidthScale, constants.Loading.TitleHeightScale)
	title.ScaleType = Enum.ScaleType.Fit
	title.ZIndex = 3
	title.Image = LoadingArt.titleUrl()
	titleImage = title

	local heading = findNamed(current, "TitleText", "TextLabel")
	if heading == nil then
		local created = Instance.new("TextLabel")
		created.Name = "TitleText"
		created.Parent = current
		heading = created
	end
	heading = heading :: TextLabel
	heading.AutoLocalize = false
	heading.BackgroundTransparency = 1
	heading.AnchorPoint = Vector2.new(0.5, 0.5)
	heading.Position = title.Position
	heading.Size = title.Size
	heading.Font = Enum.Font.Garamond
	heading.TextScaled = true
	heading.TextColor3 = PAPER
	heading.TextStrokeColor3 = INK
	heading.TextStrokeTransparency = 0.35
	heading.Text = text("Title")
	heading.ZIndex = 3
	titleText = heading
	local limit = heading:FindFirstChild("TitleSize")
	if limit == nil then
		local created = Instance.new("UITextSizeConstraint")
		created.Name = "TitleSize"
		created.MinTextSize = 18
		created.MaxTextSize = 72
		created.Parent = heading
	end
	if title:GetAttribute("TitleWatch") ~= true then
		title:SetAttribute("TitleWatch", true)
		title:GetPropertyChangedSignal("IsLoaded"):Connect(syncTitle)
		title:GetPropertyChangedSignal("Image"):Connect(syncTitle)
	end
	syncTitle()

	local sink = findNamed(current, "InputSink", "TextButton")
	if sink == nil then
		local created = Instance.new("TextButton")
		created.Name = "InputSink"
		created.Parent = current
		sink = created
	end
	sink = sink :: TextButton
	sink.AutoLocalize = false
	sink.Size = UDim2.fromScale(1, 1)
	sink.BackgroundTransparency = 1
	sink.Text = ""
	sink.Modal = true
	sink.Active = true
	sink.Selectable = false
	sink.AutoButtonColor = false
	sink.ZIndex = 2

	local plate = findNamed(current, "StatusPlate", "Frame")
	if plate == nil then
		local created = Instance.new("Frame")
		created.Name = "StatusPlate"
		created.Parent = current
		plate = created
	end
	plate = plate :: Frame
	plate.BackgroundColor3 = INK
	plate.BackgroundTransparency = 0.28
	plate.BorderSizePixel = 0
	plate.ZIndex = 4
	local corner = plate:FindFirstChild("Corner")
	if corner == nil then
		local created = Instance.new("UICorner")
		created.Name = "Corner"
		created.CornerRadius = UDim.new(0, 8)
		created.Parent = plate
	end

	local status = findNamed(plate, "Status", "TextLabel")
	if status == nil then
		local created = Instance.new("TextLabel")
		created.Name = "Status"
		created.Parent = plate
		status = created
	end
	status = status :: TextLabel
	status.AutoLocalize = false
	status.BackgroundTransparency = 1
	status.Size = UDim2.fromScale(1, 1)
	status.Font = Enum.Font.GothamMedium
	status.TextColor3 = PAPER
	status.TextXAlignment = Enum.TextXAlignment.Center
	status.TextYAlignment = Enum.TextYAlignment.Center
	status.TextStrokeTransparency = 1
	status.ZIndex = 5
	statusLabel = status

	local panel = findNamed(current, "Failure", "Frame")
	if panel == nil then
		local created = Instance.new("Frame")
		created.Name = "Failure"
		created.Parent = current
		panel = created
	end
	panel = panel :: Frame
	panel.BackgroundColor3 = INK
	panel.BackgroundTransparency = 0.08
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Active = true
	panel.ZIndex = 8
	if panel:FindFirstChild("Corner") == nil then
		local created = Instance.new("UICorner")
		created.Name = "Corner"
		created.CornerRadius = UDim.new(0, 12)
		created.Parent = panel
	end
	failurePanel = panel

	local message = findNamed(panel, "Message", "TextLabel")
	if message == nil then
		local created = Instance.new("TextLabel")
		created.Name = "Message"
		created.Parent = panel
		message = created
	end
	message = message :: TextLabel
	message.AutoLocalize = false
	message.BackgroundTransparency = 1
	message.Position = UDim2.fromOffset(16, 16)
	message.Size = UDim2.new(1, -32, 0, 72)
	message.Font = Enum.Font.GothamMedium
	message.TextSize = 18
	message.TextColor3 = PAPER
	message.TextWrapped = true
	message.TextYAlignment = Enum.TextYAlignment.Top
	message.ZIndex = 9
	failureMessage = message

	local code = findNamed(panel, "Code", "TextLabel")
	if code == nil then
		local created = Instance.new("TextLabel")
		created.Name = "Code"
		created.Parent = panel
		code = created
	end
	code = code :: TextLabel
	code.AutoLocalize = false
	code.BackgroundTransparency = 1
	code.Position = UDim2.fromOffset(16, 92)
	code.Size = UDim2.new(1, -32, 0, 24)
	code.Font = Enum.Font.Gotham
	code.TextSize = 14
	code.TextColor3 = Color3.fromRGB(214, 206, 196)
	code.ZIndex = 9
	failureCode = code

	local retry = findNamed(panel, "Retry", "TextButton")
	if retry == nil then
		local created = Instance.new("TextButton")
		created.Name = "Retry"
		created.Parent = panel
		retry = created
	end
	retry = retry :: TextButton
	retry.AutoLocalize = false
	retry.AnchorPoint = Vector2.new(0.5, 1)
	retry.Position = UDim2.new(0.5, 0, 1, -16)
	retry.Size = UDim2.new(1, -32, 0, 40)
	retry.BackgroundColor3 = Color3.fromRGB(244, 196, 67)
	retry.TextColor3 = INK
	retry.Font = Enum.Font.GothamBold
	retry.TextSize = 16
	retry.AutoButtonColor = true
	retry.ZIndex = 9
	if retry:FindFirstChild("Corner") == nil then
		local created = Instance.new("UICorner")
		created.Name = "Corner"
		created.CornerRadius = UDim.new(0, 8)
		created.Parent = retry
	end
	retryButton = retry

	watchLayout(current)
	layout()
	ensureDots()
	return current
end

function LoadingPresenter.show(phase: string)
	showGeneration += 1
	fadeStarted = false
	showingFailure = false
	local current = buildScreen()
	current.Enabled = true
	setCover(true)
	hideFailure()
	setPhrase(phase)
	lockInput()
	layout()
	syncTitle()
end

function LoadingPresenter.setPhase(phase: string)
	if screen == nil or not screen.Enabled then
		LoadingPresenter.show(phase)
		return
	end
	setPhrase(phase)
end

function LoadingPresenter.applyArt(backgroundUrl: string, titleUrl: string, statuses: { [string]: string })
	local current = screen
	if current == nil then
		return
	end
	local background = current:FindFirstChild("Background")
	local art = if background ~= nil then background:FindFirstChild("BackgroundArt") else nil
	if art ~= nil and art:IsA("ImageLabel") then
		local status = if backgroundUrl ~= "" then statuses[backgroundUrl] else nil
		if LoadingPolicy.artMode(backgroundUrl, status, art.IsLoaded) == "image" then
			art.Image = backgroundUrl
		else
			art.Image = ""
		end
	end
	local title = titleImage
	if title ~= nil then
		local status = if titleUrl ~= "" then statuses[titleUrl] else nil
		if LoadingPolicy.artMode(titleUrl, status, title.IsLoaded) == "image" then
			title.Image = titleUrl
		else
			title.Image = ""
		end
	end
	syncTitle()
end

function LoadingPresenter.fadeOut()
	if fadeStarted then
		return
	end
	local current = screen
	if current == nil or not current.Enabled then
		unlockInput()
		setCover(false)
		return
	end
	fadeStarted = true
	local generation = showGeneration
	local info = TweenInfo.new(constants.Loading.FadeOutSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local targets: { Instance } = {}
	local background = current:FindFirstChild("Background")
	if background ~= nil then
		table.insert(targets, background)
		local art = background:FindFirstChild("BackgroundArt")
		if art ~= nil then
			table.insert(targets, art)
		end
	end
	if statusLabel ~= nil and statusLabel.Parent ~= nil then
		table.insert(targets, statusLabel.Parent)
		table.insert(targets, statusLabel)
	end
	if titleImage ~= nil then
		table.insert(targets, titleImage)
	end
	if titleText ~= nil then
		table.insert(targets, titleText)
	end
	for _, target in targets do
		if target:IsA("Frame") then
			TweenService:Create(target, info, { BackgroundTransparency = 1 }):Play()
		elseif target:IsA("ImageLabel") then
			TweenService:Create(target, info, { ImageTransparency = 1 }):Play()
		elseif target:IsA("TextLabel") then
			TweenService:Create(target, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end
	task.delay(constants.Loading.FadeOutSeconds, function()
		if generation ~= showGeneration then
			return
		end
		current.Enabled = false
		unlockInput()
		setCover(false)
	end)
end

function LoadingPresenter.fail(code: string, messageName: string, onRetry: () -> ())
	local current = buildScreen()
	current.Enabled = true
	fadeStarted = false
	setCover(true)
	lockInput()
	hideFailure()
	showingFailure = true
	setPhrase(LoadingPolicy.Phase.Failed)
	local panel = failurePanel
	local messageLabel = failureMessage
	local codeLabel = failureCode
	local retry = retryButton
	if panel == nil or messageLabel == nil or codeLabel == nil or retry == nil then
		return
	end
	messageLabel.Text = text(messageName)
	codeLabel.Text = text("ErrorCode", { code = code })
	retry.Text = text("Retry")
	panel.Visible = true
	local armed = true
	retryConnection = retry.Activated:Connect(function()
		if not armed then
			return
		end
		armed = false
		hideFailure()
		onRetry()
	end)
	layout()
	GuiService.SelectedObject = retry
end

if localeConnection == nil then
	localeConnection = Localization.onChanged(function()
		if screen ~= nil and screen.Enabled and not fadeStarted then
			setPhrase(phaseName)
			if titleText ~= nil then
				titleText.Text = text("Title")
			end
			if showingFailure and retryButton ~= nil then
				retryButton.Text = text("Retry")
			end
		end
	end)
end

return LoadingPresenter

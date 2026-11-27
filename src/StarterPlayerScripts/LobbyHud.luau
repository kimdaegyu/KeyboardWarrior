--!strict
-- Lobby HUD. The clock is the server phase end, not a local countdown.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local constants = require(ReplicatedStorage.Shared.IngameConstants)
local Localization = require(ReplicatedStorage.Shared.Localization)
local UiChrome = require(ReplicatedStorage.Shared.UiChrome)

local STATUS_FONT_SCALE = 2
local CAPACITY = constants.Match.MaxParticipants

local PHASE_KEYS: {[string]: string} = {
	Play = "Lobby.PhasePlay",
	Ready = "Lobby.PhaseReady",
	Result = "Lobby.PhaseResult",
	Rest = "Lobby.PhaseRest",
}

local Layout = require(script.Parent.Layout)
local LobbyHud = {}

local function formatTime(seconds: number): string
	local shown = math.max(0, math.ceil(seconds - 1e-4))
	local minutes = math.floor(shown / 60)
	local remainder = shown % 60
	return string.format("%d:%02d", minutes, remainder)
end

function LobbyHud.bind(root: Frame): () -> ()
	local panel = Instance.new("Frame")
	panel.Name = "LobbyHud"
	panel.BackgroundTransparency = 1
	panel.Size = UDim2.fromScale(1, 1)
	panel.Parent = root

	local stopStats = require(script.Parent.LobbyPlayerStats).bind(panel, root)

	local status = Instance.new("Frame")
	status.Name = "MatchStatus"
	status.AnchorPoint = Vector2.new(1, 0)
	status.Parent = panel
	UiChrome.paint(status, "panel")
	local function statusLine(name: string, y: number, height: number, maxFont: number): TextLabel
		local label = Instance.new("TextLabel")
		label.Name = name
		label.BackgroundTransparency = 1
		label.Position = UDim2.new(0, 5, y, 2)
		label.Size = UDim2.new(1, -10, height, -4)
		label.Font = Enum.Font.GothamBold
		label.TextColor3 = UiChrome.Navy
		label.TextScaled = true
		label.TextWrapped = false
		label.Text = ""
		local font = Instance.new("UITextSizeConstraint")
		font.MinTextSize = 10 * STATUS_FONT_SCALE
		font.MaxTextSize = maxFont * STATUS_FONT_SCALE
		font.Parent = label
		label.Parent = status
		return label
	end
	local phaseLine = statusLine("Phase", 0, 0.33, 20)
	phaseLine.BackgroundColor3 = UiChrome.Blue
	phaseLine.BackgroundTransparency = 0
	phaseLine.TextColor3 = UiChrome.White
	UiChrome.round(phaseLine, 6)
	local timeLine = statusLine("TimeLeft", 0.33, 0.38, 26)
	local queueLine = statusLine("Waiting", 0.71, 0.29, 18)
	queueLine.BackgroundColor3 = Color3.fromRGB(234, 241, 255)
	queueLine.BackgroundTransparency = 0
	local queueFont = queueLine:FindFirstChildOfClass("UITextSizeConstraint") :: UITextSizeConstraint
	queueFont.MinTextSize = 10
	queueLine.Font = Enum.Font.GothamMedium
	UiChrome.round(queueLine, 5)

	local function menuButton(name: string, role: string, iconKey: string | number): (TextButton, ImageLabel)
		local button = Instance.new("TextButton")
		button.Name = name
		button.AutoButtonColor = false
		button.Text = ""
		button.Visible = true
		button.Parent = panel
		UiChrome.paint(button, role)
		local mark = UiChrome.icon(button, iconKey)
		mark.AnchorPoint = Vector2.new(0.5, 0.5)
		mark.Position = UDim2.fromScale(0.5, 0.5)
		return button, mark
	end
	local practiceButton, practiceIcon = menuButton("Practice", "primary", "Practice")
	local shopButton, shopIcon = menuButton("Shop", "panel", "Shop")
	local rankButton, rankIcon = menuButton("Rank", "panel", 10073)
	local actionButtons = { practiceButton, shopButton, rankButton }
	local actionIcons = { practiceIcon, shopIcon, rankIcon }

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local existingTopbar = playerGui:FindFirstChild("KeyboardWarriorTopbar")
	if existingTopbar ~= nil then
		existingTopbar:Destroy()
	end
	local topbar = Instance.new("ScreenGui")
	topbar.Name = "KeyboardWarriorTopbar"
	topbar.ResetOnSpawn = false
	topbar.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	topbar.DisplayOrder = 10
	topbar.ScreenInsets = Enum.ScreenInsets.TopbarSafeInsets
	topbar.Parent = playerGui
	local settingsButton = Instance.new("TextButton")
	settingsButton.Name = "Settings"
	settingsButton.AnchorPoint = Vector2.new(0, 1)
	settingsButton.AutoButtonColor = false
	settingsButton.BackgroundColor3 = Color3.new(0, 0, 0)
	settingsButton.BorderSizePixel = 0
	settingsButton.Text = ""
	settingsButton.ClipsDescendants = true
	settingsButton.Visible = false
	settingsButton.Parent = topbar
	local settingsCorner = Instance.new("UICorner")
	settingsCorner.CornerRadius = UDim.new(0.5, 0)
	settingsCorner.Parent = settingsButton
	-- Item 10063 is a blue gear with a white hole. A flat white tint fills that hole.
	local settingsIcon = UiChrome.icon(settingsButton, 10063)
	settingsIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	settingsIcon.Position = UDim2.fromScale(0.5, 0.5)
	local function placeSettings()
		local band = topbar.AbsoluteSize
		if band.X < 1 or band.Y < 1 then
			return
		end
		-- Roblox draws the menu icon at 44px on the bottom of the 58px top bar.
		local row = GuiService.TopbarInset.Height
		local diameter = if row >= 50 then 44 elseif row > 0 then math.floor(row) else math.min(44, band.Y)
		diameter = math.min(diameter, band.X, band.Y)
		if diameter < 1 then
			return
		end
		settingsButton.AnchorPoint = Vector2.new(0, 1)
		settingsButton.Position = UDim2.fromOffset(8, band.Y)
		settingsButton.Size = UDim2.fromOffset(diameter, diameter)
		local iconSide = math.max(1, math.floor(diameter * 0.72))
		settingsIcon.Size = UDim2.fromOffset(iconSide, iconSide)
	end

	local function applyLayout()
		local size = root.AbsoluteSize
		if size.X < 1 or size.Y < 1 then return end
		local metrics = Layout.metrics(size)
		local edge = metrics.margin
		local statusHeight = metrics.statusHeight
		queueFont.MaxTextSize = metrics.hudTextSize
		queueLine.TextSize = metrics.hudTextSize
		queueLine:SetAttribute("FitWidth", nil)
		local statusWidth = math.clamp(math.round(size.X * 0.19), 138, 240)
		status.Position = UDim2.new(1, -edge, 0, metrics.statusTop)
		status.Size = UDim2.fromOffset(statusWidth, statusHeight)
		local gap = math.max(4, math.round(statusWidth * 0.04))
		local side = math.floor((statusWidth - gap * 2) / 3)
		if side < 1 then
			side = 1
		end
		local spare = statusWidth - (side * 3 + gap * 2)
		if spare < 0 then
			gap = math.max(1, math.floor((statusWidth - side * 3) / 2))
			spare = statusWidth - (side * 3 + gap * 2)
		end
		local cardTop = metrics.statusTop
		local above = gap
		local room = math.floor(cardTop - above)
		local rowWidth = statusWidth
		if side > room and room >= 1 then
			local scale = room / side
			side = math.max(1, math.floor(side * scale))
			gap = math.max(1, math.floor(gap * scale))
			spare = 0
			rowWidth = side * 3 + gap * 2
		end
		local rowLeft = size.X - edge - rowWidth
		local rowTop = math.max(0, cardTop - above - side)
		local iconSide = math.max(1, math.floor(side * 0.6))
		local step = side + gap
		for index, button in actionButtons do
			local shift = if index == #actionButtons then math.max(0, spare) else 0
			button.Size = UDim2.fromOffset(side, side)
			button.Position = UDim2.fromOffset(rowLeft + (index - 1) * step + shift, rowTop)
			actionIcons[index].Size = UDim2.fromOffset(iconSide, iconSide)
		end
		placeSettings()
	end
	applyLayout()

	local function canPractice(): boolean
		if Players.LocalPlayer:GetAttribute("InJoinZone") == true then
			return false
		end
		if Players.LocalPlayer:GetAttribute("InMatch") ~= true then
			return true
		end
		local folder = ReplicatedStorage:FindFirstChild("MatchState")
		local phaseName = if folder ~= nil then folder:GetAttribute("Phase") else nil
		return phaseName == "Result" and root:GetAttribute("ResultDismissed") == true
	end

	local function render()
		local folder = ReplicatedStorage:FindFirstChild("MatchState")
		local phaseName = if folder ~= nil then folder:GetAttribute("Phase") else nil
		local phaseKey = if type(phaseName) == "string" then PHASE_KEYS[phaseName] else nil
		local phase = if phaseKey ~= nil then Localization.getText(phaseKey) else Localization.getText("Lobby.Pending")

		local endsAt = if folder ~= nil then folder:GetAttribute("PhaseEndsAt") else nil
		local remain = 0
		if type(endsAt) == "number" then
			remain = math.max(0, endsAt - Workspace:GetServerTimeNow())
		end
		local time = Localization.getText("Lobby.TimeLeft", nil, { time = formatTime(remain) })

		local waitingCount = if folder ~= nil then folder:GetAttribute("WaitingCount") else 0
		if type(waitingCount) ~= "number" then
			waitingCount = 0
		end
		local queue = Localization.getText("Lobby.Queue", nil, {
			count = waitingCount,
			capacity = CAPACITY,
		})

		phaseLine.Text = phase
		timeLine.Text = time
		if queueLine.Text ~= queue or queueLine:GetAttribute("FitWidth") ~= queueLine.AbsoluteSize.X then
			queueLine.Text = queue
			queueLine.TextScaled = false
			queueLine.TextScaled = not queueLine.TextFits
			queueLine:SetAttribute("FitWidth", queueLine.AbsoluteSize.X)
		end

		local inMatch = Players.LocalPlayer:GetAttribute("InMatch") == true
		local practicing = root:GetAttribute("PracticeOpen") == true
		local settingsOpen = root:GetAttribute("SettingsOpen") == true
		local tutorialOpen = root:GetAttribute("TutorialOpen") == true
		local rankOpen = root:GetAttribute("RankOpen") == true
		local shopOpen = root:GetAttribute("ShopOpen") == true
		local dismissed = phaseName == "Result" and root:GetAttribute("ResultDismissed") == true
		local playing = inMatch and (phaseName == "Play" or phaseName == "Ready" or (phaseName == "Result" and not dismissed))
		panel.Visible = not practicing and not settingsOpen and not tutorialOpen and not rankOpen and not shopOpen and not playing
		local available = canPractice()
		UiChrome.paint(practiceButton, if available then "primary" else "panel")
		practiceButton.Active = available
		practiceButton.Selectable = available
		settingsButton.Visible = panel.Visible
	end
	local function openMenu(attribute: string)
		if panel.Visible then
			root:SetAttribute(attribute, true)
		end
	end
	shopButton.Activated:Connect(function()
		openMenu("ShopOpen")
	end)
	rankButton.Activated:Connect(function()
		openMenu("RankOpen")
	end)
	settingsButton.Activated:Connect(function()
		openMenu("SettingsOpen")
	end)
	practiceButton.Activated:Connect(function()
		if canPractice() then
			openMenu("PracticeOpen")
		end
	end)
	render()

	local connections = {
		root:GetAttributeChangedSignal("Compact"):Connect(applyLayout),
		root:GetAttributeChangedSignal("PracticeOpen"):Connect(render),
		root:GetAttributeChangedSignal("SettingsOpen"):Connect(render),
		root:GetAttributeChangedSignal("TutorialOpen"):Connect(render),
		root:GetAttributeChangedSignal("RankOpen"):Connect(render),
		root:GetAttributeChangedSignal("ShopOpen"):Connect(render),
		root:GetAttributeChangedSignal("ResultDismissed"):Connect(render),
		root:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout),
		topbar:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeSettings),
		GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(placeSettings),
		RunService.Heartbeat:Connect(render),
	}
	local stopLocale = Localization.onChanged(render)
	-- The lobby buttons and their Activated handlers exist. SafeRoot alone is not this signal.
	playerGui:SetAttribute("LobbyHudReady", true)
	return function()
		for _, connection in connections do
			connection:Disconnect()
		end
		stopLocale()
		stopStats()
		panel:Destroy()
		topbar:Destroy()
	end
end

return LobbyHud

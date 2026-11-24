--!strict
-- Left lobby HUD. The clock is the server phase end, not a local countdown.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local constants = require(ReplicatedStorage.Shared.IngameConstants)
local Localization = require(ReplicatedStorage.Shared.Localization)
local UiChrome = require(ReplicatedStorage.Shared.UiChrome)

local CAPACITY = constants.Match.MaxParticipants

local PHASE_KEYS: {[string]: string} = {
	Play = "Lobby.PhasePlay",
	Result = "Lobby.PhaseResult",
	Rest = "Lobby.PhaseRest",
}

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

	local status = Instance.new("TextLabel")
	status.Name = "MatchStatus"
	status.AnchorPoint = Vector2.new(0.5, 0)
	status.Font = Enum.Font.GothamBold
	status.TextColor3 = UiChrome.Navy
	status.TextScaled = true
	status.TextWrapped = false
	status.Parent = panel
	UiChrome.paint(status, "panel")
	local statusFont = Instance.new("UITextSizeConstraint")
	statusFont.MinTextSize = 9
	statusFont.MaxTextSize = 18
	statusFont.Parent = status
	local function menuButton(name: string, role: string, iconKey: string | number): TextButton
		local button = Instance.new("TextButton")
		button.Name = name
		button.AutoButtonColor = false
		button.Visible = false
		button.Parent = panel
		UiChrome.paint(button, role)
		local mark = UiChrome.icon(button, iconKey)
		mark.AnchorPoint = Vector2.new(0, 0.5)
		mark.Position = UDim2.new(0, 6, 0.5, 0)
		mark.Size = UDim2.fromOffset(18, 18)
		button.Text = ""
		local caption = Instance.new("TextLabel")
		caption.Name = "Caption"
		caption.Position = UDim2.fromOffset(if mark.Visible then 28 else 4, 0)
		caption.Size = UDim2.new(1, if mark.Visible then -32 else -8, 1, 0)
		caption.BackgroundTransparency = 1
		caption.Font = Enum.Font.GothamMedium
		caption.TextColor3 = UiChrome.Navy
		caption.TextScaled = true
		caption.Parent = button
		local font = Instance.new("UITextSizeConstraint")
		font.MaxTextSize = 17
		font.Parent = caption
		return button
	end
	local practiceButton = menuButton("Practice", "primary", "Practice")
	local practiceHint = Instance.new("TextLabel")
	practiceHint.Name = "PracticeHint"
	practiceHint.TextWrapped = true
	practiceHint.TextColor3 = UiChrome.Navy
	practiceHint.Visible = false
	practiceHint.Parent = panel
	UiChrome.paint(practiceHint, "panel")
	local shopButton = menuButton("Shop", "panel", "Shop")
	local rankButton = menuButton("Rank", "panel", 10073)
	local settingsButton = menuButton("Settings", "panel", 10063)

	local function applyLayout()
		local size = root.AbsoluteSize
		if size.X < 1 or size.Y < 1 then return end
		local compact = root:GetAttribute("Compact") == true
		local row = if compact then constants.UI.CompactTouchTarget else constants.UI.TouchTarget
		local width = if compact then 129 else 151
		local gap = 4
		local statusHeight = if compact then 26 else 34
		status.Position = UDim2.new(0.5, 0, 0, 4)
		status.Size = UDim2.fromOffset(math.min(size.X - 16, 620), statusHeight)
		-- Reserve the lower left for Roblox touch movement, including on short phones.
		local bottom = math.floor(size.Y * 0.62)
		local top = statusHeight + 10
		local columns = if bottom - top < row * 4 + gap * 3 then 2 else 1
		local rows = 4 / columns
		local menuHeight = rows * row + (rows - 1) * gap
		local start = math.clamp(math.floor((size.Y - menuHeight) * 0.5), top, math.max(top, bottom - menuHeight))
		for index, button in { practiceButton, shopButton, rankButton, settingsButton } do
			button.Size = UDim2.fromOffset(width, row)
			button.Position = UDim2.fromOffset(8 + ((index - 1) % columns) * (width + gap), start + math.floor((index - 1) / columns) * (row + gap))
		end
		practiceHint.Position = practiceButton.Position
		practiceHint.Size = practiceButton.Size
		practiceHint.TextSize = if compact then 12 else 15
	end
	applyLayout()

	local function setCaption(button: TextButton, text: string)
		local caption = button:FindFirstChild("Caption") :: TextLabel
		caption.Text = text
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

		local waiting = Players.LocalPlayer:GetAttribute("InJoinZone") == true
		local participation = Localization.getText(if waiting then "Lobby.Waiting" else "Lobby.NotWaiting")

		local waitingCount = if folder ~= nil then folder:GetAttribute("WaitingCount") else 0
		if type(waitingCount) ~= "number" then
			waitingCount = 0
		end
		local queue = Localization.getText("Lobby.Queue", nil, {
			count = waitingCount,
			capacity = CAPACITY,
		})

		status.Text = table.concat({ phase, time, participation, queue }, "   ·   ")

		local inMatch = Players.LocalPlayer:GetAttribute("InMatch") == true
		local practicing = root:GetAttribute("PracticeOpen") == true
		local settingsOpen = root:GetAttribute("SettingsOpen") == true
		local tutorialOpen = root:GetAttribute("TutorialOpen") == true
		local rankOpen = root:GetAttribute("RankOpen") == true
		local shopOpen = root:GetAttribute("ShopOpen") == true
		local playing = inMatch and (phaseName == "Play" or phaseName == "Result")
		panel.Visible = not practicing and not settingsOpen and not tutorialOpen and not rankOpen and not shopOpen and not playing
		practiceButton.Visible = panel.Visible and not waiting and not inMatch
		setCaption(practiceButton, Localization.getText("Practice.Start"))
		practiceHint.Visible = panel.Visible and waiting and not inMatch
		practiceHint.Text = Localization.getText("Practice.Outside")
		settingsButton.Visible = panel.Visible
		setCaption(settingsButton, Localization.getText("Settings.Open"))
		rankButton.Visible = panel.Visible
		setCaption(rankButton, Localization.getText("Rank.Open"))
		shopButton.Visible = panel.Visible
		setCaption(shopButton, Localization.getText("Shop.Open"))
	end
	shopButton.Activated:Connect(function()
		if Players.LocalPlayer:GetAttribute("InMatch") == true then
			local folder = ReplicatedStorage:FindFirstChild("MatchState")
			local phaseName = if folder ~= nil then folder:GetAttribute("Phase") else nil
			if phaseName == "Play" or phaseName == "Result" then
				return
			end
		end
		root:SetAttribute("ShopOpen", true)
	end)
	rankButton.Activated:Connect(function()
		if Players.LocalPlayer:GetAttribute("InMatch") == true then
			local folder = ReplicatedStorage:FindFirstChild("MatchState")
			local phaseName = if folder ~= nil then folder:GetAttribute("Phase") else nil
			if phaseName == "Play" or phaseName == "Result" then
				return
			end
		end
		root:SetAttribute("RankOpen", true)
	end)
	settingsButton.Activated:Connect(function()
		if Players.LocalPlayer:GetAttribute("InMatch") == true then
			local folder = ReplicatedStorage:FindFirstChild("MatchState")
			local phaseName = if folder ~= nil then folder:GetAttribute("Phase") else nil
			if phaseName == "Play" or phaseName == "Result" then
				return
			end
		end
		root:SetAttribute("SettingsOpen", true)
	end)
	practiceButton.Activated:Connect(function()
		if Players.LocalPlayer:GetAttribute("InJoinZone") == true or Players.LocalPlayer:GetAttribute("InMatch") == true then
			return
		end
		root:SetAttribute("PracticeOpen", true)
	end)
	render()

	local connections = {
		root:GetAttributeChangedSignal("Compact"):Connect(applyLayout),
		root:GetAttributeChangedSignal("PracticeOpen"):Connect(render),
		root:GetAttributeChangedSignal("SettingsOpen"):Connect(render),
		root:GetAttributeChangedSignal("TutorialOpen"):Connect(render),
		root:GetAttributeChangedSignal("RankOpen"):Connect(render),
		root:GetAttributeChangedSignal("ShopOpen"):Connect(render),
		root:GetAttributeChangedSignal("TouchTarget"):Connect(applyLayout),
		root:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout),
		RunService.Heartbeat:Connect(render),
	}
	local stopLocale = Localization.onChanged(render)
	return function()
		for _, connection in connections do
			connection:Disconnect()
		end
		stopLocale()
		panel:Destroy()
	end
end

return LobbyHud

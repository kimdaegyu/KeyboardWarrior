--!strict
-- First-run guide. Complete and Skip remember the player. A match start closes the guide without remembering.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local constants = require(ReplicatedStorage.Shared.IngameConstants)
local Localization = require(ReplicatedStorage.Shared.Localization)
local PracticeRules = require(ReplicatedStorage.Shared.PracticeRules)
local TableData = require(ReplicatedStorage.Shared.TableData)
local TutorialLayout = require(ReplicatedStorage.Shared.TutorialLayout)
local TutorialRules = require(ReplicatedStorage.Shared.TutorialRules)
local UiChrome = require(ReplicatedStorage.Shared.UiChrome)
local SettingsState = require(script.Parent.SettingsState)
local TutorialState = require(script.Parent.TutorialState)

local TutorialScreen = {}

function TutorialScreen.bind(root: Frame): () -> ()
	SettingsState.start()
	TutorialState.start()
	local catalog, reason = TutorialRules.catalog(TableData.rows("TutorialDataSheet") :: {TutorialRules.Row})
	assert(catalog ~= nil, reason)
	local steps = TutorialRules.active(catalog :: {TutorialRules.Step})

	local screen = Instance.new("Frame")
	screen.Name = "TutorialScreen"
	screen.Size = UDim2.fromScale(1, 1)
	screen.BackgroundColor3 = Color3.fromRGB(12, 6, 24)
	screen.BackgroundTransparency = 1
	screen.BorderSizePixel = 0
	screen.Visible = false
	screen.Active = false
	screen.ZIndex = 6
	screen.Parent = root

	local panel = Instance.new("ImageLabel")
	panel.Name = "Panel"
	panel.BackgroundColor3 = UiChrome.White
	panel.BorderSizePixel = 0
	panel.ZIndex = 7
	panel.Parent = screen
	UiChrome.paint(panel, "panel")

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextColor3 = UiChrome.Navy
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel.ZIndex = 8
	titleLabel.Parent = panel

	local body = Instance.new("ScrollingFrame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.ScrollBarThickness = 4
	body.ScrollingDirection = Enum.ScrollingDirection.Y
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.CanvasSize = UDim2.new()
	body.ZIndex = 8
	body.Parent = panel
	local bodyText = Instance.new("TextLabel")
	bodyText.Name = "Text"
	bodyText.BackgroundTransparency = 1
	bodyText.Size = UDim2.new(1, -4, 0, 0)
	bodyText.AutomaticSize = Enum.AutomaticSize.Y
	bodyText.Font = Enum.Font.GothamMedium
	bodyText.TextColor3 = UiChrome.Navy
	bodyText.TextXAlignment = Enum.TextXAlignment.Left
	bodyText.TextYAlignment = Enum.TextYAlignment.Top
	bodyText.TextWrapped = true
	bodyText.ZIndex = 9
	bodyText.Parent = body

	local stepLabel = Instance.new("TextLabel")
	stepLabel.Name = "Step"
	stepLabel.BackgroundTransparency = 1
	stepLabel.Font = Enum.Font.GothamMedium
	stepLabel.TextColor3 = UiChrome.Navy
	stepLabel.TextXAlignment = Enum.TextXAlignment.Center
	stepLabel.ZIndex = 8
	stepLabel.Parent = panel

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
		item.ZIndex = 8
		item.Parent = panel
		return item
	end

	local previousButton = button("Previous", "panel")
	local nextButton = button("Next", "primary")
	local skipButton = button("Skip", "panel")
	local guideIcon = UiChrome.icon(panel, "Tutorial")
	guideIcon.ZIndex = 8

	local page = 1
	local shown = false
	local held = false

	local function viewport(): (number, number, number)
		local size = root.AbsoluteSize
		local content = root:GetAttribute("ContentWidth")
		local width = size.X
		if type(content) == "number" then
			width = math.min(width, content)
		end
		return size.X, size.Y, width
	end

	local function currentStep(): TutorialRules.Step?
		return steps[page]
	end

	local function render()
		local step = currentStep()
		if step == nil then
			return
		end
		local facts = if step.bodyKey == "Tutorial.TypingBody"
			then {
				seconds = constants.Match.DoubleScoreSeconds,
				multiplier = constants.Match.EndScoreMultiplier,
			}
			else nil
		titleLabel.Text = Localization.getText(step.titleKey)
		bodyText.Text = Localization.getText(step.bodyKey, nil, facts)
		stepLabel.Text = TutorialRules.progress(page, #steps)
		previousButton.Text = Localization.getText("Tutorial.Previous")
		previousButton.Active = page > 1
		previousButton.AutoButtonColor = page > 1
		previousButton.TextTransparency = if page > 1 then 0 else 0.45
		local last = page >= #steps
		nextButton.Text = Localization.getText(if last then "Tutorial.Done" else "Tutorial.Next")
		skipButton.Text = Localization.getText("Tutorial.Skip")
	end

	local function applyLayout()
		if not screen.Visible then
			return
		end
		local sizeX, sizeY, width = viewport()
		if sizeX < 50 or sizeY < 50 then
			return
		end
		local step = currentStep()
		local docked = step ~= nil and step.id == "join" and root:GetAttribute("SettingsOpen") ~= true
		local plan = TutorialLayout.plan(width, sizeY, docked, constants.UI.CompactHeight, constants.UI.CompactWidth)
		local origin = math.floor((sizeX - width) / 2)
		local x = origin + math.floor((width - plan.panelWidth) / 2)
		local y = if plan.docked then sizeY - plan.margin - plan.panelHeight else math.floor((sizeY - plan.panelHeight) / 2)
		screen.BackgroundTransparency = if plan.docked then 1 else 0.35
		screen.Active = not plan.docked
		panel.Position = UDim2.fromOffset(x, math.max(plan.margin, y))
		panel.Size = UDim2.fromOffset(plan.panelWidth, plan.panelHeight)

		local inner = plan.gap
		local rowWidth = math.max(0, plan.panelWidth - inner * 2)
		local cursor = inner
		local iconRoom = if guideIcon.Visible then plan.title else 0
		guideIcon.Position = UDim2.fromOffset(inner, cursor)
		guideIcon.Size = UDim2.fromOffset(iconRoom, plan.title)
		titleLabel.Position = UDim2.fromOffset(inner + iconRoom, cursor)
		titleLabel.Size = UDim2.fromOffset(math.max(0, rowWidth - iconRoom), plan.title)
		titleLabel.TextSize = math.clamp(plan.title - 4, 14, 24)
		cursor += plan.title + plan.gap
		body.Position = UDim2.fromOffset(inner, cursor)
		body.Size = UDim2.fromOffset(rowWidth, plan.body)
		bodyText.TextSize = math.clamp(plan.body / 4, 13, 18)
		cursor += plan.body + plan.gap
		stepLabel.Position = UDim2.fromOffset(inner, cursor)
		stepLabel.Size = UDim2.fromOffset(rowWidth, plan.step)
		stepLabel.TextSize = math.clamp(plan.step - 2, 12, 16)
		cursor += plan.step + plan.gap
		local gap = plan.gap
		local buttonWidth = math.floor((rowWidth - gap * 2) / 3)
		local buttons = { previousButton, nextButton, skipButton }
		for _, item in buttons do
			item.Position = UDim2.fromOffset(inner, cursor)
			item.Size = UDim2.fromOffset(buttonWidth, plan.row)
			item.TextSize = math.clamp(plan.row - 14, 12, 18)
			local face = item:GetAttribute("Face")
			local role = if type(face) == "string" then face else "panel"
			UiChrome.paint(item, role)
			item.TextColor3 = UiChrome.ink(role)
			inner += buttonWidth + gap
		end
	end

	local function closeForMatch()
		held = true
		shown = false
		screen.Visible = false
		root:SetAttribute("TutorialOpen", false)
		root:SetAttribute("TutorialReplay", false)
	end

	local function acknowledge()
		held = true
		shown = false
		screen.Visible = false
		root:SetAttribute("TutorialOpen", false)
		root:SetAttribute("TutorialReplay", false)
		TutorialState.acknowledge()
	end

	local function consider()
		if held or shown or #steps == 0 then
			return
		end
		if root:GetAttribute("TutorialOpen") == true then
			return
		end
		if SettingsState.saveState() == "loading" then
			return
		end
		if not TutorialState.known() or TutorialState.seen() or TutorialState.saveState() ~= "ready" then
			return
		end
		if root:GetAttribute("PracticeOpen") == true or root:GetAttribute("SettingsOpen") == true or root:GetAttribute("RankOpen") == true or root:GetAttribute("ShopOpen") == true then
			return
		end
		local folder = ReplicatedStorage:FindFirstChild("MatchState")
		local phaseName = if folder ~= nil then folder:GetAttribute("Phase") else nil
		local phase = if type(phaseName) == "string" then phaseName else ""
		if PracticeRules.blockedByMatch(Players.LocalPlayer:GetAttribute("InMatch") == true, phase, root:GetAttribute("ResultDismissed") == true) then
			return
		end
		page = 1
		root:SetAttribute("TutorialOpen", true)
	end

	local function sync()
		local folder = ReplicatedStorage:FindFirstChild("MatchState")
		local phaseName = if folder ~= nil then folder:GetAttribute("Phase") else nil
		local phase = if type(phaseName) == "string" then phaseName else ""
		local open = root:GetAttribute("TutorialOpen") == true
		if open and PracticeRules.blockedByMatch(Players.LocalPlayer:GetAttribute("InMatch") == true, phase, root:GetAttribute("ResultDismissed") == true) then
			closeForMatch()
			return
		end
		if open and not shown then
			page = 1
			shown = true
		end
		if not open then
			shown = false
		end
		screen.Visible = open and #steps > 0
		if screen.Visible then
			render()
			applyLayout()
		else
			consider()
		end
	end

	previousButton.Activated:Connect(function()
		if page <= 1 then
			return
		end
		page -= 1
		render()
		applyLayout()
	end)
	nextButton.Activated:Connect(function()
		if page < #steps then
			page += 1
			render()
			applyLayout()
			return
		end
		acknowledge()
	end)
	skipButton.Activated:Connect(function()
		acknowledge()
	end)

	local stateFolder = ReplicatedStorage:WaitForChild("MatchState")
	local connections = {
		root:GetAttributeChangedSignal("TutorialOpen"):Connect(sync),
		root:GetAttributeChangedSignal("SettingsOpen"):Connect(sync),
		root:GetAttributeChangedSignal("PracticeOpen"):Connect(sync),
		root:GetAttributeChangedSignal("RankOpen"):Connect(sync),
		root:GetAttributeChangedSignal("ShopOpen"):Connect(sync),
		root:GetAttributeChangedSignal("ContentWidth"):Connect(applyLayout),
		root:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout),
		Players.LocalPlayer:GetAttributeChangedSignal("InMatch"):Connect(sync),
		stateFolder:GetAttributeChangedSignal("Phase"):Connect(sync),
	}
	local stopTutorial = TutorialState.onChanged(sync)
	local stopSettings = SettingsState.onChanged(sync)
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
		stopTutorial()
		stopSettings()
		stopLocale()
		screen:Destroy()
	end
end

return TutorialScreen

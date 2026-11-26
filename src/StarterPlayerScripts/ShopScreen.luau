--!strict
-- Lobby shop. Selecting a product changes only that preview slot. Equip is the save.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local constants = require(ReplicatedStorage.Shared.IngameConstants)
local Localization = require(ReplicatedStorage.Shared.Localization)
local PadLook = require(ReplicatedStorage.Shared.PadLook)
local PracticeRules = require(ReplicatedStorage.Shared.PracticeRules)
local ShopLayout = require(ReplicatedStorage.Shared.ShopLayout)
local ShopRules = require(ReplicatedStorage.Shared.ShopRules)
local TableData = require(ReplicatedStorage.Shared.TableData)
local TitleRules = require(ReplicatedStorage.Shared.TitleRules)
local ItemIconUtil = require(ReplicatedStorage.Shared.ItemIconUtil)
local UiChrome = require(ReplicatedStorage.Shared.UiChrome)
local UIImageUtil = require(ReplicatedStorage.Shared.UIImageUtil)
local ShopState = require(script.Parent.ShopState)
local TitleState = require(script.Parent.TitleState)

local Layout = require(script.Parent.Layout)
local ShopScreen = {}

function ShopScreen.bind(root: Frame): () -> ()
	local screen = Instance.new("Frame")
	screen.Name = "ShopScreen"
	screen.Size = UDim2.fromScale(1, 1)
	screen.BackgroundColor3 = UiChrome.Navy
	screen.BackgroundTransparency = 1
	screen.BorderSizePixel = 0
	screen.Visible = false
	screen.Active = true
	screen.ZIndex = 3
	screen.Parent = root

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.BackgroundColor3 = UiChrome.White
	card.BorderSizePixel = 0
	card.ZIndex = 4
	card.Parent = screen

	local function label(name: string): TextLabel
		local item = Instance.new("TextLabel")
		item.Name = name
		item.BackgroundTransparency = 1
		item.Font = Enum.Font.GothamMedium
		item.TextColor3 = UiChrome.Navy
		item.TextXAlignment = Enum.TextXAlignment.Left
		item.TextYAlignment = Enum.TextYAlignment.Center
		item.TextTruncate = Enum.TextTruncate.AtEnd
		item.ZIndex = 5
		item.Parent = card
		return item
	end

	local titleLabel = label("Title")
	titleLabel.TextXAlignment = Enum.TextXAlignment.Center
	titleLabel.Font = Enum.Font.GothamBold
	local goldLabel = label("Gold")
	local goldIcon = Instance.new("ImageLabel")
	goldIcon.Name = "GoldIcon"
	goldIcon.BackgroundTransparency = 1
	goldIcon.ZIndex = 6
	goldIcon.Parent = card
	goldIcon.Visible = ItemIconUtil.apply(goldIcon, 1)
	goldIcon.ScaleType = Enum.ScaleType.Fit

	local function tabButton(name: string): TextButton
		local button = Instance.new("TextButton")
		button.Name = name
		button.Font = Enum.Font.GothamMedium
		button.TextColor3 = UiChrome.Navy
		button.BackgroundColor3 = UiChrome.White
		button.BackgroundTransparency = 0
		button.BorderSizePixel = 0
		button.AutoButtonColor = false
		button.TextTruncate = Enum.TextTruncate.AtEnd
		button.ZIndex = 5
		button.Parent = card
		return button
	end

	local bodyTab = tabButton("BodyTab")
	local rimTab = tabButton("RimTab")
	local effectTab = tabButton("EffectTab")

	local list = Instance.new("ScrollingFrame")
	list.Name = "Products"
	list.ClipsDescendants = true
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ZIndex = 5
	list.Parent = card
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = list

	local preview = Instance.new("ViewportFrame")
	preview.Name = "Preview"
	preview.BackgroundColor3 = Color3.fromRGB(232, 236, 244)
	preview.BorderSizePixel = 0
	preview.Ambient = Color3.fromRGB(190, 190, 210)
	preview.LightColor = Color3.new(1, 1, 1)
	preview.ZIndex = 5
	preview.Parent = card
	local previewCorner = Instance.new("UICorner")
	previewCorner.CornerRadius = UDim.new(0, 8)
	previewCorner.Parent = preview
	local world = Instance.new("WorldModel")
	world.Parent = preview
	local camera = Instance.new("Camera")
	camera.CFrame = CFrame.new(Vector3.new(9, 7, 9), Vector3.new(0, 1, 0))
	camera.Parent = preview
	preview.CurrentCamera = camera
	local pad = Instance.new("Part")
	pad.Name = "PreviewPad"
	pad.Anchored = true
	pad.CanCollide = false
	pad.Shape = Enum.PartType.Cylinder
	pad.Size = Vector3.new(1, 6, 6)
	pad.CFrame = CFrame.new(0, 1, 0) * CFrame.Angles(0, 0, math.rad(90))
	pad.Parent = world

	local function actionButton(name: string): TextButton
		local button = Instance.new("TextButton")
		button.Name = name
		button.Font = Enum.Font.GothamMedium
		button.TextColor3 = UiChrome.Navy
		button.BackgroundColor3 = UiChrome.White
		button.BackgroundTransparency = 0
		button.BorderSizePixel = 0
		button.AutoButtonColor = false
		button.TextTruncate = Enum.TextTruncate.AtEnd
		button.ZIndex = 5
		button.Parent = card
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = button
		return button
	end

	local buyButton = actionButton("Buy")
	local titleButton = actionButton("Titles")
	local closeButton = UiChrome.closeButton(card)
	local titlePanel = Instance.new("Frame")
	titlePanel.Name = "Titles"
	titlePanel.BackgroundColor3 = UiChrome.White
	titlePanel.BorderSizePixel = 0
	titlePanel.Visible = false
	titlePanel.ZIndex = 7
	titlePanel.Parent = card
	local titleList = Instance.new("ScrollingFrame")
	titleList.Name = "TitleList"
	titleList.BackgroundTransparency = 1
	titleList.BorderSizePixel = 0
	titleList.ScrollBarThickness = 6
	titleList.CanvasSize = UDim2.fromOffset(0, 0)
	titleList.ZIndex = 8
	titleList.Parent = titlePanel
	local autoButton = actionButton("Auto")
	autoButton.Parent = titlePanel
	autoButton.ZIndex = 8
	local titleCards: {TextButton} = {}
	local titlesOpen = false
	local loadedTitles = TitleRules.catalog(TableData.rows("AchievementDataSheet") :: {TitleRules.Row}) or {}
	local previewArt = Instance.new("ImageLabel")
	previewArt.Name = "ProductArt"
	previewArt.BackgroundTransparency = 1
	previewArt.ScaleType = Enum.ScaleType.Fit
	previewArt.ZIndex = 6
	previewArt.Visible = false
	previewArt.Parent = card

	local category = "Body"
	local draft = { body = "", rim = "", effect = "" }
	local touched = false
	local shown = false
	local cards: {TextButton} = {}

	local function equippedId(): string
		if category == "Rim" then
			return ShopState.rim()
		end
		if category == "Effect" then
			return ShopState.effect()
		end
		return ShopState.body()
	end

	local function draftId(): string
		if category == "Rim" then
			return draft.rim
		end
		if category == "Effect" then
			return draft.effect
		end
		return draft.body
	end

	local function setDraft(id: string)
		touched = true
		if category == "Rim" then
			draft.rim = id
		elseif category == "Effect" then
			draft.effect = id
		else
			draft.body = id
		end
	end

	local function catalog(): {ShopRules.Item}
		local rows: {ShopRules.Item} = {}
		for _, item in ShopState.items() do
			table.insert(rows, {
				id = item.id,
				category = item.category,
				currency = item.currency,
				price = item.price,
				platformProductId = "",
				enabled = true,
				release = item.release,
				color = item.color,
			})
		end
		return rows
	end

	local function selected()
		local id = draftId()
		for _, item in ShopState.items() do
			if item.id == id then
				return item
			end
		end
		return nil
	end

	local render: () -> ()

	local function ensureCard(index: number): TextButton
		local existing = cards[index]
		if existing ~= nil then
			return existing
		end
		local button = Instance.new("TextButton")
		button.Name = "Product"
		button.Font = Enum.Font.GothamMedium
		button.TextColor3 = UiChrome.Navy
		button.BackgroundColor3 = UiChrome.White
		button.BackgroundTransparency = 0
		button.BorderSizePixel = 0
		button.AutoButtonColor = false
		button.TextTruncate = Enum.TextTruncate.AtEnd
		button.TextXAlignment = Enum.TextXAlignment.Left
		local art = Instance.new("ImageLabel")
		art.Name = "Art"
		art.BackgroundTransparency = 1
		art.AnchorPoint = Vector2.new(0, 0.5)
		art.Position = UDim2.new(0, 8, 0.5, 0)
		art.Size = UDim2.fromOffset(28, 28)
		art.ZIndex = 7
		art.Parent = button
		button.ZIndex = 6
		button.Parent = list
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = button
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 8)
		padding.PaddingRight = UDim.new(0, 8)
		padding.Parent = button
		button.Activated:Connect(function()
			local id = button:GetAttribute("ItemId")
			if type(id) ~= "string" then
				return
			end
			setDraft(id)
			render()
		end)
		cards[index] = button
		return button
	end

	local function applyLayout()
		local bounds = root.AbsoluteSize
		if bounds.X < 50 or bounds.Y < 50 then return end
		local metrics = Layout.metrics(bounds)
		local width, height = ShopLayout.windowSize(bounds.X, bounds.Y, metrics.margin)
		local size = Vector2.new(width, height)
		card.Size = UDim2.fromOffset(size.X, size.Y)
		local plan = ShopLayout.plan(size.X, size.Y, constants.UI.CompactHeight, constants.UI.CompactWidth, metrics.target)
		local inner = math.max(0, size.X - plan.margin * 2)
		UiChrome.paint(card, "panel")
		local y = plan.margin
		titleLabel.Position = UDim2.fromOffset(plan.margin, y)
		titleLabel.Size = UDim2.fromOffset(math.max(0, inner - 120), plan.title)
		titleLabel.TextSize = math.clamp(plan.title - 2, 14, 28)
		y += plan.title + plan.gap
		local goldShift = if goldIcon.Visible then plan.gold + 4 else 0
		goldIcon.Position = UDim2.fromOffset(plan.margin, y)
		goldIcon.Size = UDim2.fromOffset(plan.gold, plan.gold)
		goldLabel.Position = UDim2.fromOffset(plan.margin + goldShift, y)
		goldLabel.Size = UDim2.fromOffset(math.max(0, inner - goldShift), plan.gold)
		goldLabel.TextSize = math.clamp(plan.gold - 2, 12, 20)
		y += plan.gold + plan.gap
		local tabWidth = math.floor((inner - plan.gap * 2) / 3)
		local tabs = { bodyTab, rimTab, effectTab }
		for index, tab in tabs do
			tab.Position = UDim2.fromOffset(plan.margin + (index - 1) * (tabWidth + plan.gap), y)
			tab.Size = UDim2.fromOffset(tabWidth, plan.tab)
			tab.TextSize = math.clamp(plan.tab - 14, 12, 18)
			local face = tab:GetAttribute("Face")
			local role = if type(face) == "string" then face else "panel"
			UiChrome.paint(tab, role)
			tab.TextColor3 = UiChrome.ink(role)
		end
		y += plan.tab + plan.gap
		list.Position = UDim2.fromOffset(plan.margin, y)
		list.Size = UDim2.fromOffset(plan.list, plan.body)
		preview.Position = UDim2.fromOffset(plan.margin + plan.list + plan.gap, y)
		preview.Size = UDim2.fromOffset(plan.preview, plan.body)
		previewArt.Position = UDim2.fromOffset(plan.margin + plan.list + plan.gap + 8, y + 8)
		previewArt.Size = UDim2.fromOffset(math.min(64, math.max(0, plan.preview - 16)), math.min(64, math.max(0, plan.body - 16)))
		for _, button in cards do
			button.Size = UDim2.new(1, -8, 0, plan.action)
			button.TextSize = math.clamp(plan.action - 16, 12, 18)
			local face = button:GetAttribute("Face")
			local role = if type(face) == "string" then face else "panel"
			UiChrome.paint(button, role)
			button.TextColor3 = UiChrome.ink(role)
		end
		y += plan.body + plan.gap
		local closeSize = math.min(plan.action, plan.title + plan.gap + plan.gold)
		buyButton.Position = UDim2.fromOffset(plan.margin, y)
		buyButton.Size = UDim2.fromOffset(inner, plan.action)
		closeButton.Position = UDim2.fromOffset(size.X - plan.margin, plan.margin)
		closeButton.Size = UDim2.fromOffset(closeSize, closeSize)
		local titleWidth = math.min(108, math.max(64, closeSize * 2))
		titleButton.Position = UDim2.fromOffset(size.X - plan.margin - closeSize - 6 - titleWidth, plan.margin)
		titleButton.Size = UDim2.fromOffset(titleWidth, closeSize)
		titleButton.TextSize = math.clamp(closeSize - 16, 11, 16)
		titleButton.Text = Localization.getText("Shop.Titles")
		UiChrome.paint(titleButton, if titlesOpen then "selected" else "panel")
		titleButton.TextColor3 = UiChrome.ink(if titlesOpen then "selected" else "panel")
		titlePanel.Position = list.Position
		titlePanel.Size = UDim2.fromOffset(plan.list + plan.gap + plan.preview, plan.body)
		titleList.Size = UDim2.new(1, 0, 1, -plan.action - 4)
		autoButton.Position = UDim2.new(0, 0, 1, -plan.action)
		autoButton.Size = UDim2.new(1, 0, 0, plan.action)
		autoButton.TextSize = math.clamp(plan.action - 16, 12, 18)
		autoButton.Text = Localization.getText("Title.Auto")
		UiChrome.paint(autoButton, if TitleState.mode() == "auto" then "selected" else "primary")
		autoButton.TextColor3 = UiChrome.ink(if TitleState.mode() == "auto" then "selected" else "primary")
		buyButton.TextSize = math.clamp(plan.action - 16, 12, 18)
		closeButton.TextSize = math.round(closeSize * 0.55)
		local buyFace = buyButton:GetAttribute("Face")
		local buyRole = if type(buyFace) == "string" then buyFace else "primary"
		UiChrome.paint(buyButton, buyRole)
		buyButton.TextColor3 = UiChrome.ink(buyRole)
		UiChrome.paint(closeButton, "panel")
		closeButton.TextColor3 = UiChrome.Navy
	end

	render = function()
		titleLabel.Text = Localization.getText("Shop.Title")

		bodyTab.Text = Localization.getText("Shop.TabBody")
		rimTab.Text = Localization.getText("Shop.TabRim")
		effectTab.Text = Localization.getText("Shop.TabEffect")
		local note = ""
		local why = ShopState.reason()
		if not ShopState.received() then
			note = Localization.getText("Shop.Loading")
		elseif ShopState.status() == "unavailable" or why == "unavailable" then
			note = Localization.getText("Shop.Unavailable")
		elseif why == "funds" then
			note = Localization.getText("Shop.Funds")
		elseif why == "closed" then
			note = Localization.getText("Shop.Closed")
		end
		local gold = Localization.getText("Shop.Gold", nil, { gold = ShopState.gold() })
		goldLabel.Text = if note == "" then gold else gold .. "  " .. note
		local tabs = { Body = bodyTab, Rim = rimTab, Effect = effectTab }
		for name, tab in tabs do
			tab:SetAttribute("Face", if name == category then "selected" else "panel")
		end
		local shownItems = {}
		for _, item in ShopState.items() do
			if item.category == category then
				table.insert(shownItems, item)
			end
		end
		table.sort(shownItems, function(left, right)
			if left.release == "Default" and right.release ~= "Default" then
				return true
			end
			if right.release == "Default" and left.release ~= "Default" then
				return false
			end
			if left.price ~= right.price then
				return left.price < right.price
			end
			return left.id < right.id
		end)
		local chosen = draftId()
		for index, item in shownItems do
			local button = ensureCard(index)
			button.Visible = true
			button.LayoutOrder = index
			button:SetAttribute("ItemId", item.id)
			button.Text = Localization.getText("Shop.Name." .. item.id)
			button:SetAttribute("Face", if item.id == chosen then "selected" else "panel")
			local art = button:FindFirstChild("Art")
			if art ~= nil and art:IsA("ImageLabel") then
				local shownArt = UIImageUtil.apply(art, item.id)
				art.Visible = shownArt
				if shownArt then
					art.ScaleType = Enum.ScaleType.Fit
					art.ImageColor3 = Color3.new(1, 1, 1)
				end
				local inset = button:FindFirstChild("Inset")
				if inset == nil then
					local padding = button:FindFirstChildOfClass("UIPadding")
					if padding ~= nil then
						padding.Name = "Inset"
						inset = padding
					end
				end
				if inset ~= nil and inset:IsA("UIPadding") then
					inset.PaddingLeft = UDim.new(0, if shownArt then 40 else 8)
					art.Position = UDim2.new(0, -32, 0.5, 0)
				end
			end
		end
		for index = #shownItems + 1, #cards do
			cards[index].Visible = false
		end
		local item = selected()
		local worn = equippedId()
		buyButton.AutoButtonColor = true
		buyButton.Active = true
		if not ShopState.received() or ShopState.pending() or item == nil then
			buyButton.Text = Localization.getText(if ShopState.pending() then "Shop.Processing" else "Shop.Loading")
			buyButton.Active = false
			buyButton.AutoButtonColor = false
			buyButton:SetAttribute("Face", "panel")
		elseif item.id == worn then
			buyButton.Text = Localization.getText("Shop.Equipped")
			buyButton.Active = false
			buyButton.AutoButtonColor = false
			buyButton:SetAttribute("Face", "selected")
		elseif item.currency == "Achievement" and not item.owned then
			buyButton.Text = Localization.getText("Shop.NeedScore", nil, { score = tostring(item.score or 0) })
			buyButton.Active = false
			buyButton.AutoButtonColor = false
			buyButton:SetAttribute("Face", "panel")
		elseif item.owned then
			buyButton.Text = Localization.getText("Shop.Equip")
			buyButton:SetAttribute("Face", "primary")
		else
			buyButton.Text = Localization.getText("Shop.Buy", nil, { price = item.price })
			buyButton:SetAttribute("Face", "primary")
		end
		if item ~= nil then
			local shownArt = UIImageUtil.apply(previewArt, item.id)
			previewArt.Visible = shownArt
			if shownArt then
				previewArt.ScaleType = Enum.ScaleType.Fit
				previewArt.ImageColor3 = Color3.new(1, 1, 1)
			end
		else
			previewArt.Visible = false
		end
		PadLook.apply(pad, ShopRules.preview(catalog(), draft.body, draft.rim, draft.effect))
		titlePanel.Visible = titlesOpen
		list.Visible = not titlesOpen
		preview.Visible = not titlesOpen
		local ownedTitles = TitleState.titles()
		for index = 1, math.max(#ownedTitles, #titleCards) do
			local titleId = ownedTitles[index]
			local button = titleCards[index]
			if titleId ~= nil and button == nil then
				button = Instance.new("TextButton")
				button.Font = Enum.Font.GothamMedium
				button.TextXAlignment = Enum.TextXAlignment.Left
				button.BackgroundColor3 = UiChrome.White
				button.AutoButtonColor = false
				button.TextTruncate = Enum.TextTruncate.AtEnd
				button.ZIndex = 9
				button.Parent = titleList
				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(0, 6)
				corner.Parent = button
				button.Activated:Connect(function()
					local picked = button:GetAttribute("TitleId")
					if type(picked) == "number" then
						TitleState.equip(picked)
					end
				end)
				titleCards[index] = button
			end
			if button ~= nil then
				button.Visible = titleId ~= nil
				if titleId ~= nil then
					local achievement = TitleRules.find(loadedTitles, titleId)
					local name = if achievement ~= nil then Localization.getText(achievement.titleKey) else tostring(titleId)
					button.Text = name
					button:SetAttribute("TitleId", titleId)
					button.Size = UDim2.new(1, -8, 0, 32)
					button.Position = UDim2.fromOffset(4, (index - 1) * 36)
					button.TextSize = 14
					local selectedTitle = TitleState.equipped() == titleId and TitleState.mode() == "manual"
					button.TextColor3 = if selectedTitle then UiChrome.White else UiChrome.Navy
					button.BackgroundColor3 = if selectedTitle then UiChrome.Blue else UiChrome.White
				end
			end
		end
		if #ownedTitles == 0 then
			titleList.CanvasSize = UDim2.fromOffset(0, 32)
		else
			titleList.CanvasSize = UDim2.fromOffset(0, #ownedTitles * 36)
		end
		applyLayout()
	end

	local function sync()
		local folder = ReplicatedStorage:FindFirstChild("MatchState")
		local phaseName = if folder ~= nil then folder:GetAttribute("Phase") else nil
		local phase = if type(phaseName) == "string" then phaseName else ""
		local open = root:GetAttribute("ShopOpen") == true
		if open and PracticeRules.blockedByMatch(Players.LocalPlayer:GetAttribute("InMatch") == true, phase, root:GetAttribute("ResultDismissed") == true) then
			shown = false
			touched = false
			screen.Visible = false
			root:SetAttribute("ShopOpen", false)
			return
		end
		if open and not shown then
			shown = true
			touched = false
			category = "Body"
			ShopState.request()
			TitleState.sync()
		end
		if not open then
			shown = false
			touched = false
		end
		screen.Visible = open
		if open then
			if not touched then
				draft.body = ShopState.body()
				draft.rim = ShopState.rim()
				draft.effect = ShopState.effect()
			end
			render()
		end
	end

	closeButton.Activated:Connect(function()
		root:SetAttribute("ShopOpen", false)
	end)
	buyButton.Activated:Connect(function()
		local item = selected()
		if item == nil or ShopState.pending() or item.id == equippedId() then
			return
		end
		if item.currency == "Achievement" and not item.owned then
			return
		end
		if item.owned then
			ShopState.equip(item.id)
		else
			ShopState.buy(item.id)
		end
	end)
	titleButton.Activated:Connect(function()
		titlesOpen = not titlesOpen
		render()
	end)
	autoButton.Activated:Connect(function()
		TitleState.auto()
	end)
	bodyTab.Activated:Connect(function()
		titlesOpen = false
		category = "Body"
		render()
	end)
	rimTab.Activated:Connect(function()
		titlesOpen = false
		category = "Rim"
		render()
	end)
	effectTab.Activated:Connect(function()
		titlesOpen = false
		category = "Effect"
		render()
	end)

	local stateFolder = ReplicatedStorage:WaitForChild("MatchState")
	local connections = {
		root:GetAttributeChangedSignal("ShopOpen"):Connect(sync),
		root:GetAttributeChangedSignal("ContentWidth"):Connect(applyLayout),
		root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			if screen.Visible then
				applyLayout()
			end
		end),
		Players.LocalPlayer:GetAttributeChangedSignal("InMatch"):Connect(sync),
		stateFolder:GetAttributeChangedSignal("Phase"):Connect(sync),
	}
	local stopShop = ShopState.onChanged(function()
		if screen.Visible then
			if not touched then
				draft.body = ShopState.body()
				draft.rim = ShopState.rim()
				draft.effect = ShopState.effect()
			end
			render()
		end
	end)
	local stopLocale = Localization.onChanged(function()
		if screen.Visible then
			render()
		end
	end)
	local stopTitles = TitleState.listen(function()
		if screen.Visible then
			render()
		end
	end)
	ShopState.start()
	sync()
	return function()
		for _, connection in connections do
			connection:Disconnect()
		end
		stopShop()
		stopLocale()
		stopTitles()
		screen:Destroy()
	end
end

return ShopScreen

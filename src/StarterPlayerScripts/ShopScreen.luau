--!strict
-- Lobby shop. Selecting a product changes only that preview slot. Equip is the save.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local constants = require(ReplicatedStorage.Shared.IngameConstants)
local DigitPadEffect = require(ReplicatedStorage.Shared.DigitPadEffect)
local Localization = require(ReplicatedStorage.Shared.Localization)
local PadLook = require(ReplicatedStorage.Shared.PadLook)
local PracticeRules = require(ReplicatedStorage.Shared.PracticeRules)
local ShopLayout = require(ReplicatedStorage.Shared.ShopLayout)
local ShopRules = require(ReplicatedStorage.Shared.ShopRules)
local TableData = require(ReplicatedStorage.Shared.TableData)
local TitleRules = require(ReplicatedStorage.Shared.TitleRules)
local ItemIconUtil = require(ReplicatedStorage.Shared.ItemIconUtil)
local UiChrome = require(ReplicatedStorage.Shared.UiChrome)
local ShopState = require(script.Parent.ShopState)
local TitleState = require(script.Parent.TitleState)
local TypingPad = require(script.Parent.TypingPad)

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
	local touchSink = Instance.new("TextButton")
	touchSink.Name = "TouchSink"
	touchSink.Text = ""
	touchSink.AutoButtonColor = false
	touchSink.BackgroundTransparency = 1
	touchSink.BorderSizePixel = 0
	touchSink.Size = UDim2.fromScale(1, 1)
	touchSink.Modal = true
	touchSink.Active = true
	touchSink.ZIndex = 2
	touchSink.Parent = screen

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.BackgroundColor3 = UiChrome.White
	card.BorderSizePixel = 0
	card.Active = true
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
	local colorTab = tabButton("EffectColorTab")

	local list = Instance.new("ScrollingFrame")
	list.Name = "Products"
	list.ClipsDescendants = true
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Active = true
	list.ZIndex = 5
	list.Parent = card
	local listInset = Instance.new("UIPadding")
	listInset.Name = "ListInset"
	listInset.PaddingTop = UDim.new(0, 2)
	listInset.PaddingBottom = UDim.new(0, 2)
	listInset.PaddingLeft = UDim.new(0, 2)
	listInset.PaddingRight = UDim.new(0, 2)
	listInset.Parent = list
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
	preview.Active = true
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
	local padSource = ReplicatedStorage:FindFirstChild("Pad")
	local padTemplate = if padSource ~= nil then padSource:FindFirstChild("BasePad") else nil
	local pad = if padTemplate ~= nil and padTemplate:IsA("BasePart") then padTemplate:Clone() else Instance.new("Part")
	pad.Name = "BasePad"
	pad.Anchored = true
	pad.CanCollide = false
	pad.CanTouch = false
	pad.CanQuery = false
	local previewRim = pad:FindFirstChild("Out")
	if previewRim ~= nil and previewRim:IsA("BasePart") then
		previewRim.Anchored = true
		previewRim.CanCollide = false
		previewRim.CanTouch = false
		previewRim.CanQuery = false
	end
	pad.Parent = world
	local digitLayer = Instance.new("Frame")
	digitLayer.Name = "Digits"
	digitLayer.BackgroundTransparency = 1
	digitLayer.BorderSizePixel = 0
	digitLayer.ClipsDescendants = true
	digitLayer.ZIndex = 6
	digitLayer.Visible = false
	digitLayer.Parent = card

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
	titleList.Active = true
	titleList.ZIndex = 8
	titleList.Parent = titlePanel
	titlePanel.Active = true
	local titleCards: {TextButton} = {}
	local titlesOpen = false
	local loadedTitles = TitleRules.catalog(TableData.rows("AchievementDataSheet") :: {TitleRules.Row}) or {}

	local category = "Body"
	local draft = { body = "", rim = "", effect = "", effectColor = "" }
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
		if category == "EffectColor" then
			return ShopState.effectColor()
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
		if category == "EffectColor" then
			return draft.effectColor
		end
		return draft.body
	end

	local function setDraft(id: string)
		touched = true
		if category == "Rim" then
			draft.rim = id
		elseif category == "Effect" then
			draft.effect = id
		elseif category == "EffectColor" then
			draft.effectColor = id
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
				preset = item.preset,
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

	local previewSpin = 0
	local emitClock = 0
	local digitCursor = 0
	local pointCursor = 0
	local shownPreset = ""
	local shownColor = Color3.fromRGB(255, 226, 114)
	local motion: RBXScriptConnection? = nil
	local flying: {{ label: ImageLabel, born: number, origin: Vector3, up: Vector3 }} = {}

	local function clearFlying()
		for _, fly in flying do
			fly.label.Visible = false
		end
		table.clear(flying)
	end

	local function digitLabel(): ImageLabel
		local used: {[ImageLabel]: boolean} = {}
		for _, fly in flying do
			used[fly.label] = true
		end
		for _, child in digitLayer:GetChildren() do
			if child:IsA("ImageLabel") and not used[child] then
				return child
			end
		end
		local label = Instance.new("ImageLabel")
		label.Name = "Digit"
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.ScaleType = Enum.ScaleType.Fit
		label.ZIndex = 6
		label.Parent = digitLayer
		return label
	end

	local function frameCamera(width: number, height: number)
		if width < 8 or height < 8 then
			return
		end
		local rim = pad:FindFirstChild("Out")
		local radius = if rim ~= nil and rim:IsA("BasePart") then math.max(rim.Size.Y, rim.Size.Z) * 0.5 else 5
		local focus = pad.Position + Vector3.new(0, radius * 0.55, 0)
		local direction = Vector3.new(1, 0.58, 1).Unit
		local aspect = width / height
		local vertical = math.rad(camera.FieldOfView)
		local horizontal = 2 * math.atan(math.tan(vertical * 0.5) * aspect)
		local distance = (radius * 2) / (0.65 * 2 * math.tan(horizontal * 0.5))
		camera.CFrame = CFrame.new(focus + direction * distance, focus)
	end

	local function stepPreview(dt: number)
		local rim = pad:FindFirstChild("Out")
		local rimPart = if rim ~= nil and rim:IsA("BasePart") then rim else nil
		if rimPart ~= nil then
			previewSpin -= math.rad(constants.Floor.RimRotationSpeed) * dt
			rimPart.CFrame = pad.CFrame * CFrame.Angles(previewSpin, 0, 0)
		end
		local now = os.clock()
		local view = preview.AbsoluteSize
		for index = #flying, 1, -1 do
			local fly = flying[index]
			local alpha = (now - fly.born) / DigitPadEffect.Lifetime
			if alpha >= 1 then
				fly.label.Visible = false
				table.remove(flying, index)
				continue
			end
			local world = fly.origin + fly.up * (DigitPadEffect.Rise * alpha)
			local panel = DigitPadEffect.project(world, camera.CFrame, camera.FieldOfView, view)
			if panel == nil then
				fly.label.Visible = false
				continue
			end
			fly.label.Visible = fly.label.Image ~= ""
			fly.label.Position = UDim2.fromOffset(panel.X, panel.Y)
			fly.label.ImageTransparency = alpha
			local studs = if rimPart ~= nil then math.max(0.4, rimPart.Size.Y * 0.14) else 1
			local edge = DigitPadEffect.project(world + camera.CFrame.XVector * studs, camera.CFrame, camera.FieldOfView, view)
			local pixels = if edge ~= nil then math.max(12, (edge - panel).Magnitude) else 18
			fly.label.Size = UDim2.fromOffset(pixels, pixels)
		end
		if shownPreset ~= DigitPadEffect.Id or rimPart == nil then
			return
		end
		emitClock += dt
		local interval = DigitPadEffect.interval()
		local bursts = 0
		while emitClock >= interval and bursts < 3 do
			emitClock -= interval
			bursts += 1
			digitCursor = digitCursor % DigitPadEffect.Count + 1
			pointCursor = pointCursor % DigitPadEffect.PointCount + 1
			local origin = rimPart.CFrame:PointToWorldSpace(DigitPadEffect.localPoint(rimPart.Size, pointCursor))
			local label = digitLabel()
			local offset, rect = DigitPadEffect.cell(digitCursor)
			label.Image = DigitPadEffect.image()
			label.ImageColor3 = shownColor
			label.ImageRectOffset = offset
			label.ImageRectSize = rect
			label.ImageTransparency = 0
			label.Visible = label.Image ~= ""
			table.insert(flying, {
				label = label,
				born = now,
				origin = origin,
				up = rimPart.CFrame.XVector,
			})
		end
	end

	local function setMotion(active: boolean)
		digitLayer.Visible = active
		if active then
			if motion == nil then
				motion = RunService.Heartbeat:Connect(stepPreview)
			end
			return
		end
		if motion ~= nil then
			motion:Disconnect()
			motion = nil
		end
		clearFlying()
		emitClock = 0
	end

	local function paintPreview(paint: ShopRules.Paint)
		local bodyColor = PadLook.parseColor(paint.body) or Color3.fromRGB(200, 178, 145)
		pad.Color = bodyColor
		pad.Material = Enum.Material.Asphalt
		local rim = pad:FindFirstChild("Out")
		if rim ~= nil and rim:IsA("BasePart") then
			local rimColor = if paint.rim == "none" or paint.rim == "" then nil else PadLook.parseColor(paint.rim)
			if rimColor ~= nil then
				rim.Transparency = 0
				rim.Color = rimColor
			else
				rim.Transparency = 1
			end
			local emitter = rim:FindFirstChild("ParticleEmitter")
			local digits = paint.preset == DigitPadEffect.Id
			local effectColor = if paint.effect == "none" or paint.effect == "" then nil else PadLook.parseColor(paint.effect)
			if emitter ~= nil and emitter:IsA("ParticleEmitter") then
				emitter.Enabled = effectColor ~= nil and not digits
				if effectColor ~= nil then
					emitter.Color = ColorSequence.new(effectColor)
					emitter.LightEmission = PadLook.lightEmission(effectColor)
				end
			end
		end
		local spark = pad:FindFirstChild("Spark")
		if spark ~= nil then
			spark:Destroy()
		end
		local motes = pad:FindFirstChild("PadEffect")
		if motes ~= nil then
			motes:Destroy()
		end
		if paint.preset ~= shownPreset then
			shownPreset = paint.preset
			clearFlying()
			emitClock = 0
			digitCursor = 0
			pointCursor = 0
		end
		local nextColor = if paint.preset == DigitPadEffect.Id then PadLook.parseColor(paint.effect) else nil
		if nextColor ~= nil then
			shownColor = nextColor
		end
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
		local swatch = Instance.new("Frame")
		swatch.Name = "Swatch"
		swatch.AnchorPoint = Vector2.new(0, 0.5)
		swatch.Position = UDim2.new(0, -28, 0.5, 0)
		swatch.Size = UDim2.fromOffset(22, 22)
		swatch.BorderSizePixel = 0
		swatch.ZIndex = 7
		swatch.Parent = button
		local swatchCorner = Instance.new("UICorner")
		swatchCorner.CornerRadius = UDim.new(0, 4)
		swatchCorner.Parent = swatch
		local swatchStroke = Instance.new("UIStroke")
		swatchStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		swatchStroke.Color = Color3.fromRGB(159, 175, 197)
		swatchStroke.Thickness = 1
		swatchStroke.Parent = swatch
		local slash = Instance.new("Frame")
		slash.Name = "Slash"
		slash.AnchorPoint = Vector2.new(0.5, 0.5)
		slash.Position = UDim2.fromScale(0.5, 0.5)
		slash.Size = UDim2.fromOffset(18, 2)
		slash.Rotation = 45
		slash.BorderSizePixel = 0
		slash.BackgroundColor3 = UiChrome.Navy
		slash.Visible = false
		slash.ZIndex = 8
		slash.Parent = swatch
		button.Modal = true
		button.ZIndex = 6
		button.Parent = list
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = button
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 36)
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
		local tabs = { bodyTab, rimTab, effectTab, colorTab }
		local tabWidth = math.floor((inner - plan.gap * (#tabs - 1)) / #tabs)
		for index, tab in tabs do
			tab.Position = UDim2.fromOffset(plan.margin + (index - 1) * (tabWidth + plan.gap), y)
			tab.Size = UDim2.fromOffset(tabWidth, plan.tab)
			tab.TextSize = math.clamp(plan.tab - 18, 11, 16)
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
		digitLayer.Position = preview.Position
		digitLayer.Size = preview.Size
		frameCamera(plan.preview, plan.body)
		for _, button in cards do
			button.Size = UDim2.new(1, -(list.ScrollBarThickness + 2), 0, plan.action)
			button.TextSize = math.clamp(plan.action - 16, 12, 18)
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
		titleList.Size = UDim2.fromScale(1, 1)
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
		colorTab.Text = Localization.getText("Shop.TabEffectColor")
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
		local tabs = { Body = bodyTab, Rim = rimTab, Effect = effectTab, EffectColor = colorTab }
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
			local swatch = button:FindFirstChild("Swatch")
			if swatch ~= nil and swatch:IsA("Frame") then
				local empty = item.id == "starter_rim" or item.id == "starter_effect" or item.id == "starter_effectcolor"
				local parsed = PadLook.parseColor(item.color)
				swatch.BackgroundColor3 = if parsed ~= nil then parsed else Color3.new(1, 1, 1)
				swatch.BackgroundTransparency = if empty then 1 else 0
				local slash = swatch:FindFirstChild("Slash")
				if slash ~= nil and slash:IsA("Frame") then
					slash.Visible = empty
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
		elseif item.currency == "Gold" and ShopState.gold() < item.price then
			buyButton.Text = Localization.getText("Shop.ShortGold", nil, { price = tostring(item.price) })
			buyButton.Active = false
			buyButton.AutoButtonColor = false
			buyButton:SetAttribute("Face", "short")
		else
			buyButton.Text = Localization.getText("Shop.Buy", nil, { price = item.price })
			buyButton:SetAttribute("Face", "primary")
		end
		if titlesOpen then
			buyButton.Active = false
			buyButton.AutoButtonColor = false
		end
		paintPreview(ShopRules.preview(catalog(), draft.body, draft.rim, draft.effect, draft.effectColor))
		setMotion(screen.Visible and not titlesOpen)
		titlePanel.Visible = titlesOpen
		list.Visible = not titlesOpen
		preview.Visible = not titlesOpen
		local ownedSet: {[number]: boolean} = {}
		for _, titleId in TitleState.titles() do
			ownedSet[titleId] = true
		end
		local catalogTitles = table.clone(loadedTitles)
		table.sort(catalogTitles, function(left, right)
			if left.score ~= right.score then
				return left.score < right.score
			end
			return left.id < right.id
		end)
		for index, achievement in catalogTitles do
			local button = titleCards[index]
			if button == nil then
				button = Instance.new("TextButton")
				button.Name = "TitleRow"
				button.Font = Enum.Font.GothamMedium
				button.Text = ""
				button.AutoButtonColor = false
				button.Modal = true
				button.ZIndex = 9
				button.Parent = titleList
				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(0, 6)
				corner.Parent = button
				local scoreLabel = Instance.new("TextLabel")
				scoreLabel.Name = "Score"
				scoreLabel.BackgroundTransparency = 1
				scoreLabel.Font = Enum.Font.GothamMedium
				scoreLabel.TextXAlignment = Enum.TextXAlignment.Right
				scoreLabel.TextTruncate = Enum.TextTruncate.AtEnd
				scoreLabel.ZIndex = 10
				scoreLabel.Parent = button
				local icon = Instance.new("ImageLabel")
				icon.Name = "Icon"
				icon.BackgroundTransparency = 1
				icon.ScaleType = Enum.ScaleType.Fit
				icon.ZIndex = 10
				icon.Parent = button
				local nameLabel = Instance.new("TextLabel")
				nameLabel.Name = "Name"
				nameLabel.BackgroundTransparency = 1
				nameLabel.Font = Enum.Font.GothamMedium
				nameLabel.TextXAlignment = Enum.TextXAlignment.Left
				nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
				nameLabel.ZIndex = 10
				nameLabel.Parent = button
				local mark = Instance.new("TextLabel")
				mark.Name = "Check"
				mark.BackgroundTransparency = 1
				mark.Font = Enum.Font.GothamBold
				mark.Text = ""
				mark.ZIndex = 10
				mark.Parent = button
				local box = Instance.new("Frame")
				box.Name = "Box"
				box.BackgroundTransparency = 1
				box.BorderSizePixel = 0
				box.ZIndex = 10
				box.Parent = button
				local boxStroke = Instance.new("UIStroke")
				boxStroke.Thickness = 1
				boxStroke.Parent = box
				button.Activated:Connect(function()
					if button:GetAttribute("Owned") ~= true then
						return
					end
					local picked = button:GetAttribute("TitleId")
					if type(picked) == "number" then
						TitleState.equip(picked)
					end
				end)
				titleCards[index] = button
			end
			local owned = ownedSet[achievement.id] == true
			local equipped = TitleState.equipped() == achievement.id
			button.Visible = true
			button:SetAttribute("TitleId", achievement.id)
			button:SetAttribute("Owned", owned)
			button.Size = UDim2.new(1, -8, 0, 32)
			button.Position = UDim2.fromOffset(4, (index - 1) * 36)
			button.BackgroundColor3 = if equipped then UiChrome.Blue else UiChrome.White
			local ink = if equipped then UiChrome.White else UiChrome.Navy
			local scoreLabel = button:FindFirstChild("Score")
			local icon = button:FindFirstChild("Icon")
			local nameLabel = button:FindFirstChild("Name")
			local mark = button:FindFirstChild("Check")
			local box = button:FindFirstChild("Box")
			if scoreLabel ~= nil and scoreLabel:IsA("TextLabel") then
				scoreLabel.Text = tostring(achievement.score)
				scoreLabel.TextColor3 = ink
				scoreLabel.TextSize = 13
				scoreLabel.Position = UDim2.fromOffset(6, 0)
				scoreLabel.Size = UDim2.fromOffset(52, 32)
			end
			if icon ~= nil and icon:IsA("ImageLabel") then
				ItemIconUtil.apply(icon, achievement.itemId)
				icon.Position = UDim2.fromOffset(64, 5)
				icon.Size = UDim2.fromOffset(22, 22)
			end
			if nameLabel ~= nil and nameLabel:IsA("TextLabel") then
				nameLabel.Text = Localization.getText(achievement.titleKey)
				nameLabel.TextColor3 = ink
				nameLabel.TextSize = 14
				nameLabel.Position = UDim2.fromOffset(92, 0)
				nameLabel.Size = UDim2.new(1, -128, 1, 0)
			end
			if mark ~= nil and mark:IsA("TextLabel") then
				mark.Text = if owned then "✓" else ""
				mark.TextColor3 = ink
				mark.TextSize = 16
				mark.Position = UDim2.new(1, -28, 0, 0)
				mark.Size = UDim2.fromOffset(22, 32)
			end
			if box ~= nil and box:IsA("Frame") then
				box.Visible = not owned
				box.Position = UDim2.new(1, -26, 0.5, -7)
				box.Size = UDim2.fromOffset(14, 14)
				local boxStroke = box:FindFirstChildOfClass("UIStroke")
				if boxStroke ~= nil then
					boxStroke.Color = ink
				end
			end
		end
		for index = #catalogTitles + 1, #titleCards do
			titleCards[index].Visible = false
		end
		titleList.CanvasSize = UDim2.fromOffset(0, math.max(#catalogTitles, 1) * 36)
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
			setMotion(false)
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
			setMotion(false)
		end
		screen.Visible = open
		TypingPad.holdMovement("Shop", open and UserInputService.TouchEnabled)
		if open then
			if not touched then
				draft.body = ShopState.body()
				draft.rim = ShopState.rim()
				draft.effect = ShopState.effect()
				draft.effectColor = ShopState.effectColor()
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
		elseif item.currency == "Gold" and ShopState.gold() < item.price then
			return
		else
			ShopState.buy(item.id)
		end
	end)
	titleButton.Activated:Connect(function()
		titlesOpen = not titlesOpen
		render()
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
	colorTab.Activated:Connect(function()
		titlesOpen = false
		category = "EffectColor"
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
				draft.effectColor = ShopState.effectColor()
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
		setMotion(false)
		TypingPad.holdMovement("Shop", false)
		stopShop()
		stopLocale()
		stopTitles()
		screen:Destroy()
	end
end

return ShopScreen

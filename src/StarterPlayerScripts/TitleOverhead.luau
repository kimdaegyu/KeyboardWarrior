--!strict
-- Name and title above the body. A player with no title keeps the default name.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemIconUtil = require(ReplicatedStorage.Shared.ItemIconUtil)
local Localization = require(ReplicatedStorage.Shared.Localization)
local TableData = require(ReplicatedStorage.Shared.TableData)
local TitleRules = require(ReplicatedStorage.Shared.TitleRules)

local BILLBOARD_NAME = "EquippedTitleBillboard"
local BILLBOARD_HEIGHT = 1.57
local CLEARANCE = 2
local INK = Color3.fromRGB(20, 12, 32)
local TITLE_COLOR = Color3.fromRGB(98, 234, 212)

local TitleOverhead = {}

local function catalog(): {[number]: TitleRules.Achievement}
	local loaded = TitleRules.catalog(TableData.rows("AchievementDataSheet") :: {TitleRules.Row})
	local byId: {[number]: TitleRules.Achievement} = {}
	if loaded == nil then
		return byId
	end
	for _, row in loaded do
		byId[row.id] = row
	end
	return byId
end

local titles = catalog()
local mountToken: {[Model]: number} = {}

local function findJoint(part: BasePart): Motor6D?
	for _, child in part:GetChildren() do
		if child:IsA("Motor6D") and child.Part1 == part and child.Part0 ~= nil and child.Part0:IsA("BasePart") then
			return child
		end
	end
	return nil
end

-- Rest pose only. Motor6D.Transform is the idle, walk, and head motion, so it stays out.
local function restHeadOffset(root: BasePart, head: BasePart): Vector3
	local point = Vector3.zero
	local current: BasePart? = head
	local guard = 0
	while current ~= nil and current ~= root and guard < 8 do
		guard += 1
		local joint = findJoint(current)
		if joint == nil then
			break
		end
		local part0 = joint.Part0
		if part0 == nil or not part0:IsA("BasePart") then
			break
		end
		point = (joint.C0 * joint.C1:Inverse()):PointToWorldSpace(point)
		current = part0
	end
	if current ~= root then
		return Vector3.new(0, 2, 0)
	end
	return point
end

local function clear(character: Model)
	local existing = character:FindFirstChild(BILLBOARD_NAME)
	if existing ~= nil then
		existing:Destroy()
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	end
end

local function line(name: string, text: string, color: Color3, y: number, height: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromScale(0, y)
	label.Size = UDim2.fromScale(1, height)
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeColor3 = INK
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Active = false
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 22
	limit.MinTextSize = 1
	limit.Parent = label
	return label
end

local function mount(player: Player)
	local character = player.Character
	if character == nil then
		return
	end
	clear(character)
	if character.Parent == nil then
		return
	end
	local value = player:GetAttribute(TitleRules.EQUIPPED_ATTRIBUTE)
	local titleId = if type(value) == "number" then math.floor(value) else 0
	local row = titles[titleId]
	if row == nil then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return
	end
	local head = character:FindFirstChild("Head")
	local offset = if head ~= nil and head:IsA("BasePart") then restHeadOffset(root, head) else Vector3.new(0, 2, 0)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = BILLBOARD_NAME
	billboard.Adornee = root
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0
	billboard.MaxDistance = 100
	billboard.Size = UDim2.fromScale(7, BILLBOARD_HEIGHT)
	billboard.StudsOffset = Vector3.zero
	billboard.StudsOffsetWorldSpace = Vector3.new(0, offset.Y + CLEARANCE + BILLBOARD_HEIGHT * 0.5, 0)
	billboard.Active = false
	billboard.Parent = character
	local title = Localization.getText(row.titleKey)
	if title == row.titleKey or title == "" then
		title = Localization.getText("Title.Empty")
	end
	local titleLabel = line("Title", title, TITLE_COLOR, 0, 0.54)
	titleLabel.Parent = billboard
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.BorderSizePixel = 0
	icon.ScaleType = Enum.ScaleType.Fit
	icon.AnchorPoint = Vector2.new(1, 0.5)
	icon.Active = false
	icon.Visible = ItemIconUtil.apply(icon, row.itemId)
	icon.Parent = titleLabel
	local function placeIcon()
		local bounds = titleLabel.TextBounds
		local width = titleLabel.AbsoluteSize.X
		if not icon.Visible or bounds.X <= 0 or bounds.Y <= 0 or width <= 0 then
			return
		end
		local left = (width - bounds.X) / 2
		icon.Size = UDim2.fromOffset(bounds.Y, bounds.Y)
		icon.Position = UDim2.new(0, left - 3, 0.5, 0)
	end
	titleLabel:GetPropertyChangedSignal("TextBounds"):Connect(placeIcon)
	titleLabel:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeIcon)
	placeIcon()
	task.defer(placeIcon)
	line("Name", player.DisplayName, Color3.new(1, 1, 1), 0.54, 0.46).Parent = billboard
end

local function mountWhenReady(player: Player)
	local character = player.Character
	if character == nil then
		return
	end
	local token = (mountToken[character] or 0) + 1
	mountToken[character] = token
	task.spawn(function()
		if character:FindFirstChild("HumanoidRootPart") == nil then
			character:WaitForChild("HumanoidRootPart", 8)
		end
		if character:FindFirstChild("Head") == nil then
			character:WaitForChild("Head", 8)
		end
		if mountToken[character] ~= token or player.Character ~= character or character.Parent == nil then
			return
		end
		mount(player)
	end)
end

function TitleOverhead.bind(): () -> ()
	local connections: {RBXScriptConnection} = {}
	local function watch(player: Player)
		table.insert(connections, player:GetAttributeChangedSignal(TitleRules.EQUIPPED_ATTRIBUTE):Connect(function()
			mountWhenReady(player)
		end))
		table.insert(connections, player.CharacterAdded:Connect(function()
			mountWhenReady(player)
		end))
		table.insert(connections, player.CharacterAppearanceLoaded:Connect(function()
			mountWhenReady(player)
		end))
		table.insert(connections, player.CharacterRemoving:Connect(function(character)
			mountToken[character] = (mountToken[character] or 0) + 1
			clear(character)
		end))
		if player.Character ~= nil then
			mountWhenReady(player)
		end
	end
	table.insert(connections, Players.PlayerAdded:Connect(watch))
	table.insert(connections, Players.PlayerRemoving:Connect(function(player)
		if player.Character ~= nil then
			clear(player.Character)
		end
	end))
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	local function watchPhase(state: Instance)
		table.insert(connections, state:GetAttributeChangedSignal("Phase"):Connect(function()
			for _, player in Players:GetPlayers() do
				mountWhenReady(player)
			end
		end))
	end
	local state = ReplicatedStorage:FindFirstChild("MatchState")
	if state ~= nil then
		watchPhase(state)
	else
		table.insert(connections, ReplicatedStorage.ChildAdded:Connect(function(child)
			if child.Name == "MatchState" then
				watchPhase(child)
				for _, player in Players:GetPlayers() do
					mountWhenReady(player)
				end
			end
		end))
	end
	local stopLocale = Localization.onChanged(function()
		titles = catalog()
		for _, player in Players:GetPlayers() do
			mountWhenReady(player)
		end
	end)
	return function()
		stopLocale()
		for _, connection in connections do
			connection:Disconnect()
		end
		for _, player in Players:GetPlayers() do
			if player.Character ~= nil then
				clear(player.Character)
			end
		end
	end
end

return TitleOverhead

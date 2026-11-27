--!strict
-- Puts the loading cover on screen before Shared modules or the profile response exist.
-- The solid background and the game name are parented first. Then the default cover is removed.
-- Art is applied to that same screen afterwards.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SCREEN_NAME = "LoadingScreen"
local STATUS_TEXT = "플레이어 데이터 불러오는 중"
local TITLE_TEXT = "Typing GOD"
local MARBLE = Color3.fromRGB(214, 204, 188)
local INK = Color3.fromRGB(23, 41, 69)
local PAPER = Color3.fromRGB(255, 248, 236)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function sinkAction(_name: string, _state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonStart then
		return Enum.ContextActionResult.Pass
	end
	return Enum.ContextActionResult.Sink
end

local screen = playerGui:FindFirstChild(SCREEN_NAME)
if screen == nil or not screen:IsA("ScreenGui") then
	screen = Instance.new("ScreenGui")
	screen.Name = SCREEN_NAME
	screen.Parent = playerGui
end
screen = screen :: ScreenGui
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.ClipToDeviceSafeArea = false
screen.DisplayOrder = 100000
screen.Enabled = true
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local background = screen:FindFirstChild("Background")
if background == nil or not background:IsA("Frame") then
	background = Instance.new("Frame")
	background.Name = "Background"
	background.Parent = screen
end
background = background :: Frame
background.BackgroundColor3 = MARBLE
background.BorderSizePixel = 0
background.Size = UDim2.fromScale(1, 1)

local art = background:FindFirstChild("BackgroundArt")
if art == nil or not art:IsA("ImageLabel") then
	art = Instance.new("ImageLabel")
	art.Name = "BackgroundArt"
	art.Parent = background
end
art = art :: ImageLabel
art.BackgroundTransparency = 1
art.Size = UDim2.fromScale(1, 1)
art.ScaleType = Enum.ScaleType.Crop

local title = screen:FindFirstChild("Title")
if title == nil or not title:IsA("ImageLabel") then
	title = Instance.new("ImageLabel")
	title.Name = "Title"
	title.Parent = screen
end
title = title :: ImageLabel
title.BackgroundTransparency = 1
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.fromScale(0.73, 0.30)
title.Size = UDim2.fromScale(0.40, 0.20)
title.ScaleType = Enum.ScaleType.Fit
title.Visible = false
title.ZIndex = 3

local heading = screen:FindFirstChild("TitleText")
if heading == nil or not heading:IsA("TextLabel") then
	heading = Instance.new("TextLabel")
	heading.Name = "TitleText"
	heading.Parent = screen
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
heading.Text = TITLE_TEXT
heading.ZIndex = 3
local limit = heading:FindFirstChild("TitleSize")
if limit == nil then
	local created = Instance.new("UITextSizeConstraint")
	created.Name = "TitleSize"
	created.MinTextSize = 18
	created.MaxTextSize = 72
	created.Parent = heading
end

local sink = screen:FindFirstChild("InputSink")
if sink == nil or not sink:IsA("TextButton") then
	sink = Instance.new("TextButton")
	sink.Name = "InputSink"
	sink.Parent = screen
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

local plate = screen:FindFirstChild("StatusPlate")
if plate == nil or not plate:IsA("Frame") then
	plate = Instance.new("Frame")
	plate.Name = "StatusPlate"
	plate.Parent = screen
end
plate = plate :: Frame
plate.AnchorPoint = Vector2.new(0.5, 1)
plate.Position = UDim2.new(0.5, 0, 1, -24)
plate.Size = UDim2.new(0.86, 0, 0, 44)
plate.BackgroundColor3 = INK
plate.BackgroundTransparency = 0.28
plate.BorderSizePixel = 0
plate.ZIndex = 4
if plate:FindFirstChild("Corner") == nil then
	local created = Instance.new("UICorner")
	created.Name = "Corner"
	created.CornerRadius = UDim.new(0, 8)
	created.Parent = plate
end

local status = plate:FindFirstChild("Status")
if status == nil or not status:IsA("TextLabel") then
	status = Instance.new("TextLabel")
	status.Name = "Status"
	status.Parent = plate
end
status = status :: TextLabel
status.AutoLocalize = false
status.BackgroundTransparency = 1
status.Size = UDim2.fromScale(1, 1)
status.Font = Enum.Font.GothamMedium
status.TextSize = 20
status.TextColor3 = PAPER
status.TextXAlignment = Enum.TextXAlignment.Center
status.Text = STATUS_TEXT
status.ZIndex = 5

playerGui:SetAttribute("LoadingCover", true)

pcall(function()
	ReplicatedFirst:RemoveDefaultLoadingScreen()
end)

pcall(function()
	ContextActionService:BindActionAtPriority(
		"LoadingBootstrapSink",
		sinkAction,
		false,
		Enum.ContextActionPriority.High.Value + 1000,
		Enum.UserInputType.Keyboard,
		Enum.UserInputType.MouseButton1,
		Enum.UserInputType.MouseButton2,
		Enum.UserInputType.Touch
	)
end)

task.spawn(function()
	local step = 0
	while screen.Parent ~= nil and screen:GetAttribute("PresenterOwned") ~= true do
		step += 1
		status.Text = STATUS_TEXT .. string.rep(".", (step % 3) + 1)
		task.wait(0.4)
	end
end)

task.spawn(function()
	local shared = ReplicatedStorage:WaitForChild("Shared", 8)
	if shared == nil then
		return
	end
	local moduleScript = shared:WaitForChild("LoadingArt", 8)
	if moduleScript == nil or not moduleScript:IsA("ModuleScript") then
		return
	end
	if screen:GetAttribute("PresenterOwned") == true then
		return
	end
	local ok, artModule = pcall(require, moduleScript)
	if screen:GetAttribute("PresenterOwned") == true or not ok or typeof(artModule) ~= "table" then
		return
	end
	local backgroundUrl = ""
	local titleUrl = ""
	if typeof((artModule :: any).backgroundUrl) == "function" then
		local value = (artModule :: any).backgroundUrl()
		if typeof(value) == "string" then
			backgroundUrl = value
		end
	end
	if typeof((artModule :: any).titleUrl) == "function" then
		local value = (artModule :: any).titleUrl()
		if typeof(value) == "string" then
			titleUrl = value
		end
	end
	if screen:GetAttribute("PresenterOwned") == true then
		return
	end
	if backgroundUrl ~= "" then
		art.Image = backgroundUrl
	end
	if titleUrl ~= "" then
		title.Image = titleUrl
		title.Visible = true
		title:GetPropertyChangedSignal("IsLoaded"):Connect(function()
			if title.IsLoaded then
				heading.Visible = false
			end
		end)
		if title.IsLoaded then
			heading.Visible = false
		end
	end
end)

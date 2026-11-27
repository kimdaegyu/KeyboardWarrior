--!strict
-- Shared faces for the lobby screens. Image ids and crop rects stay in the atlas modules.

local ItemIconUtil = require(script.Parent.ItemIconUtil)
local UIImageUtil = require(script.Parent.UIImageUtil)

local UiChrome = {}

UiChrome.Navy = Color3.fromRGB(23, 41, 69)
UiChrome.White = Color3.new(1, 1, 1)
UiChrome.Blue = Color3.fromRGB(36, 91, 205)
UiChrome.Yellow = Color3.fromRGB(255, 211, 74)
UiChrome.Gray = Color3.fromRGB(88, 96, 110)

function UiChrome.ink(role: string): Color3
	return if role == "selected" or role == "short" then UiChrome.White else UiChrome.Navy
end

function UiChrome.round(gui: GuiObject, radius: number?)
	gui.BorderSizePixel = 0
	local corner = gui:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 7)
	corner.Parent = gui
end

function UiChrome.paint(gui: GuiObject, role: string)
	gui.BackgroundColor3 = if role == "primary" then UiChrome.Yellow elseif role == "selected" then UiChrome.Blue elseif role == "short" then UiChrome.Gray else UiChrome.White
	gui.BackgroundTransparency = 0
	gui.BorderSizePixel = 0
	if gui:IsA("ImageLabel") or gui:IsA("ImageButton") then
		gui.Image = ""
	end
	UiChrome.round(gui)
	if not gui:FindFirstChildOfClass("UIStroke") then
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color = Color3.fromRGB(159, 175, 197)
		stroke.Thickness = 1
		stroke.Parent = gui
	end
end

function UiChrome.icon(parent: GuiObject, key: string | number): ImageLabel
	local existing = parent:FindFirstChild("Icon")
	local image = if existing ~= nil and existing:IsA("ImageLabel") then existing else Instance.new("ImageLabel")
	image.Name = "Icon"
	image.BackgroundTransparency = 1
	image.BorderSizePixel = 0
	image.Active = false
	image.ZIndex = parent.ZIndex + 2
	image.Parent = parent
	local painted = if type(key) == "number" then ItemIconUtil.apply(image, key) else UIImageUtil.apply(image, key)
	image.Visible = painted
	if painted then
		image.ScaleType = Enum.ScaleType.Fit
		image.ImageColor3 = Color3.new(1, 1, 1)
	end
	return image
end

function UiChrome.closeButton(parent: GuiObject): TextButton
	local button = Instance.new("TextButton")
	button.Name = "Close"
	button.Text = "X"
	button.Font = Enum.Font.GothamBold
	button.TextSize = 20
	button.TextColor3 = UiChrome.Navy
	button.AnchorPoint = Vector2.new(1, 0)
	button.ZIndex = parent.ZIndex + 5
	UiChrome.paint(button, "panel")
	button.Parent = parent
	return button
end

return UiChrome

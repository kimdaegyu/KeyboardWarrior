--!strict
-- Shared faces for the lobby screens. Image ids and crop rects stay in the atlas modules.

local ItemIconUtil = require(script.Parent.ItemIconUtil)
local UIImageUtil = require(script.Parent.UIImageUtil)

local UiChrome = {}

UiChrome.Navy = Color3.fromRGB(23, 41, 69)
UiChrome.White = Color3.new(1, 1, 1)
UiChrome.Blue = Color3.fromRGB(36, 91, 205)
UiChrome.Yellow = Color3.fromRGB(255, 211, 74)

function UiChrome.ink(role: string): Color3
	if role == "selected" then
		return UiChrome.White
	end
	return UiChrome.Navy
end

function UiChrome.paint(gui: GuiObject, role: string)
	gui.BackgroundColor3 = if role == "primary" then UiChrome.Yellow elseif role == "selected" then UiChrome.Blue else UiChrome.White
	gui.BackgroundTransparency = 0
	gui.BorderSizePixel = 0
	if gui:IsA("ImageLabel") or gui:IsA("ImageButton") then
		gui.Image = ""
	end
	if not gui:FindFirstChildOfClass("UICorner") then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 7)
		corner.Parent = gui
	end
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

return UiChrome

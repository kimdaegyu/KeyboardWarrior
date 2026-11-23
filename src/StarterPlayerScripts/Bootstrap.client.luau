--!strict
local Players = game:GetService("Players")
local shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local layout = require(script.Parent.Layout)
local lobbyHud = require(script.Parent.LobbyHud)
local typingScreen = require(script.Parent.TypingScreen)
local gui = Instance.new("ScreenGui")
gui.Name = "KeyboardWarriorUI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
local root = Instance.new("Frame")
root.Name = "SafeRoot"
root.Size = UDim2.fromScale(1, 1)
root.BackgroundTransparency = 1
root.Parent = gui
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
local resize = layout.bind(root)
local stopHud = lobbyHud.bind(root)
local stopTyping = typingScreen.bind(root)
gui.Destroying:Once(function()
	resize:Disconnect()
	stopHud()
	stopTyping()
end)

-- Enable the Studio-only preview with a boolean Workspace attribute before Play.
if game:GetService("RunService"):IsStudio() and workspace:GetAttribute("PreviewCoreUI") then
	local panel = Instance.new("ImageLabel")
	panel.Name = "PanelPreview"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.5, 0.3)
	panel.BackgroundTransparency = 1
	require(shared.UIImageUtil).apply(panel, "panel-9slice")
	panel.Parent = root
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.Parent = panel
	require(shared.Localization).bind(label, "Common.Ready", nil, "Ready")
end

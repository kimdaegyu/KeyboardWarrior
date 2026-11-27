--!strict
-- Studio-only cheat window. F7 shows and hides it. The server writes the profile.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Localization = require(ReplicatedStorage.Shared.Localization)
local UiChrome = require(ReplicatedStorage.Shared.UiChrome)

local CheatScreen = {}

local STATUS_KEYS = {
	done = "Cheat.Done",
	invalid = "Cheat.Invalid",
	failed = "Cheat.Failed",
	unavailable = "Cheat.Unavailable",
}

local function text(key: string, fallback: string): string
	local value = Localization.getText(key)
	if value == nil or value == "" or value == key then
		return fallback
	end
	return value
end

local function field(parent: Frame, name: string, placeholder: string, editable: boolean): TextBox
	local box = Instance.new("TextBox")
	box.Name = name
	box.ClearTextOnFocus = false
	box.TextEditable = editable
	box.Text = ""
	box.PlaceholderText = placeholder
	box.PlaceholderColor3 = Color3.fromRGB(120, 138, 162)
	box.Font = Enum.Font.GothamMedium
	box.TextSize = 16
	box.TextColor3 = UiChrome.Navy
	box.TextXAlignment = Enum.TextXAlignment.Center
	box.Size = UDim2.fromScale(0.22, 1)
	UiChrome.paint(box, "panel")
	box.Parent = parent
	return box
end

function CheatScreen.bind(root: Frame): () -> ()
	if not RunService:IsStudio() then
		return function() end
	end
	local found = ReplicatedStorage:WaitForChild("CheatRequest", 8)
	if found == nil or not found:IsA("RemoteEvent") then
		return function() end
	end
	local remote = found

	local panel = Instance.new("Frame")
	panel.Name = "Cheat"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundTransparency = 0
	panel.Visible = false
	panel.ZIndex = 40
	UiChrome.paint(panel, "panel")
	panel.Parent = root

	local header = Instance.new("TextLabel")
	header.Name = "Title"
	header.BackgroundTransparency = 1
	header.Font = Enum.Font.GothamBold
	header.TextSize = 20
	header.TextColor3 = UiChrome.Navy
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Size = UDim2.new(1, -24, 0, 32)
	header.Position = UDim2.fromOffset(12, 8)
	header.ZIndex = 41
	header.Parent = panel

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.BackgroundTransparency = 1
	status.Font = Enum.Font.GothamMedium
	status.TextSize = 15
	status.TextColor3 = UiChrome.Navy
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.Text = ""
	status.Size = UDim2.new(1, -24, 0, 22)
	status.Position = UDim2.new(0, 12, 1, -30)
	status.ZIndex = 41
	status.Parent = panel

	local boxes: {TextBox} = {}

	local function row(name: string, titleKey: string, titleFallback: string, usesParameter1: boolean, action: string): Frame
		local line = Instance.new("Frame")
		line.Name = name
		line.BackgroundTransparency = 1
		line.Size = UDim2.new(1, -24, 0, 36)
		line.ZIndex = 41
		line.Parent = panel

		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.GothamBold
		title.TextSize = 16
		title.TextColor3 = UiChrome.Navy
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextTruncate = Enum.TextTruncate.AtEnd
		title.Size = UDim2.fromScale(0.34, 1)
		title.ZIndex = 42
		title.Parent = line

		local parameter1 = field(line, "Parameter1", "", usesParameter1)
		parameter1.Position = UDim2.fromScale(0.34, 0)
		local parameter2 = field(line, "Parameter2", "", false)
		parameter2.Position = UDim2.fromScale(0.57, 0)
		table.insert(boxes, parameter1)
		table.insert(boxes, parameter2)

		local button = Instance.new("TextButton")
		button.Name = "Run"
		button.Font = Enum.Font.GothamBold
		button.TextSize = 16
		button.TextColor3 = UiChrome.Navy
		button.Size = UDim2.fromScale(0.18, 1)
		button.Position = UDim2.fromScale(0.80, 0)
		button.ZIndex = 42
		UiChrome.paint(button, "primary")
		button.Parent = line
		button.Activated:Connect(function()
			status.Text = ""
			if action == "gold" then
				remote:FireServer("gold", parameter1.Text)
			else
				remote:FireServer("reset")
			end
		end)

		local function fill()
			title.Text = text(titleKey, titleFallback)
			button.Text = text("Cheat.Run", "실행")
			parameter1.PlaceholderText = if usesParameter1 then text("Cheat.Param1", "파라미터1") else text("Cheat.Unused", "사용 안 함")
			parameter2.PlaceholderText = text("Cheat.Unused", "사용 안 함")
		end
		fill()
		line:SetAttribute("Fill", 0)
		line:GetAttributeChangedSignal("Fill"):Connect(fill)
		return line
	end

	local resetRow = row("Reset", "Cheat.Reset", "모든 데이터 초기화", false, "reset")
	local goldRow = row("Gold", "Cheat.Gold", "골드 변경", true, "gold")
	resetRow.Position = UDim2.fromOffset(12, 48)
	goldRow.Position = UDim2.fromOffset(12, 96)

	local function fillHeader()
		header.Text = text("Cheat.Window", "치트")
		for _, line in { resetRow, goldRow } do
			line:SetAttribute("Fill", (line:GetAttribute("Fill") :: number) + 1)
		end
	end
	fillHeader()

	local function place()
		local width = math.clamp(root.AbsoluteSize.X - 24, 320, 560)
		panel.Size = UDim2.fromOffset(width, 168)
	end
	place()

	local function hideFocus()
		for _, box in boxes do
			if box:IsFocused() then
				box:ReleaseFocus()
			end
		end
	end

	local input = UserInputService.InputBegan:Connect(function(inputObject: InputObject)
		if inputObject.UserInputType ~= Enum.UserInputType.Keyboard or inputObject.KeyCode ~= Enum.KeyCode.F7 then
			return
		end
		panel.Visible = not panel.Visible
		if panel.Visible then
			fillHeader()
		else
			hideFocus()
		end
	end)
	local result = remote.OnClientEvent:Connect(function(message: any)
		local code = if type(message) == "table" then message.code else nil
		local key = if type(code) == "string" then STATUS_KEYS[code] else nil
		if key == nil then
			status.Text = text("Cheat.Failed", "실패")
			return
		end
		local fallbacks = {
			["Cheat.Done"] = "완료",
			["Cheat.Invalid"] = "값을 확인해 주세요",
			["Cheat.Failed"] = "실패",
			["Cheat.Unavailable"] = "프로필을 열 수 없습니다",
		}
		status.Text = text(key, fallbacks[key] or "실패")
	end)
	local resized = root:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)

	return function()
		input:Disconnect()
		result:Disconnect()
		resized:Disconnect()
		panel:Destroy()
	end
end

return CheatScreen

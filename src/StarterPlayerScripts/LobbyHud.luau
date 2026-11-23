--!strict
-- Left lobby HUD. The clock is the server phase end, not a local countdown.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local constants = require(ReplicatedStorage.Shared.IngameConstants)
local Localization = require(ReplicatedStorage.Shared.Localization)
local UIImageUtil = require(ReplicatedStorage.Shared.UIImageUtil)

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
	local panel = Instance.new("ImageLabel")
	panel.Name = "LobbyHud"
	panel.AnchorPoint = Vector2.new(0, 0)
	panel.Position = UDim2.fromOffset(12, 12)
	panel.BackgroundColor3 = Color3.fromRGB(40, 20, 70)
	panel.BackgroundTransparency = 0.2
	panel.BorderSizePixel = 0
	panel.ScaleType = Enum.ScaleType.Fit
	panel.ZIndex = 2
	panel.Parent = root
	if UIImageUtil.apply(panel, "panel-9slice") then
		panel.BackgroundTransparency = 1
	else
		panel.BackgroundTransparency = 0.15
	end

	local padding = Instance.new("UIPadding")
	padding.Parent = panel
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = panel

	local function label(name: string, order: number, color: Color3): TextLabel
		local text = Instance.new("TextLabel")
		text.Name = name
		text.LayoutOrder = order
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.GothamMedium
		text.TextXAlignment = Enum.TextXAlignment.Left
		text.TextYAlignment = Enum.TextYAlignment.Center
		text.TextColor3 = color
		text.TextWrapped = true
		text.Text = ""
		text.Parent = panel
		return text
	end

	local phaseLabel = label("Phase", 1, Color3.fromRGB(90, 230, 255))
	local timeLabel = label("Time", 2, Color3.new(1, 1, 1))
	local waitingLabel = label("Waiting", 3, Color3.fromRGB(210, 210, 220))
	local queueLabel = label("Queue", 4, Color3.new(1, 1, 1))

	local function applyLayout()
		local compact = root:GetAttribute("Compact") == true
		local touch = root:GetAttribute("TouchTarget")
		local target = if type(touch) == "number" then touch else (if compact then constants.UI.CompactTouchTarget else constants.UI.TouchTarget)
		local inset = if compact then 8 else 12
		local gap = if compact then 2 else 4
		local textSize = math.clamp(math.floor(target * 0.5), 14, 22)
		local width = if compact then 200 else 240
		local available = root.AbsoluteSize.X
		if available > 0 then
			width = math.min(width, math.max(168, available - inset * 2))
		end
		padding.PaddingTop = UDim.new(0, inset)
		padding.PaddingBottom = UDim.new(0, inset)
		padding.PaddingLeft = UDim.new(0, inset)
		padding.PaddingRight = UDim.new(0, inset)
		list.Padding = UDim.new(0, gap)
		local row = textSize + 6
		panel.Position = UDim2.fromOffset(inset, inset)
		panel.AutomaticSize = Enum.AutomaticSize.None
		panel.Size = UDim2.fromOffset(width, inset * 2 + row * 4 + gap * 3)
		for _, child in { phaseLabel, timeLabel, waitingLabel, queueLabel } do
			child.Size = UDim2.new(1, 0, 0, row)
			child.TextSize = textSize
			child.ZIndex = 3
		end
		phaseLabel.TextSize = textSize + 2
	end
	applyLayout()

	local function render()
		local folder = ReplicatedStorage:FindFirstChild("MatchState")
		local phaseName = if folder ~= nil then folder:GetAttribute("Phase") else nil
		local phaseKey = if type(phaseName) == "string" then PHASE_KEYS[phaseName] else nil
		phaseLabel.Text = if phaseKey ~= nil then Localization.getText(phaseKey) else Localization.getText("Lobby.Pending")

		local endsAt = if folder ~= nil then folder:GetAttribute("PhaseEndsAt") else nil
		local remain = 0
		if type(endsAt) == "number" then
			remain = math.max(0, endsAt - Workspace:GetServerTimeNow())
		end
		timeLabel.Text = Localization.getText("Lobby.TimeLeft", nil, { time = formatTime(remain) })

		local waiting = Players.LocalPlayer:GetAttribute("InJoinZone") == true
		waitingLabel.Text = Localization.getText(if waiting then "Lobby.Waiting" else "Lobby.NotWaiting")
		waitingLabel.TextColor3 = if waiting then Color3.fromRGB(255, 220, 120) else Color3.fromRGB(210, 210, 220)

		local waitingCount = if folder ~= nil then folder:GetAttribute("WaitingCount") else 0
		if type(waitingCount) ~= "number" then
			waitingCount = 0
		end
		queueLabel.Text = Localization.getText("Lobby.Queue", nil, {
			count = waitingCount,
			capacity = CAPACITY,
		})

		local playing = phaseName == "Play" and Players.LocalPlayer:GetAttribute("InMatch") == true
		panel.Visible = not playing
	end
	render()

	local connections = {
		root:GetAttributeChangedSignal("Compact"):Connect(applyLayout),
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

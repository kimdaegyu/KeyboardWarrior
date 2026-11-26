--!strict
local TextService = game:GetService("TextService")
local Players = game:GetService("Players")
local shared = game:GetService("ReplicatedStorage").Shared
local UiChrome = require(shared.UiChrome)
local Localization = require(shared.Localization)
local TableData = require(shared.TableData)
local RewardRules = require(shared.RewardRules)
local Layout = require(script.Parent.Layout)

local EMPHASIS_SCALE = 1.7
local LobbyPlayerStats = {}

function LobbyPlayerStats.bind(panel: Frame, root: Frame): () -> ()
	local player = Players.LocalPlayer
	local levels = RewardRules.levelsFromRows(TableData.rows("LevelDataSheet"))
	local card = Instance.new("Frame")
	card.Name = "PlayerStats"
	UiChrome.paint(card, "panel")
	card.Parent = panel

	local function label(name: string, alignment: Enum.TextXAlignment): (TextLabel, UITextSizeConstraint)
		local item = Instance.new("TextLabel")
		item.Name = name
		item.Font = Enum.Font.GothamBold
		item.TextColor3 = UiChrome.Navy
		item.TextXAlignment = alignment
		item.BackgroundTransparency = 1
		item.TextScaled = true
		item.TextWrapped = false
		item.Text = ""
		local font = Instance.new("UITextSizeConstraint")
		font.MinTextSize = 10
		font.MaxTextSize = 40
		font.Parent = item
		item.Parent = card
		return item, font
	end

	local center = Enum.TextXAlignment.Center
	local level, levelFont = label("Level", center)
	level.BackgroundTransparency = 0
	level.BackgroundColor3 = UiChrome.Blue
	level.TextColor3 = UiChrome.White
	UiChrome.round(level, 5)
	local exp, expFont = label("Experience", center)
	local gold, goldFont = label("Gold", Enum.TextXAlignment.Left)
	local boost, boostFont = label("FriendBoost", center)
	boost.BackgroundTransparency = 0
	boost.BackgroundColor3 = Color3.fromRGB(234, 241, 255)
	boost.TextColor3 = UiChrome.Blue
	UiChrome.round(boost, 5)
	local coin = UiChrome.icon(card, 1)
	local divider = Instance.new("Frame")
	divider.Name = "GoldDivider"
	divider.BorderSizePixel = 0
	divider.BackgroundColor3 = Color3.fromRGB(215, 228, 250)
	divider.Parent = card

	local function render()
		local size = root.AbsoluteSize
		if size.X < 100 or size.Y < 100 then return end
		local metrics = Layout.metrics(size)
		local pad = 4
		local width = math.clamp(math.round(size.X * 0.19), 138, 240)
		local row = math.clamp(math.floor(size.Y * 0.084), 18, 39)
		local percent = player:GetAttribute("FriendBoostPercent") or 0
		boost.Visible = percent > 0
		boost.Text = if boost.Visible then Localization.getText("Lobby.FriendBoost", nil, {percent = percent}) else ""
		local expTotal = player:GetAttribute("ProfileExp")
		local balance = player:GetAttribute("ProfileGold")
		local ready = type(expTotal) == "number" and type(balance) == "number" and #levels > 0
		card.Visible = ready
		if not ready then return end
		local number, floorExp, nextExp = RewardRules.progress(expTotal, levels)
		level.Text = Localization.getText("Result.Level", nil, {level = number})
		exp.Text = if nextExp then `{expTotal - floorExp}/{nextExp - floorExp} XP` else `{expTotal} XP`
		gold.Text = tostring(balance)

		local gap = 4
		local oldIcon = math.round((row - 6) * EMPHASIS_SCALE)
		local oldGoldHeight = math.max(row, oldIcon + 2)
		local goldHeight = math.round(oldGoldHeight * 0.8)
		local headerHeight = math.round((3 * row - oldGoldHeight) * 0.8)
		local iconSize = math.min(oldIcon, goldHeight - 2)
		local textSize = metrics.hudTextSize
		for _, constraint in {levelFont, expFont, goldFont, boostFont} do
			constraint.MaxTextSize = textSize
		end
		-- Give both values enough width at the same font size as the Waiting row.
		local function textWidth(item: TextLabel): number
			return math.ceil(TextService:GetTextSize(item.Text, textSize, item.Font, Vector2.new(10000, 1000)).X) + 6
		end
		local levelWidth = textWidth(level)
		width = math.min(math.floor(size.X * 0.45), math.max(width, pad * 2 + gap + levelWidth + textWidth(exp)))
		local inner = width - 2 * pad
		levelWidth = math.clamp(inner - gap - textWidth(exp), math.floor(inner * 0.40), math.max(1, inner - gap))
		local goldY = pad + headerHeight
		local baseHeight = pad * 2 + headerHeight + goldHeight
		card.Position = UDim2.fromOffset(metrics.margin, metrics.statusTop)
		card.Size = UDim2.fromOffset(width, baseHeight + (if boost.Visible then row else 0))

		-- Use the actual HUD size for normal values; allow fitting only on overflow.
		local function setFont(item: TextLabel, availableWidth: number)
			item.TextSize = textSize
			item.TextScaled = textWidth(item) > availableWidth
		end
		setFont(level, levelWidth)
		setFont(exp, inner - levelWidth - gap)
		setFont(gold, inner - iconSize - gap)
		setFont(boost, inner)
		level.Position = UDim2.fromOffset(pad, pad)
		level.Size = UDim2.fromOffset(levelWidth, headerHeight - 3)
		exp.Position = UDim2.fromOffset(pad + levelWidth + gap, pad)
		exp.Size = UDim2.fromOffset(inner - levelWidth - gap, headerHeight - 3)
		divider.Position = UDim2.fromOffset(pad, goldY - 1)
		divider.Size = UDim2.fromOffset(inner, 1)
		coin.Position = UDim2.fromOffset(pad, goldY + math.floor((goldHeight - iconSize) / 2))
		coin.Size = UDim2.fromOffset(iconSize, iconSize)
		gold.Position = UDim2.fromOffset(pad + iconSize + gap, goldY)
		gold.Size = UDim2.fromOffset(inner - iconSize - gap, goldHeight)
		boost.Position = UDim2.fromOffset(pad, goldY + goldHeight)
		boost.Size = UDim2.fromOffset(inner, row - 2)
	end
	local connections = {
		root:GetPropertyChangedSignal("AbsoluteSize"):Connect(render),
		player:GetAttributeChangedSignal("ProfileGold"):Connect(render),
		player:GetAttributeChangedSignal("ProfileExp"):Connect(render),
		player:GetAttributeChangedSignal("FriendBoostPercent"):Connect(render),
	}
	local stopLocale = Localization.onChanged(render)
	render()
	return function()
		for _, connection in connections do connection:Disconnect() end
		stopLocale()
		card:Destroy()
	end
end

return LobbyPlayerStats

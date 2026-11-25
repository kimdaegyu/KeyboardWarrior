--!strict
local UiChrome = require(game:GetService("ReplicatedStorage").Shared.UiChrome)
local ShopState = require(script.Parent.ShopState)

local ProfileBar = {}

function ProfileBar.bind(header: Frame)
	ShopState.start()
	local function label(name: string, color: Color3, parent: Instance): TextLabel
		local text = Instance.new("TextLabel")
		text.Name = name
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.GothamMedium
		text.TextColor3 = color
		text.TextXAlignment = Enum.TextXAlignment.Left
		text.TextYAlignment = Enum.TextYAlignment.Center
		text.TextTruncate = Enum.TextTruncate.AtEnd
		text.ZIndex = 6
		text.Parent = parent
		return text
	end

	local brand = label("Brand", UiChrome.Blue, header)
	brand.Text = "KEYBOARD WARRIOR"
	brand.FontFace = Font.new(Font.fromEnum(Enum.Font.GothamBold).Family, Enum.FontWeight.Heavy, Enum.FontStyle.Italic)
	local level = label("Level", UiChrome.Navy, header)
	local gold = label("Gold", UiChrome.Navy, header)
	level.TextXAlignment = Enum.TextXAlignment.Right
	gold.TextXAlignment = Enum.TextXAlignment.Right
	local logo = UiChrome.icon(header, "Practice")
	local coin = UiChrome.icon(header, 1)
	local function showBalance()
		local value = ShopState.level()
		local ready = ShopState.received() and ShopState.status() == "ready"
		level.Text = if ready and value then "Lv. " .. tostring(value) else "Lv. —"
		local digits = tostring(ShopState.gold())
		local groups = digits:reverse():gsub("(%d%d%d)", "%1,")
		local formatted = groups:reverse():gsub("^,", "")
		gold.Text = if ready then formatted else "—"
	end

	local disconnect = ShopState.onChanged(showBalance)
	local function refresh()
		showBalance()
		ShopState.request()
	end
	local function layout(sizeX: number, sizeY: number, pad: number, height: number): number
		local headerInset = math.max(6, math.round(sizeX * 0.026))
		local headerTop = math.max(3, math.round(sizeY * 0.024))
		local headerWidth = sizeX - headerInset * 2
		header.Position = UDim2.fromOffset(headerInset, headerTop)
		header.Size = UDim2.fromOffset(headerWidth, height)
		local badge = math.floor(height * 0.53)
		local function box(obj: GuiObject, x: number, y: number, w: number, h: number)
			obj.Position = UDim2.fromOffset(x, y)
			obj.Size = UDim2.fromOffset(w, h)
		end
		local baseline = math.floor((height - badge) / 2)
		local numberWidth = math.max(60, badge * 3)
		box(logo, pad, baseline, badge, badge)
		box(brand, pad + badge + 8, 0, headerWidth - 2 * pad - 2 * numberWidth - 2 * badge - 20, height)
		box(gold, headerWidth - pad - numberWidth, 0, numberWidth, height)
		box(coin, headerWidth - pad - numberWidth - badge, baseline, badge, badge)
		box(level, headerWidth - pad - numberWidth * 2 - badge - 8, 0, numberWidth, height)
		brand.TextSize = math.clamp(badge, 14, 35)
		level.TextSize = math.clamp(badge * 0.73, 13, 25)
		gold.TextSize = level.TextSize

		return headerTop + height
	end
	return { refresh = refresh, layout = layout, disconnect = disconnect }
end

return ProfileBar

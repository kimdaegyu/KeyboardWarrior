--!strict
local input = game:GetService("UserInputService")
local ui = require(game:GetService("ReplicatedStorage").Shared.IngameConstants).UI

local Layout = {}

function Layout.metrics(size: Vector2)
	local compact = size.Y <= ui.CompactHeight or size.X <= ui.CompactWidth
	local statusHeight = math.min(if compact then 90 else 116, math.floor(size.Y * 0.36))
	return {
		statusHeight = statusHeight,
		statusTop = math.round(size.Y * 0.40 - statusHeight / 2),
		hudTextSize = math.clamp(math.floor((statusHeight * 0.29 - 4) * 0.88), 14, 28),
		compact = compact,
		contentWidth = math.min(size.X, ui.MaxContentWidth),
		margin = math.clamp(math.round(size.Y * 0.02), 6, 20),
		target = if compact then ui.CompactTouchTarget else ui.TouchTarget,
	}
end

function Layout.bind(root: Frame)
	local function resize()
		local metrics = Layout.metrics(root.AbsoluteSize)
		root:SetAttribute("Compact", metrics.compact)
		root:SetAttribute("ContentWidth", metrics.contentWidth)
		root:SetAttribute("TouchTarget", metrics.target)
	end
	local function updateInput()
		local touch = input.TouchEnabled and (input.PreferredInput == Enum.PreferredInput.Touch or not input.KeyboardEnabled)
		root:SetAttribute("TouchControls", touch)
	end
	resize()
	updateInput()
	local connections = {
		root:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize),
		input:GetPropertyChangedSignal("PreferredInput"):Connect(updateInput),
		input:GetPropertyChangedSignal("KeyboardEnabled"):Connect(updateInput),
		input:GetPropertyChangedSignal("TouchEnabled"):Connect(updateInput),
	}
	return function()
		for _, connection in connections do connection:Disconnect() end
	end
end

return Layout

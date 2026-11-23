--!strict
local ui = require(game:GetService("ReplicatedStorage").Shared.IngameConstants).UI

local Layout = {}
function Layout.bind(root: Frame)
	local function resize()
		local size = root.AbsoluteSize
		local compact = size.Y <= ui.CompactHeight or size.X <= ui.CompactWidth
		root:SetAttribute("Compact", compact)
		root:SetAttribute("ContentWidth", math.min(size.X, ui.MaxContentWidth))
		root:SetAttribute("TouchTarget", if compact then ui.CompactTouchTarget else ui.TouchTarget)
	end
	resize()
	return root:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
end
return Layout

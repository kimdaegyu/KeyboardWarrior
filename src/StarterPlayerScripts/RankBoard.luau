--!strict
-- Localizes the shared lobby board. Row values stay on the server snapshot.

local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Localization = require(ReplicatedStorage.Shared.Localization)

local RankBoard = {}

local function locate(): SurfaceGui?
	local folder = Workspace:FindFirstChild("Rank")
	local part = if folder ~= nil then folder:FindFirstChild("Rank") else nil
	local gui = if part ~= nil then part:FindFirstChild("SurfaceGui") else nil
	if gui ~= nil and gui:IsA("SurfaceGui") then
		return gui
	end
	return nil
end

local function apply(board: Instance)
	for _, child in board:GetDescendants() do
		if child:IsA("TextLabel") then
			local key = child:GetAttribute("TextKey")
			if type(key) == "string" then
				child.Text = Localization.getText(key)
			end
			local rank = child:GetAttribute("Rank")
			if child.Name == "Place" and type(rank) == "number" then
				child.Text = Localization.getText("Rank.Ordinal", nil, { rank = rank })
			end
		end
	end
end

function RankBoard.bind(): () -> ()
	local alive = true
	local board: Instance? = nil
	local function refresh()
		if board ~= nil and board.Parent ~= nil then
			apply(board)
		end
	end
	local stopLocale = Localization.onChanged(refresh)
	task.spawn(function()
		while alive do
			local gui = locate()
			local nextBoard = if gui ~= nil then gui:FindFirstChild("Board") else nil
			if nextBoard ~= nil and nextBoard ~= board then
				board = nextBoard
				refresh()
			elseif nextBoard ~= nil then
				refresh()
			end
			task.wait(1)
		end
	end)
	return function()
		alive = false
		stopLocale()
	end
end

return RankBoard

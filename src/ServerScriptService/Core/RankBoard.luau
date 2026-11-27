--!strict
-- Lobby Top 10 board. It reads RankService.board and does not query stores itself.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Localization = require(ReplicatedStorage.Shared.Localization)
local RankRules = require(ReplicatedStorage.Shared.RankRules)
local RankService = require(script.Parent.RankService)

local NAVY = Color3.fromRGB(10, 24, 48)
local BLUE = Color3.fromRGB(15, 55, 145)
local LINE = Color3.fromRGB(215, 228, 250)
local MISSING = "—"
local DEFAULT_FACE = "rbxasset://textures/ui/GuiImagePlaceholder.png"
local BODY_OF_FACE = 0.65
local MIN_CANVAS_HEIGHT = 1100
local TITLE_BAND = 0.07
local HEADER_BAND = 0.05
local ROWS_TOP = 0.146
local ROWS_BAND = 0.84
local FACE_OF_ROW = 0.84

local RankBoard = {}
local started = false
local faces: {[number]: string} = {}
local painted: SurfaceGui? = nil

local function text(key: string): string
	local value = Localization.getText(key)
	return if value == key then key else value
end

local function formatScore(score: number): string
	local digits = tostring(math.floor(score)):reverse():gsub("(%d%d%d)", "%1,")
	return (digits:reverse():gsub("^,", ""))
end

local function locate(): SurfaceGui?
	local folder = Workspace:FindFirstChild("Rank")
	local part = if folder ~= nil then folder:FindFirstChild("Rank") else nil
	local gui = if part ~= nil then part:FindFirstChild("SurfaceGui") else nil
	if gui ~= nil and gui:IsA("SurfaceGui") then
		return gui
	end
	return nil
end

local function faceStuds(part: BasePart, face: Enum.NormalId): (number, number)
	local size = part.Size
	if face == Enum.NormalId.Left or face == Enum.NormalId.Right then
		return size.Z, size.Y
	end
	if face == Enum.NormalId.Top or face == Enum.NormalId.Bottom then
		return size.X, size.Z
	end
	return size.X, size.Y
end

-- Pixel sizes follow the canvas. Raising PixelsPerStud or CanvasSize scales the
-- glyphs by the same ratio, so they stay the same size at the same distance.
local function prepareCanvas(gui: SurfaceGui): Vector2
	local parent = gui.Parent
	local part = if parent ~= nil and parent:IsA("BasePart") then parent else nil
	if gui.SizingMode == Enum.SurfaceGuiSizingMode.PixelsPerStud and part ~= nil then
		local widthStuds, heightStuds = faceStuds(part, gui.Face)
		local pps = gui.PixelsPerStud
		if heightStuds > 0 and heightStuds * pps < MIN_CANVAS_HEIGHT then
			pps = math.min(1000, MIN_CANVAS_HEIGHT / heightStuds)
			gui.PixelsPerStud = pps
		end
		return Vector2.new(math.max(widthStuds * pps, 1), math.max(heightStuds * pps, 1))
	end
	local canvas = gui.AbsoluteSize
	if canvas.Y < 2 then
		canvas = gui.CanvasSize
	end
	if canvas.Y > 0 and canvas.Y < MIN_CANVAS_HEIGHT and gui.SizingMode == Enum.SurfaceGuiSizingMode.FixedSize then
		local scale = MIN_CANVAS_HEIGHT / canvas.Y
		canvas = Vector2.new(canvas.X * scale, canvas.Y * scale)
		gui.CanvasSize = canvas
	end
	return Vector2.new(math.max(canvas.X, 1), math.max(canvas.Y, 1))
end

local function label(parent: Instance, name: string, font: Enum.Font, color: Color3, textSize: number): TextLabel
	local item = Instance.new("TextLabel")
	item.Name = name
	item.BackgroundTransparency = 1
	item.BorderSizePixel = 0
	item.Font = font
	item.TextColor3 = color
	item.TextScaled = false
	item.TextSize = textSize
	item.TextWrapped = false
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.TextYAlignment = Enum.TextYAlignment.Center
	item.TextTruncate = Enum.TextTruncate.AtEnd
	item.Active = false
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = textSize
	limit.MinTextSize = textSize
	limit.Parent = item
	item.Parent = parent
	return item
end

local function mount(gui: SurfaceGui)
	local existing = gui:FindFirstChild("Board")
	if existing ~= nil then
		existing:Destroy()
	end
	gui.LightInfluence = 0
	gui.ClipsDescendants = true
	local backdrop = gui:FindFirstChild("Frame")
	if backdrop ~= nil and backdrop:IsA("GuiObject") then
		backdrop.BackgroundTransparency = 1
	end
	local canvas = prepareCanvas(gui)
	local rowPx = canvas.Y * ROWS_BAND * 0.1
	local rowWidthPx = canvas.X * 0.96
	local facePx = math.min(rowPx * FACE_OF_ROW, rowWidthPx * 0.10)
	local bodyPx = math.max(1, math.floor(facePx * BODY_OF_FACE + 0.5))
	local headerPx = math.max(1, math.min(bodyPx, math.floor(canvas.Y * HEADER_BAND * 0.9 + 0.5)))
	local titlePx = math.max(bodyPx, math.min(math.floor(bodyPx * 1.25 + 0.5), math.floor(canvas.Y * TITLE_BAND * 0.88 + 0.5)))
	local faceWidth = math.clamp((facePx * 1.2) / rowWidthPx, 0.05, 0.12)
	local placeWidth = 0.08
	local rest = 1 - placeWidth - faceWidth
	local columns = {
		{ name = "Place", key = "Rank.Place", width = placeWidth, font = Enum.Font.GothamBold },
		{ name = "Face", key = "", width = faceWidth, font = Enum.Font.GothamMedium },
		{ name = "Name", key = "Rank.Board.Name", width = rest * 0.46, font = Enum.Font.GothamMedium },
		{ name = "Score", key = "Rank.Score", width = rest * 0.24, font = Enum.Font.GothamBold },
		{ name = "Cpm", key = "Rank.Cpm", width = rest * 0.17, font = Enum.Font.GothamMedium },
		{ name = "Language", key = "Rank.Language", width = rest * 0.13, font = Enum.Font.GothamMedium },
	}
	local board = Instance.new("Frame")
	board.Name = "Board"
	board.Size = UDim2.fromScale(1, 1)
	board.BackgroundTransparency = 1
	board.BorderSizePixel = 0
	board.Parent = gui
	local title = label(board, "Title", Enum.Font.GothamBold, NAVY, titlePx)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.Position = UDim2.fromScale(0.02, 0.012)
	title.Size = UDim2.fromScale(0.96, TITLE_BAND)
	title.Text = text("Rank.Board.Title")
	title:SetAttribute("TextKey", "Rank.Board.Title")
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Position = UDim2.fromScale(0.02, 0.086)
	header.Size = UDim2.fromScale(0.96, HEADER_BAND)
	header.Parent = board
	local x = 0
	for _, column in columns do
		local heading = label(header, column.name, Enum.Font.GothamBold, BLUE, headerPx)
		heading.Position = UDim2.fromScale(x, 0)
		heading.Size = UDim2.fromScale(column.width, 1)
		if column.key ~= "" then
			heading.Text = text(column.key)
			heading:SetAttribute("TextKey", column.key)
		else
			heading.Text = ""
		end
		x += column.width
	end
	local rule = Instance.new("Frame")
	rule.Name = "Rule"
	rule.BackgroundColor3 = LINE
	rule.BorderSizePixel = 0
	rule.Position = UDim2.fromScale(0.02, 0.138)
	rule.Size = UDim2.fromScale(0.96, 0.004)
	rule.Parent = board
	local rows = Instance.new("Frame")
	rows.Name = "Rows"
	rows.BackgroundTransparency = 1
	rows.Position = UDim2.fromScale(0.02, ROWS_TOP)
	rows.Size = UDim2.fromScale(0.96, ROWS_BAND)
	rows.Parent = board
	for index = 1, 10 do
		local row = Instance.new("Frame")
		row.Name = "Row" .. tostring(index)
		row.BackgroundTransparency = 1
		row.Position = UDim2.fromScale(0, (index - 1) * 0.1)
		row.Size = UDim2.fromScale(1, 0.1)
		row.Visible = false
		row.Parent = rows
		local cursor = 0
		for _, column in columns do
			if column.name == "Face" then
				local face = Instance.new("ImageLabel")
				face.Name = "Face"
				face.BackgroundTransparency = 1
				face.BorderSizePixel = 0
				face.ScaleType = Enum.ScaleType.Fit
				face.AnchorPoint = Vector2.new(0, 0.5)
				face.Position = UDim2.fromScale(cursor, 0.5)
				face.Size = UDim2.fromScale(0, facePx / rowPx)
				face.Image = DEFAULT_FACE
				face.Parent = row
				local ratio = Instance.new("UIAspectRatioConstraint")
				ratio.AspectRatio = 1
				ratio.DominantAxis = Enum.DominantAxis.Height
				ratio.Parent = face
			else
				local cell = label(row, column.name, column.font, NAVY, bodyPx)
				cell.Position = UDim2.fromScale(cursor, 0)
				cell.Size = UDim2.fromScale(column.width, 1)
			end
			cursor += column.width
		end
		local line = Instance.new("Frame")
		line.BackgroundColor3 = LINE
		line.BorderSizePixel = 0
		line.Position = UDim2.fromScale(0, 1)
		line.Size = UDim2.new(1, 0, 0, 1)
		line.Parent = row
	end
	local notice = label(board, "Notice", Enum.Font.GothamMedium, NAVY, bodyPx)
	notice.TextXAlignment = Enum.TextXAlignment.Center
	notice.TextYAlignment = Enum.TextYAlignment.Center
	notice.Position = UDim2.fromScale(0.04, 0.2)
	notice.Size = UDim2.fromScale(0.92, 0.16)
	notice.Text = text("Rank.Board.Loading")
	notice:SetAttribute("TextKey", "Rank.Board.Loading")
end

local function faceFor(row: Frame, userId: number)
	local image = row:FindFirstChild("Face")
	if image == nil or not image:IsA("ImageLabel") then
		return
	end
	local known = faces[userId]
	if row:GetAttribute("UserId") == userId then
		if known ~= nil then
			image.Image = known
		end
		if known ~= nil or image.Image ~= DEFAULT_FACE or row:GetAttribute("FacePending") == true then
			return
		end
	end
	local token = (row:GetAttribute("FaceToken") :: number? or 0) + 1
	row:SetAttribute("UserId", userId)
	row:SetAttribute("FaceToken", token)
	if known ~= nil then
		image.Image = known
		row:SetAttribute("FacePending", false)
		return
	end
	image.Image = DEFAULT_FACE
	if userId <= 0 then
		row:SetAttribute("FacePending", false)
		return
	end
	row:SetAttribute("FacePending", true)
	task.spawn(function()
		local ok, content, ready = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		end)
		if row:GetAttribute("FaceToken") ~= token or row:GetAttribute("UserId") ~= userId then
			return
		end
		row:SetAttribute("FacePending", false)
		local portrait = if ok and ready == true and type(content) == "string" and content ~= "" then content else DEFAULT_FACE
		if portrait ~= DEFAULT_FACE then
			faces[userId] = portrait
		end
		image.Image = portrait
	end)
end

local function show(status: string, rows: {RankRules.Placed})
	local gui = locate()
	if gui == nil then
		painted = nil
		return
	end
	if painted ~= gui or gui:FindFirstChild("Board") == nil then
		mount(gui)
		painted = gui
	end
	local board = gui:FindFirstChild("Board")
	if board == nil then
		return
	end
	local list = board:FindFirstChild("Rows")
	local notice = board:FindFirstChild("Notice")
	if list == nil or notice == nil or not notice:IsA("TextLabel") then
		return
	end
	local count = math.min(10, #rows)
	local showRows = count > 0
	notice.Visible = not showRows
	if not showRows then
		local key = if status == "empty" then "Rank.Board.Empty" else "Rank.Board.Loading"
		notice:SetAttribute("TextKey", key)
		notice.Text = text(key)
	end
	for index = 1, 10 do
		local row = list:FindFirstChild("Row" .. tostring(index))
		if row == nil or not row:IsA("Frame") then
			continue
		end
		local entry = if index <= count then rows[index] else nil
		row.Visible = entry ~= nil
		if entry == nil then
			continue
		end
		local place = row:FindFirstChild("Place")
		local name = row:FindFirstChild("Name")
		local score = row:FindFirstChild("Score")
		local cpm = row:FindFirstChild("Cpm")
		local language = row:FindFirstChild("Language")
		if place and place:IsA("TextLabel") then
			place.Text = "#" .. tostring(entry.rank)
			place:SetAttribute("Rank", entry.rank)
		end
		if name and name:IsA("TextLabel") then
			name.Text = entry.name
		end
		if score and score:IsA("TextLabel") then
			score.Text = formatScore(entry.score)
		end
		if cpm and cpm:IsA("TextLabel") then
			cpm.Text = if entry.cpm ~= nil then formatScore(entry.cpm) else MISSING
		end
		if language and language:IsA("TextLabel") then
			language.Text = if entry.language ~= nil and entry.language ~= "" then entry.language else MISSING
		end
		faceFor(row, entry.userId)
	end
end

function RankBoard.start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		while true do
			local ok, err = pcall(function()
				local status, rows = RankService.board()
				show(status, rows)
			end)
			if not ok then
				warn("Lobby rank board refresh failed", err)
			end
			task.wait(2)
		end
	end)
end

return RankBoard

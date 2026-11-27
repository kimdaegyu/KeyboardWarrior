--!strict
-- Local copies of BasePad. A new floor snaps the character up before the pad grows.
-- The server publishes each step after positioning the rig and its support.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local constants = require(ReplicatedStorage.Shared.IngameConstants)
local DigitPadEffect = require(ReplicatedStorage.Shared.DigitPadEffect)
local FloorRules = require(ReplicatedStorage.Shared.FloorRules)
local PadLook = require(ReplicatedStorage.Shared.PadLook)
local SoundManager = require(script.Parent.SoundManager)

local FLOOR = constants.Floor
local FloorRise = {}

type Visual = {
	body: BasePart,
	rim: BasePart?,
	bottomY: number,
	scale: number,
	spin: number,
	generation: number,
}

type Paint = {
	body: string,
	rim: string,
	effect: string,
	preset: string,
}

type Glyph = {
	gui: BillboardGui,
	image: ImageLabel,
	born: number,
	origin: Vector3,
	up: Vector3,
}

type Show = {
	userId: number,
	matchId: number,
	paint: Paint,
	x: number,
	z: number,
	surfaceY: number,
	standY: number,
	built: {Visual},
	generation: number,
	elapsed: number,
	digit: number,
	point: number,
	glyphs: {Glyph},
}

type Lift = {
	generation: number,
	y: number,
	untilClock: number,
}

local shows: {[number]: Show} = {}
local held: {any} = {}
local lifts: {[number]: Lift} = {}

local LIFT_NAME = "KeyboardWarriorFloorLift"

local function templateParts(): (BasePart?, BasePart?, CFrame, Vector3, Vector3)
	local folder = ReplicatedStorage:FindFirstChild("Pad")
	local source = if folder ~= nil then folder:FindFirstChild("BasePad") else nil
	if source == nil or not source:IsA("BasePart") then
		return nil, nil, CFrame.identity, Vector3.zero, Vector3.zero
	end
	local rim = source:FindFirstChild("Out")
	local rimPart = if rim ~= nil and rim:IsA("BasePart") then rim else nil
	local rotation = source.CFrame - source.CFrame.Position
	local rimSize = if rimPart ~= nil then rimPart.Size else Vector3.zero
	return source, rimPart, rotation, source.Size, rimSize
end

local function readPaint(payload: {[string]: any}): Paint
	return {
		body = if type(payload.body) == "string" then payload.body else "126;84;255",
		rim = if type(payload.rim) == "string" then payload.rim else "none",
		effect = if type(payload.effect) == "string" then payload.effect else "none",
		preset = if type(payload.preset) == "string" then payload.preset else "",
	}
end

local function applyLook(body: BasePart, rim: BasePart?, paint: Paint)
	local bodyColor, rimColor, effectOn, effectColor = PadLook.forStack(paint)
	body.Color = bodyColor
	if rim == nil then
		return
	end
	if rimColor ~= nil then
		rim.Color = rimColor
	end
	local emitter = rim:FindFirstChild("ParticleEmitter")
	if emitter ~= nil and emitter:IsA("ParticleEmitter") then
		emitter.Enabled = effectOn
		if paint.preset == DigitPadEffect.Id then
			emitter.Enabled = false
		end
		if effectColor ~= nil then
			emitter.Color = ColorSequence.new(effectColor)
		end
	end
	if paint.preset == DigitPadEffect.Id then
		local spark = body:FindFirstChild("Spark")
		if spark ~= nil then
			spark:Destroy()
		end
		local motes = body:FindFirstChild("PadEffect")
		if motes ~= nil then
			motes:Destroy()
		end
	end
end

local function ensureDigitHost(visual: Visual)
	local rim = visual.rim
	if rim == nil then
		return
	end
	local folder = rim:FindFirstChild("Digits")
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = "Digits"
		folder.Parent = rim
		for point = 1, DigitPadEffect.PointCount do
			local attachment = Instance.new("Attachment")
			attachment.Name = "Point" .. tostring(point)
			attachment.Parent = folder
		end
	end
	for point = 1, DigitPadEffect.PointCount do
		local attachment = folder:FindFirstChild("Point" .. tostring(point))
		if attachment ~= nil and attachment:IsA("Attachment") then
			attachment.Position = DigitPadEffect.localPoint(rim.Size, point)
		end
	end
end

local function digitAnchor(): BasePart
	local folder = Workspace:FindFirstChild("FloorVisuals")
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = "FloorVisuals"
		folder.Parent = Workspace
	end
	local existing = folder:FindFirstChild("DigitAnchor")
	if existing ~= nil and existing:IsA("BasePart") then
		return existing
	end
	local part = Instance.new("Part")
	part.Name = "DigitAnchor"
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.CFrame = CFrame.new()
	part.Parent = folder
	return part
end

local function clearGlyphs(show: Show)
	for _, glyph in show.glyphs do
		glyph.gui:Destroy()
	end
	table.clear(show.glyphs)
end

local function spawnGlyph(show: Show, origin: Vector3, up: Vector3, digit: number, studs: number, color: Color3)
	local anchor = digitAnchor()
	local offset, rect = DigitPadEffect.cell(digit)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Digit" .. tostring(digit)
	gui.LightInfluence = 0
	gui.MaxDistance = 140
	gui.Size = UDim2.fromScale(studs, studs)
	gui.Adornee = anchor
	gui.StudsOffsetWorldSpace = origin - anchor.Position
	local image = Instance.new("ImageLabel")
	image.Name = "Glyph"
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromScale(1, 1)
	image.ScaleType = Enum.ScaleType.Fit
	image.Image = DigitPadEffect.image()
	image.ImageColor3 = color
	image.ImageRectOffset = offset
	image.ImageRectSize = rect
	image.Parent = gui
	gui.Parent = anchor
	table.insert(show.glyphs, {
		gui = gui,
		image = image,
		born = os.clock(),
		origin = origin,
		up = up,
	})
end

local function stepGlyphs(show: Show)
	local anchor = digitAnchor()
	local now = os.clock()
	for index = #show.glyphs, 1, -1 do
		local glyph = show.glyphs[index]
		local alpha = (now - glyph.born) / DigitPadEffect.Lifetime
		if alpha >= 1 or glyph.gui.Parent == nil then
			glyph.gui:Destroy()
			table.remove(show.glyphs, index)
		else
			local world = glyph.origin + glyph.up * (DigitPadEffect.Rise * alpha)
			glyph.gui.StudsOffsetWorldSpace = world - anchor.Position
			glyph.image.ImageTransparency = alpha
		end
	end
end

local function placeDigitHost(show: Show)
	local top = show.built[#show.built]
	local kept: Instance? = nil
	for _, visual in show.built do
		local rim = visual.rim
		local folder = if rim ~= nil then rim:FindFirstChild("Digits") else nil
		if folder ~= nil then
			if kept == nil then
				kept = folder
			else
				folder:Destroy()
			end
		end
	end
	local color = if show.paint.preset == DigitPadEffect.Id then PadLook.parseColor(show.paint.effect) else nil
	if top == nil or top.rim == nil or color == nil then
		if kept ~= nil then
			kept:Destroy()
		end
		return
	end
	if kept ~= nil and kept.Parent ~= top.rim then
		kept.Parent = top.rim
	end
	ensureDigitHost(top)
end

local function emitDigit(show: Show, dt: number)
	if show.paint.preset ~= DigitPadEffect.Id then
		return
	end
	local top = show.built[#show.built]
	local rim = if top ~= nil then top.rim else nil
	if rim == nil then
		return
	end
	local folder = rim:FindFirstChild("Digits")
	local color = PadLook.parseColor(show.paint.effect)
	if folder == nil or color == nil then
		return
	end
	show.elapsed += dt
	local interval = DigitPadEffect.interval()
	local bursts = 0
	while show.elapsed >= interval and bursts < 3 do
		show.elapsed -= interval
		bursts += 1
		show.digit = show.digit % DigitPadEffect.Count + 1
		show.point = show.point % DigitPadEffect.PointCount + 1
		local point = folder:FindFirstChild("Point" .. tostring(show.point))
		if point ~= nil and point:IsA("Attachment") then
			spawnGlyph(show, point.WorldPosition, rim.CFrame.XVector, show.digit, math.max(0.25, rim.Size.Y * 0.14), color)
		end
	end
end

local function silence(root: Instance)
	if root:IsA("BasePart") then
		root.Anchored = true
		root.CanCollide = false
		root.CanTouch = false
		root.CanQuery = false
	end
	for _, child in root:GetDescendants() do
		if child:IsA("BasePart") then
			child.Anchored = true
			child.CanCollide = false
			child.CanTouch = false
			child.CanQuery = false
		end
	end
end

local function placeVisual(visual: Visual, rotation: CFrame, bodySize: Vector3, rimSize: Vector3, x: number, z: number)
	local scale = visual.scale
	local thickness = bodySize.X * scale
	local diameter = if bodySize.Y > 0 then bodySize.Y * scale else thickness
	local depth = if bodySize.Y > 0 then bodySize.Z / bodySize.Y * diameter else diameter
	visual.body.Size = Vector3.new(thickness, diameter, depth)
	local centerY = visual.bottomY + thickness / 2
	visual.body.CFrame = CFrame.new(x, centerY, z) * rotation
	local rim = visual.rim
	if rim ~= nil then
		rim.Size = rimSize * scale
		rim.CFrame = visual.body.CFrame * CFrame.Angles(visual.spin, 0, 0)
	end
end

local function snapRoot(character: Model, root: BasePart, targetY: number)
	local delta = targetY - root.Position.Y
	if delta <= 0.001 then return end
	character:PivotTo(character:GetPivot() + Vector3.new(0, delta, 0))
end

local function applyLifts()
	local now = os.clock()
	local finished = {}
	for userId, lift in lifts do
		local show = shows[userId]
		if show == nil or show.generation ~= lift.generation or now >= lift.untilClock then
			table.insert(finished, userId)
			continue
		end
		local player = Players:GetPlayerByUserId(userId)
		local character = if player ~= nil then player.Character else nil
		local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
		if character ~= nil and root ~= nil and root:IsA("BasePart") and player and player:GetAttribute("InMatch") == true then
			snapRoot(character, root, lift.y)
		end
	end
	for _, userId in finished do
		lifts[userId] = nil
	end
end

local function liftCharacter(show: Show, floors: number)
	local player = Players:GetPlayerByUserId(show.userId)
	local character = if player ~= nil then player.Character else nil
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if character == nil or root == nil or not root:IsA("BasePart") then
		return
	end
	local standY = math.max(show.standY, show.surfaceY + FloorRules.standOffset(character, root))
	local targetY = standY + floors * FLOOR.FloorHeight
	lifts[show.userId] = {
		generation = show.generation,
		y = targetY,
		untilClock = os.clock() + FLOOR.FloorAnimationDuration,
	}
	snapRoot(character, root, targetY)
end

local function spawnFloor(show: Show, index: number, scale: number, generation: number): Visual?
	local source, _, rotation, bodySize, rimSize = templateParts()
	if source == nil then
		return nil
	end
	local folder = Workspace:FindFirstChild("FloorVisuals")
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = "FloorVisuals"
		folder.Parent = Workspace
	end
	local body = source:Clone()
	body.Name = "StackPad"
	silence(body)
	local rimInstance = body:FindFirstChild("Out")
	local rim = if rimInstance ~= nil and rimInstance:IsA("BasePart") then rimInstance else nil
	applyLook(body, rim, show.paint)
	local visual: Visual = {
		body = body,
		rim = rim,
		bottomY = show.surfaceY + (index - 1) * FLOOR.FloorHeight,
		scale = scale,
		spin = 0,
		generation = generation,
	}
	placeVisual(visual, rotation, bodySize, rimSize, show.x, show.z)
	body.Parent = folder
	table.insert(show.built, visual)
	return visual
end

local function destroyShow(show: Show)
	show.generation += 1
	clearGlyphs(show)
	for _, visual in show.built do
		visual.body:Destroy()
	end
	table.clear(show.built)
end

local function ensure(userId: number, matchId: number, x: number, surfaceY: number, z: number, standY: number, paint: Paint): Show
	local show = shows[userId]
	if show == nil or show.matchId ~= matchId then
		if show ~= nil then
			destroyShow(show)
		end
		show = {
			userId = userId,
			matchId = matchId,
			paint = paint,
			x = x,
			z = z,
			surfaceY = surfaceY,
			standY = standY,
			built = {},
			generation = 1,
			elapsed = 0,
			digit = 0,
			point = 0,
			glyphs = {},
		}
		shows[userId] = show
	else
		show.x = x
		show.z = z
		show.surfaceY = surfaceY
		show.standY = standY
		show.paint = paint
	end
	return show
end

local function animateFloor(show: Show, floors: number)
	local generation = show.generation
	local visual = spawnFloor(show, floors, FLOOR.FloorStartScale, generation)
	if not visual then return end
	if show.userId == Players.LocalPlayer.UserId then SoundManager.play("PadLevelUp") end
	local _, _, rotation, bodySize, rimSize = templateParts()
	local started = os.clock()
	task.spawn(function()
		while show.generation == generation do
			local alpha = math.clamp((os.clock() - started) / FLOOR.FloorAnimationDuration, 0, 1)
			visual.scale = FLOOR.FloorStartScale + (FLOOR.FloorEndScale - FLOOR.FloorStartScale) * FloorRules.quadOut(alpha)
			placeVisual(visual, rotation, bodySize, rimSize, show.x, show.z)
			if alpha >= 1 then break end
			RunService.Heartbeat:Wait()
		end
	end)
end

local function currentMatch(): number?
	local state = ReplicatedStorage:FindFirstChild("MatchState")
	local phase = if state ~= nil then state:GetAttribute("Phase") else nil
	local matchId = if state ~= nil then state:GetAttribute("MatchId") else nil
	if (phase ~= "Play" and phase ~= "Result") or type(matchId) ~= "number" then
		return nil
	end
	return matchId
end

local function clearUser(userId: number)
	local show = shows[userId]
	if show == nil then
		return
	end
	destroyShow(show)
	shows[userId] = nil
	lifts[userId] = nil
end

local function clearAll()
	local ids = {}
	for userId in shows do
		table.insert(ids, userId)
	end
	for _, userId in ids do
		clearUser(userId)
	end
end

local function onVisual(payload: any)
	if type(payload) ~= "table" or type(payload.action) ~= "string" then
		return
	end
	local live = currentMatch()
	if payload.action == "clear" then
		if type(payload.userId) == "number" then
			local show = shows[payload.userId]
			if show ~= nil and (type(payload.matchId) ~= "number" or show.matchId == payload.matchId) then
				clearUser(payload.userId)
			end
		elseif live == nil or payload.matchId == live then
			clearAll()
		end
		return
	end
	if type(payload.matchId) ~= "number" then
		return
	end
	if live == nil then
		table.insert(held, payload)
		return
	end
	if payload.matchId ~= live then
		return
	end
	if type(payload.userId) ~= "number" or type(payload.x) ~= "number" or type(payload.y) ~= "number" or type(payload.z) ~= "number" then
		return
	end
	local floors = if type(payload.floors) == "number" then payload.floors else 0
	local paint = readPaint(payload)
	local standY = if type(payload.standY) == "number" then payload.standY else payload.y
	local show = ensure(payload.userId, payload.matchId, payload.x, payload.y, payload.z, standY, paint)
	if payload.action ~= "sync" and payload.action ~= "rise" then return end
	if floors <= #show.built then
		local top = show.built[#show.built]
		if top ~= nil then
			applyLook(top.body, top.rim, show.paint)
		end
		placeDigitHost(show)
		return
	end
	liftCharacter(show, floors)
	for index = #show.built + 1, floors do
		if index == floors and payload.action == "rise" then
			animateFloor(show, index)
		else
			spawnFloor(show, index, FLOOR.FloorEndScale, show.generation)
		end
	end
	placeDigitHost(show)
end

local function flushHeld()
	local state = ReplicatedStorage:FindFirstChild("MatchState")
	local phase = if state ~= nil then state:GetAttribute("Phase") else nil
	if phase ~= "Play" and phase ~= "Result" then
		table.clear(held)
		clearAll()
		return
	end
	if phase == "Result" then
		return
	end
	local live = currentMatch()
	if live == nil then
		return
	end
	local queued = held
	held = {}
	for _, payload in queued do
		onVisual(payload)
	end
end

function FloorRise.bind(): () -> ()
	local event = ReplicatedStorage:WaitForChild("FloorVisual")
	local state = ReplicatedStorage:WaitForChild("MatchState")
	RunService:BindToRenderStep(LIFT_NAME, Enum.RenderPriority.Last.Value, applyLifts)
	local spin = RunService.Heartbeat:Connect(function(dt)
		local step = math.rad(FLOOR.RimRotationSpeed) * dt
		for _, show in shows do
			for _, visual in show.built do
				if visual.body.Parent == nil then
					continue
				end
				visual.spin -= step
				local rim = visual.rim
				if rim ~= nil then
					rim.CFrame = visual.body.CFrame * CFrame.Angles(visual.spin, 0, 0)
				end
			end
			if show.paint.preset == DigitPadEffect.Id then
				local top = show.built[#show.built]
				if top ~= nil then
					ensureDigitHost(top)
				end
				stepGlyphs(show)
				emitDigit(show, dt)
			elseif #show.glyphs > 0 then
				clearGlyphs(show)
			end
		end
	end)
	local connections = {
		spin,
		event.OnClientEvent:Connect(onVisual),
		state:GetAttributeChangedSignal("Phase"):Connect(flushHeld),
		state:GetAttributeChangedSignal("MatchId"):Connect(flushHeld),
	}
	if event:IsA("RemoteEvent") then
		event:FireServer()
	end
	return function()
		for _, connection in connections do
			connection:Disconnect()
		end
		RunService:UnbindFromRenderStep(LIFT_NAME)
		table.clear(lifts)
		clearAll()
		local folder = Workspace:FindFirstChild("FloorVisuals")
		if folder ~= nil then
			folder:Destroy()
		end
	end
end

return FloorRise

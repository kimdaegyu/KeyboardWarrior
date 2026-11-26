--!strict
-- Local copies of BasePad. A new floor snaps the character up before the pad grows.
-- The server publishes each step after positioning the rig and its support.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local constants = require(ReplicatedStorage.Shared.IngameConstants)
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
		if effectColor ~= nil then
			emitter.Color = ColorSequence.new(effectColor)
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
	if floors <= #show.built then return end
	liftCharacter(show, floors)
	for index = #show.built + 1, floors do
		if index == floors and payload.action == "rise" then
			animateFloor(show, index)
		else
			spawnFloor(show, index, FLOOR.FloorEndScale, show.generation)
		end
	end
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

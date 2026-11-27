--!strict
-- Authoritative stack height. Clients only draw the cloned pads and the rim spin.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local constants = require(ReplicatedStorage.Shared.IngameConstants)
local FloorRules = require(ReplicatedStorage.Shared.FloorRules)
local ArenaService = require(script.Parent.ArenaService)
local ShopService = require(script.Parent.ShopService)

local FLOOR = constants.Floor
local FloorService = {}

type Stack = {
	player: Player,
	matchId: number,
	padIndex: number,
	stand: CFrame,
	surfaceY: number,
	applied: number,
	target: number,
	running: boolean,
	generation: number,
	support: Part?,
	removing: RBXScriptConnection?,
}

local stacks: {[Player]: Stack} = {}
local latestScore: {[Player]: number} = {}
local latestMatch: {[Player]: number} = {}
local visualEvent: RemoteEvent? = nil
local supports: Folder? = nil
local started = false

local function remote(): RemoteEvent
	local existing = visualEvent
	if existing ~= nil then
		return existing
	end
	local found = ReplicatedStorage:FindFirstChild("FloorVisual")
	if found ~= nil and found:IsA("RemoteEvent") then
		visualEvent = found
		return found
	end
	local event = Instance.new("RemoteEvent")
	event.Name = "FloorVisual"
	event.Parent = ReplicatedStorage
	visualEvent = event
	return event
end

local function supportFolder(): Folder
	local folder = supports
	if folder ~= nil and folder.Parent ~= nil then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = "FloorSupports"
	created.Parent = Workspace
	supports = created
	return created
end

local function tell(payload: {[string]: any})
	remote():FireAllClients(payload)
end

local function withLook(player: Player, payload: {[string]: any}): {[string]: any}
	local paint = ShopService.paintFor(player.UserId)
	payload.body = paint.body
	payload.rim = paint.rim
	payload.effect = paint.effect
	payload.preset = if type(paint.preset) == "string" then paint.preset else ""
	return payload
end

local function destroySupport(stack: Stack)
	local part = stack.support
	stack.support = nil
	if part ~= nil then
		part:Destroy()
	end
end

local function placeSupport(stack: Stack, floors: number, collide: boolean)
	local part = stack.support
	if part == nil or part.Parent == nil then
		part = Instance.new("Part")
		part.Name = "FloorSupport"
		part.Shape = Enum.PartType.Cylinder
		part.Anchored = true
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part.Transparency = 1
		part.Size = Vector3.new(FLOOR.FloorHeight, constants.Arena.PadDiameter, constants.Arena.PadDiameter)
		part.Parent = supportFolder()
		stack.support = part
	end
	part.CanCollide = collide
	local top = stack.surfaceY + floors * FLOOR.FloorHeight
	local center = Vector3.new(stack.stand.Position.X, top - FLOOR.FloorHeight / 2, stack.stand.Position.Z)
	part.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
end

local function pose(stack: Stack, floors: number)
	local character = stack.player.Character
	if character == nil then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then return end
	local standY = stack.surfaceY + FloorRules.standOffset(character, root)
	stack.stand += Vector3.new(0, standY - stack.stand.Position.Y, 0)
	ArenaService.pose(character, stack.stand + Vector3.new(0, floors * FLOOR.FloorHeight, 0))
	if floors > 0 then placeSupport(stack, floors, true) end
end

local function pump(stack: Stack)
	if stack.running or stack.applied >= stack.target then return end
	stack.running = true
	local generation = stack.generation
	task.spawn(function()
		while stacks[stack.player] == stack and stack.generation == generation do
			if stack.applied >= stack.target then
				stack.running = false
				local character = stack.player.Character
				if character then ArenaService.releasePose(character) end
				return
			end
			stack.applied += 1
			pose(stack, stack.applied)
			tell(withLook(stack.player, {
				action = "rise", matchId = stack.matchId, userId = stack.player.UserId,
				floors = stack.applied, standY = stack.stand.Position.Y,
				x = stack.stand.Position.X, y = stack.surfaceY, z = stack.stand.Position.Z,
			}))
			-- Only the visual growth and the spacing between consecutive steps take time.
			task.wait(FLOOR.FloorAnimationDuration)
		end
	end)
end

local function drop(stack: Stack, restoreBase: boolean)
	stack.generation += 1
	stacks[stack.player] = nil
	stack.player:SetAttribute("FloorCount", nil)
	latestScore[stack.player] = nil
	latestMatch[stack.player] = nil
	if stack.removing ~= nil then
		stack.removing:Disconnect()
		stack.removing = nil
	end
	local character = stack.player.Character
	if restoreBase and character ~= nil then
		ArenaService.pose(character, stack.stand)
	end
	destroySupport(stack)
	if character ~= nil then
		ArenaService.releasePose(character)
	end
	tell({
		action = "clear",
		matchId = stack.matchId,
		userId = stack.player.UserId,
	})
end

function FloorService.bind(player: Player, matchId: number, padIndex: number, character: Model)
	local stand = ArenaService.standFrame(padIndex, character)
	local surfaceY = ArenaService.surfaceY(padIndex)
	if stand == nil or surfaceY == nil then
		return
	end
	local previous = stacks[player]
	local earned = if latestMatch[player] == matchId then FloorRules.floorsFor(latestScore[player] or 0) else 0
	if previous ~= nil and previous.matchId == matchId then
		earned = math.max(earned, previous.target)
		previous.generation += 1
		if previous.removing ~= nil then
			previous.removing:Disconnect()
		end
		destroySupport(previous)
		tell({
			action = "clear",
			matchId = matchId,
			userId = player.UserId,
		})
	elseif previous ~= nil then
		drop(previous, false)
	end
	local stack: Stack = {
		player = player,
		matchId = matchId,
		padIndex = padIndex,
		stand = stand,
		surfaceY = surfaceY,
		applied = earned,
		target = earned,
		running = false,
		generation = 1,
		support = nil,
		removing = nil,
	}
	stack.removing = player.CharacterRemoving:Connect(function()
		if stacks[player] ~= stack then
			return
		end
		stack.generation += 1
		stack.running = false
		destroySupport(stack)
		tell({
			action = "clear",
			matchId = stack.matchId,
			userId = player.UserId,
		})
	end)
	stacks[player] = stack
	player:SetAttribute("FloorCount", earned)
	if earned > 0 then
		pose(stack, earned)
		ArenaService.releasePose(character)
		tell(withLook(player, {
			action = "sync",
			matchId = matchId,
			userId = player.UserId,
			floors = earned,
			standY = stand.Position.Y,
			x = stand.Position.X,
			y = surfaceY,
			z = stand.Position.Z,
		}))
	end
end

function FloorService.noteScore(player: Player, previousScore: number, currentScore: number, matchId: number)
	latestScore[player] = currentScore
	latestMatch[player] = matchId
	local stack = stacks[player]
	if stack == nil or stack.matchId ~= matchId then
		return
	end
	local acquired = FloorRules.acquired(previousScore, currentScore)
	stack.target = FloorRules.floorsFor(currentScore)
	player:SetAttribute("FloorCount", stack.target)
	if acquired <= 0 then
		return
	end
	pump(stack)
end

function FloorService.clear(player: Player)
	local stack = stacks[player]
	if stack == nil then
		return
	end
	drop(stack, false)
end

function FloorService.finishMatch(matchId: number)
	local leaving = {}
	for player, stack in stacks do
		if stack.matchId == matchId then
			table.insert(leaving, player)
		end
	end
	for _, player in leaving do
		local stack = stacks[player]
		if stack ~= nil then
			drop(stack, true)
		end
	end
end

local function sendSnapshot(player: Player)
	for _, stack in stacks do
		if stack.applied <= 0 then
			continue
		end
		remote():FireClient(player, withLook(stack.player, {
			action = "sync",
			matchId = stack.matchId,
			userId = stack.player.UserId,
			floors = stack.applied,
			standY = stack.stand.Position.Y,
			x = stack.stand.Position.X,
			y = stack.surfaceY,
			z = stack.stand.Position.Z,
		}))
	end
end

function FloorService.start()
	if started then
		return
	end
	started = true
	remote().OnServerEvent:Connect(function(player: Player)
		sendSnapshot(player)
	end)
	supportFolder()
	Players.PlayerAdded:Connect(function(player)
		task.defer(sendSnapshot, player)
	end)
end

return FloorService

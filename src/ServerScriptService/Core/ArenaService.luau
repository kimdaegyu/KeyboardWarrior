--!strict
-- Reuses Studio-placed Workspace.Arena markers and keeps one ring of pads.

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local constants = require(ReplicatedStorage.Shared.IngameConstants)
local FloorRules = require(ReplicatedStorage.Shared.FloorRules)
local MatchRules = require(ReplicatedStorage.Shared.MatchRules)
local PadLook = require(ReplicatedStorage.Shared.PadLook)

local MATCH = constants.Match
local ARENA = constants.Arena
-- A floor disc is only a few tenths thick. Standing players are still "in the circle".
local STAND_CLEARANCE = 8
local PAD_THICKNESS = 1
local LOBBY_RING_RADIUS = 3

local ArenaService = {}

local markers: {
	arena: Folder,
	center: BasePart,
	join: BasePart,
	lobby: BasePart,
}? = nil
local pads: {BasePart}? = nil
local dressed: {[number]: PadLook.Paint} = {}
local poseHeld: {[BasePart]: boolean} = {}

local function describe(root: Instance): string
	local names = {}
	for _, child in root:GetDescendants() do
		table.insert(names, child:GetFullName())
	end
	table.sort(names)
	if #names == 0 then
		return "(empty)"
	end
	return table.concat(names, ", ")
end

local function expect(arena: Instance, name: string, className: string): Instance
	local inst = arena:FindFirstChild(name, true)
	if inst == nil or not inst:IsA(className) then
		error(
			`[ArenaService] Workspace.Arena.{name} ({className}) is missing. Reuse the Studio object; descendants: {describe(arena)}`
		)
	end
	return inst
end

local function resolveMarkers()
	if markers ~= nil then
		return markers
	end
	local arena = Workspace:WaitForChild("Arena", 10)
	if arena == nil or not arena:IsA("Folder") then
		error("[ArenaService] Workspace.Arena folder is missing. Place LobbySpawn, JoinZone, and ArenaCenter under it.")
	end
	local resolved = {
		arena = arena,
		center = expect(arena, "ArenaCenter", "BasePart") :: BasePart,
		join = expect(arena, "JoinZone", "BasePart") :: BasePart,
		lobby = expect(arena, "LobbySpawn", "SpawnLocation") :: BasePart,
	}
	markers = resolved
	return resolved
end

function ArenaService.isInsideJoinZone(worldPosition: Vector3): boolean
	local join = resolveMarkers().join
	local localPosition = join.CFrame:PointToObjectSpace(worldPosition)
	local size = join.Size
	if join:IsA("Part") and join.Shape == Enum.PartType.Ball then
		return (worldPosition - join.Position).Magnitude <= math.min(size.X, size.Y, size.Z) / 2
	end
	if join:IsA("Part") and join.Shape == Enum.PartType.Cylinder then
		-- Cylinder axis is local X. A flat join disc stores its radius on Y/Z.
		local radius = math.min(size.Y, size.Z) / 2
		local planar = math.sqrt(localPosition.Y * localPosition.Y + localPosition.Z * localPosition.Z)
		return planar <= radius and math.abs(localPosition.X) <= size.X / 2 + STAND_CLEARANCE
	end
	local axes = {
		{ alignment = math.abs(join.CFrame.RightVector.Y), half = size.X / 2, coord = localPosition.X },
		{ alignment = math.abs(join.CFrame.UpVector.Y), half = size.Y / 2, coord = localPosition.Y },
		{ alignment = math.abs(join.CFrame.LookVector.Y), half = size.Z / 2, coord = localPosition.Z },
	}
	table.sort(axes, function(a, b)
		return a.alignment > b.alignment
	end)
	local radius = math.min(axes[2].half, axes[3].half)
	local planar = math.sqrt(axes[2].coord * axes[2].coord + axes[3].coord * axes[3].coord)
	return planar <= radius and math.abs(axes[1].coord) <= axes[1].half + STAND_CLEARANCE
end

local function pivotCharacter(character: Model, target: CFrame)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return
	end
	local player = Players:GetPlayerFromCharacter(character)
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	character:PivotTo(target * root.CFrame:ToObjectSpace(character:GetPivot()))
	if player ~= nil then
		task.delay(0.2, function()
			if root.Parent == nil or poseHeld[root] then
				return
			end
			pcall(function()
				root:SetNetworkOwner(player)
			end)
		end)
	end
end

function ArenaService.hold(character: Model): boolean
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return false
	end
	poseHeld[root] = true
	if root.Anchored then
		return false
	end
	root.Anchored = true
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	return true
end

function ArenaService.pose(character: Model, target: CFrame)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return
	end
	poseHeld[root] = true
	if not root.Anchored then
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
		root.Anchored = true
	end
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	character:PivotTo(target * root.CFrame:ToObjectSpace(character:GetPivot()))
end

function ArenaService.releasePose(character: Model)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return
	end
	poseHeld[root] = nil
	root.Anchored = false
	local player = Players:GetPlayerFromCharacter(character)
	if player ~= nil and root.Parent ~= nil then
		pcall(function()
			root:SetNetworkOwner(player)
		end)
	end
end

local function standCFrame(origin: CFrame, size: Vector3, character: Model, lookAt: Vector3?): CFrame?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or root == nil or not root:IsA("BasePart") then
		return nil
	end
	local floor = origin.Position.Y
		+ math.abs(origin.RightVector.Y) * size.X / 2
		+ math.abs(origin.UpVector.Y) * size.Y / 2
		+ math.abs(origin.LookVector.Y) * size.Z / 2
	local lift = FloorRules.standOffset(character, root)
	local position = Vector3.new(origin.Position.X, floor + lift, origin.Position.Z)
	local rotation = origin - origin.Position
	if lookAt == nil then
		return CFrame.new(position) * rotation
	end
	local focus = Vector3.new(lookAt.X, position.Y, lookAt.Z)
	if (focus - position).Magnitude < 0.05 then
		return CFrame.new(position)
	end
	return CFrame.lookAt(position, focus)
end

local function surfaceOf(pad: BasePart): number
	local origin = pad.CFrame
	local size = pad.Size
	return origin.Position.Y
		+ math.abs(origin.RightVector.Y) * size.X / 2
		+ math.abs(origin.UpVector.Y) * size.Y / 2
		+ math.abs(origin.LookVector.Y) * size.Z / 2
end

function ArenaService.surfaceY(padIndex: number): number?
	local current = pads or ArenaService.ensurePads()
	local pad = current[padIndex]
	if pad == nil then
		return nil
	end
	return surfaceOf(pad)
end

function ArenaService.standFrame(padIndex: number, character: Model): CFrame?
	local current = pads or ArenaService.ensurePads()
	local pad = current[padIndex]
	if pad == nil then
		return nil
	end
	return standCFrame(pad.CFrame, pad.Size, character, resolveMarkers().center.Position)
end

local function outsideJoin(preferred: Vector3): Vector3
	if not ArenaService.isInsideJoinZone(preferred) then
		return preferred
	end
	local join = resolveMarkers().join
	local flat = Vector3.new(preferred.X - join.Position.X, 0, preferred.Z - join.Position.Z)
	if flat.Magnitude < 0.1 then
		flat = Vector3.new(0, 0, 1)
	end
	local pushed = join.Position + flat.Unit * (math.max(join.Size.X, join.Size.Y, join.Size.Z) / 2 + 4)
	return Vector3.new(pushed.X, preferred.Y, pushed.Z)
end

function ArenaService.ensurePads(): {BasePart}
	local found = resolveMarkers()
	local existingFolder = found.arena:FindFirstChild("Pads")
	local folder: Folder
	if existingFolder ~= nil and existingFolder:IsA("Folder") then
		folder = existingFolder
	else
		if existingFolder ~= nil then
			existingFolder:Destroy()
		end
		folder = Instance.new("Folder")
		folder.Name = "Pads"
		folder.Parent = found.arena
	end
	local count = MATCH.MaxParticipants
	local points = MatchRules.padPoints(count, ARENA.PadCenterRadius)
	local nextPads: {BasePart} = table.create(count)
	for index = 1, count do
		local name = string.format("Pad%02d", index)
		local existing = folder:FindFirstChild(name)
		local pad: Part
		if existing ~= nil and existing:IsA("Part") then
			pad = existing
		else
			if existing ~= nil then
				existing:Destroy()
			end
			pad = Instance.new("Part")
			pad.Name = name
			pad.Anchored = true
			pad.CanCollide = true
			pad.TopSurface = Enum.SurfaceType.Smooth
			pad.BottomSurface = Enum.SurfaceType.Smooth
			pad.Parent = folder
			local billboard = Instance.new("BillboardGui")
			billboard.Name = "Index"
			billboard.Size = UDim2.fromOffset(36, 20)
			billboard.StudsOffset = Vector3.new(0, 2.2, 0)
			billboard.Parent = pad
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(1, 1)
			label.Font = Enum.Font.GothamBold
			label.Text = tostring(index)
			label.TextColor3 = Color3.new(1, 1, 1)
			label.TextScaled = true
			label.Parent = billboard
		end
		pad.Shape = Enum.PartType.Cylinder
		pad.Size = Vector3.new(PAD_THICKNESS, ARENA.PadDiameter, ARENA.PadDiameter)
		local point = points[index]
		local position = Vector3.new(
			found.center.Position.X + point.x,
			found.center.Position.Y + PAD_THICKNESS / 2,
			found.center.Position.Z + point.z
		)
		-- Local X is the cylinder axis; roll it to world Y so the pad lies flat.
		pad.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
		PadLook.apply(pad, dressed[index] or PadLook.starter())
		nextPads[index] = pad
	end
	for _, child in folder:GetChildren() do
		if table.find(nextPads, child) == nil then
			child:Destroy()
		end
	end
	pads = nextPads
	return nextPads
end

function ArenaService.padCount(): number
	local current = pads
	if current == nil then
		return 0
	end
	local count = 0
	for _, pad in ipairs(current) do
		if pad.Parent ~= nil then
			count += 1
		end
	end
	return count
end

function ArenaService.dress(padIndex: number, paint: PadLook.Paint)
	dressed[padIndex] = paint
	local current = pads or ArenaService.ensurePads()
	local pad = current[padIndex]
	if pad ~= nil then
		PadLook.apply(pad, paint)
	end
end

function ArenaService.undress(padIndex: number)
	dressed[padIndex] = nil
	local current = pads
	local pad = if current ~= nil then current[padIndex] else nil
	if pad ~= nil then
		PadLook.apply(pad, PadLook.starter())
	end
end

function ArenaService.undressAll()
	table.clear(dressed)
	local current = pads
	if current == nil then
		return
	end
	for _, pad in current do
		if pad.Parent ~= nil then
			PadLook.apply(pad, PadLook.starter())
		end
	end
end

function ArenaService.placeOnPad(character: Model, padIndex: number)
	local current = pads or ArenaService.ensurePads()
	local pad = current[padIndex]
	if pad == nil then
		return
	end
	local frame = standCFrame(pad.CFrame, pad.Size, character, resolveMarkers().center.Position)
	if frame ~= nil then
		pivotCharacter(character, frame)
	end
end

function ArenaService.placeInLobby(character: Model, slot: number, total: number)
	local lobby = resolveMarkers().lobby
	local offset = Vector3.zero
	if total > 1 then
		local angle = (slot - 1) / total * math.pi * 2
		offset = Vector3.new(math.cos(angle) * LOBBY_RING_RADIUS, 0, math.sin(angle) * LOBBY_RING_RADIUS)
	end
	local parked = outsideJoin(lobby.Position + offset)
	local origin = CFrame.new(parked) * (lobby.CFrame - lobby.CFrame.Position)
	local frame = standCFrame(origin, lobby.Size, character, nil)
	if frame ~= nil then
		pivotCharacter(character, frame)
	end
end

local announced = false
local wallWarned = false

local function innerWall(): BasePart?
	local wall = resolveMarkers().arena:FindFirstChild("Wall")
	local inner = if wall ~= nil then wall:FindFirstChild("InWall") else nil
	if inner ~= nil and inner:IsA("BasePart") then
		return inner
	end
	return nil
end

local function horizontalReach(part: BasePart, center: Vector3): number
	local half = part.Size / 2
	local frame = part.CFrame
	local reach = 0
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local corner = (frame * CFrame.new(sx * half.X, sy * half.Y, sz * half.Z)).Position
				local dx = corner.X - center.X
				local dz = corner.Z - center.Z
				local distance = math.sqrt(dx * dx + dz * dz)
				if distance > reach then
					reach = distance
				end
			end
		end
	end
	return reach
end

function ArenaService.arenaRadius(): number
	local center = resolveMarkers().center.Position
	local designed = ARENA.Diameter / 2
	local wall = innerWall()
	if wall == nil then
		return designed
	end
	return math.max(designed, horizontalReach(wall, center))
end

function ArenaService.isInsideArena(worldPosition: Vector3): boolean
	local center = resolveMarkers().center.Position
	local dx = worldPosition.X - center.X
	local dz = worldPosition.Z - center.Z
	local radius = ArenaService.arenaRadius()
	return dx * dx + dz * dz <= radius * radius
end

function ArenaService.setInnerWallCollide(enabled: boolean)
	local part = innerWall()
	if part == nil then
		if not wallWarned then
			wallWarned = true
			warn("[ArenaService] Workspace.Arena.Wall.InWall is missing")
		end
		return
	end
	part.CanCollide = enabled
end

function ArenaService.ejectOutsiders(playing: {[Player]: boolean})
	local outsiders = {}
	for _, player in Players:GetPlayers() do
		if playing[player] then
			continue
		end
		local character = player.Character
		if character ~= nil and ArenaService.isInsideArena(character:GetPivot().Position) then
			table.insert(outsiders, player)
		end
	end
	local total = math.max(#outsiders, 1)
	for index, player in outsiders do
		local character = player.Character
		if character == nil then
			continue
		end
		ArenaService.placeInLobby(character, index, total)
		local root = character:FindFirstChild("HumanoidRootPart")
		if root == nil or not root:IsA("BasePart") or not ArenaService.isInsideArena(root.Position) then
			continue
		end
		local center = resolveMarkers().center.Position
		local flat = Vector3.new(root.Position.X - center.X, 0, root.Position.Z - center.Z)
		if flat.Magnitude < 0.1 then
			flat = Vector3.new(0, 0, 1)
		end
		local pushed = Vector3.new(center.X, root.Position.Y, center.Z) + flat.Unit * (ArenaService.arenaRadius() + 4)
		pivotCharacter(character, CFrame.new(pushed) * root.CFrame.Rotation)
	end
end

function ArenaService.start()
	local current = ArenaService.ensurePads()
	ArenaService.setInnerWallCollide(false)
	if not announced then
		announced = true
		local found = resolveMarkers()
		print(
			`[KeyboardWarrior] Arena ready pads={#current} center={found.center.Position} joinSize={found.join.Size}`
		)
	end
	return current
end

return ArenaService

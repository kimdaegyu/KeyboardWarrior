--!strict
-- Frames the local pad and the pad across the arena while a match is being played.
-- Practice, spectators, and the lobby never call setPlaying(true). Stopping restores the previous camera.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local FloorRules = require(game:GetService("ReplicatedStorage").Shared.FloorRules)
local MatchCamera = {}

local BACK = 34
local UP = 18
local LOOK_LIFT = 2
local PAD_REACH = 18

local RENDER_NAME = "KeyboardWarriorMatchCamera"

local playing = false
local orbiting = false
local bound = false
local savedType: Enum.CameraType? = nil
local savedSubject: Instance? = nil
local savedCamera: Camera? = nil
local framedPad: BasePart? = nil

local function currentCamera(): Camera?
	return Workspace.CurrentCamera
end

local function restore()
	local camera = savedCamera or currentCamera()
	if camera ~= nil and savedType ~= nil then
		camera.CameraType = savedType
		if savedSubject ~= nil and savedSubject.Parent ~= nil then
			camera.CameraSubject = savedSubject
		end
	end
	savedType = nil
	savedSubject = nil
	savedCamera = nil
	framedPad = nil
end

local function nearestPad(root: BasePart): BasePart?
	local arena = Workspace:FindFirstChild("Arena")
	local pads = if arena ~= nil then arena:FindFirstChild("Pads") else nil
	if pads == nil then
		return framedPad
	end
	local best = framedPad
	local bestDistance = PAD_REACH
	for _, child in pads:GetChildren() do
		if child:IsA("BasePart") then
			local offset = Vector3.new(child.Position.X - root.Position.X, 0, child.Position.Z - root.Position.Z)
			local distance = offset.Magnitude
			if distance < bestDistance then
				bestDistance = distance
				best = child
			end
		end
	end
	if best ~= nil then
		framedPad = best
	end
	return framedPad
end

local function padSurface(pad: BasePart): number
	local origin = pad.CFrame
	local size = pad.Size
	return origin.Position.Y
		+ math.abs(origin.RightVector.Y) * size.X / 2
		+ math.abs(origin.UpVector.Y) * size.Y / 2
		+ math.abs(origin.LookVector.Y) * size.Z / 2
end

local function unbind()
	if not bound then
		return
	end
	bound = false
	RunService:UnbindFromRenderStep(RENDER_NAME)
end

local function step()
	local camera = currentCamera()
	local character = Players.LocalPlayer.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	local arena = Workspace:FindFirstChild("Arena")
	local center = if arena ~= nil then arena:FindFirstChild("ArenaCenter") else nil
	if camera == nil or character == nil or root == nil or not root:IsA("BasePart") or center == nil or not center:IsA("BasePart") then
		return
	end
	local pad = nearestPad(root)
	if pad == nil then
		return
	end
	if savedType == nil then
		savedCamera = camera
		savedType = camera.CameraType
		savedSubject = camera.CameraSubject
	else
		savedCamera = camera
	end
	local flat = Vector3.new(root.Position.X - center.Position.X, 0, root.Position.Z - center.Position.Z)
	if flat.Magnitude < 1 then
		flat = Vector3.new(pad.Position.X - center.Position.X, 0, pad.Position.Z - center.Position.Z)
	end
	if flat.Magnitude < 1 then
		return
	end
	local outward = flat.Unit
	local rise = root.Position.Y - (padSurface(pad) + FloorRules.standOffset(character, root))
	local eye = Vector3.new(root.Position.X, pad.Position.Y + UP + rise, root.Position.Z) + outward * BACK
	local look = Vector3.new(center.Position.X, center.Position.Y + LOOK_LIFT + rise, center.Position.Z)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(eye, look)
end

local function enableLook()
	local camera = currentCamera()
	local character = Players.LocalPlayer.Character
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	if camera ~= nil then
		camera.CameraType = Enum.CameraType.Custom
		if humanoid ~= nil then
			camera.CameraSubject = humanoid
		end
	end
	Players.LocalPlayer.CameraMode = Enum.CameraMode.Classic
	local scripts = Players.LocalPlayer:FindFirstChild("PlayerScripts")
	local playerModule = if scripts ~= nil then scripts:FindFirstChild("PlayerModule") else nil
	local cameraModule = if playerModule ~= nil then playerModule:FindFirstChild("CameraModule") else nil
	local input = if cameraModule ~= nil then cameraModule:FindFirstChild("CameraInput") else nil
	if input ~= nil and input:IsA("ModuleScript") then
		local ok, result = pcall(require, input)
		if ok and type(result) == "table" and type(result.setInputEnabled) == "function" then
			result.setInputEnabled(true)
		end
	end
end

function MatchCamera.setOrbit(on: boolean)
	orbiting = on
	if playing then
		return
	end
	unbind()
	if orbiting then
		enableLook()
	else
		restore()
	end
end

function MatchCamera.setPlaying(nextPlaying: boolean)
	if nextPlaying == playing then
		if not playing and orbiting then
			enableLook()
		end
		return
	end
	playing = nextPlaying
	unbind()
	if not playing then
		if orbiting then
			enableLook()
		else
			restore()
		end
		return
	end
	orbiting = false
	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Last.Value + 1, step)
	bound = true
	step()
end

return MatchCamera

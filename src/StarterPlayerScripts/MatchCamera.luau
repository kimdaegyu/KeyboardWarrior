--!strict
-- Frames the local pad and the pad across the arena while a match is being played.
-- Practice, spectators, and the lobby never call setPlaying(true). Stopping restores the previous camera.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MatchCamera = {}

local BACK = 34
local UP = 18
local LOOK_LIFT = 2
local PAD_REACH = 18

local playing = false
local connection: RBXScriptConnection? = nil
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

local function step()
	local camera = currentCamera()
	local character = Players.LocalPlayer.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	local arena = Workspace:FindFirstChild("Arena")
	local center = if arena ~= nil then arena:FindFirstChild("ArenaCenter") else nil
	if camera == nil or root == nil or not root:IsA("BasePart") or center == nil or not center:IsA("BasePart") then
		return
	end
	local pad = nearestPad(root)
	if pad == nil then
		return
	end
	if savedType == nil or savedCamera ~= camera then
		savedCamera = camera
		savedType = camera.CameraType
		savedSubject = camera.CameraSubject
	end
	local flat = Vector3.new(pad.Position.X - center.Position.X, 0, pad.Position.Z - center.Position.Z)
	if flat.Magnitude < 1 then
		return
	end
	local outward = flat.Unit
	local eye = pad.Position + outward * BACK + Vector3.yAxis * UP
	local look = center.Position + Vector3.yAxis * LOOK_LIFT
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(eye, look)
end

function MatchCamera.setPlaying(nextPlaying: boolean)
	if nextPlaying == playing then
		return
	end
	playing = nextPlaying
	if connection ~= nil then
		connection:Disconnect()
		connection = nil
	end
	if not playing then
		restore()
		return
	end
	connection = RunService.RenderStepped:Connect(step)
	step()
end

return MatchCamera

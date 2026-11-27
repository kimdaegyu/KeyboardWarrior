--!strict
-- Records that this player finished or skipped the tutorial. Reward and language fields stay on the same profile.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProfileService = require(script.Parent.ProfileService)
local TutorialRules = require(ReplicatedStorage.Shared.TutorialRules)

local TutorialService = {}

local started = false
local stateEvent: RemoteEvent? = nil

local function remote(name: string): RemoteEvent
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing ~= nil and existing:IsA("RemoteEvent") then
		return existing
	end
	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = ReplicatedStorage
	return event
end

local function payload(userId: number, saveState: string)
	local profile = ProfileService.read(userId)
	return {
		seen = if profile ~= nil then TutorialRules.seenOf(profile.tutorialSeen) else false,
		saveState = saveState,
	}
end

local function push(player: Player, saveState: string)
	if stateEvent == nil or player.Parent == nil then
		return
	end
	stateEvent:FireClient(player, payload(player.UserId, saveState))
end

function TutorialService.start()
	if started then
		return
	end
	started = true
	stateEvent = remote("TutorialState")
	local request = remote("TutorialRequest")
	local ack = remote("TutorialAck")
	ProfileService.setReadyHandler(function(userId: number)
		local player = Players:GetPlayerByUserId(userId)
		if player ~= nil then
			push(player, "ready")
		end
	end)
	request.OnServerEvent:Connect(function(player: Player)
		if ProfileService.isOpen(player.UserId) then
			push(player, "ready")
		elseif ProfileService.failure(player.UserId) ~= nil then
			push(player, "unavailable")
		else
			push(player, "loading")
		end
	end)
	ack.OnServerEvent:Connect(function(player: Player)
		if not ProfileService.isOpen(player.UserId) then
			push(player, "unavailable")
			return
		end
		local ok, reason = ProfileService.acknowledgeTutorial(player.UserId)
		if not ok then
			push(player, if reason == "unavailable" then "unavailable" else "failed")
			return
		end
		push(player, "saving")
		task.spawn(function()
			local saved = ProfileService.save(player.UserId)
			if player.Parent ~= nil then
				push(player, if saved then "saved" else "failed")
			end
		end)
	end)
end

function TutorialService.refresh(player: Player)
	push(player, "ready")
end

return TutorialService

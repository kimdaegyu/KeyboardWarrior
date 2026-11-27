--!strict
-- Server confirmation that this player has finished or skipped the tutorial.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TutorialRules = require(ReplicatedStorage.Shared.TutorialRules)

local TutorialState = {}

local seen = false
local known = false
local saveState = "loading"
local started = false
local attempt = 0
local serial: number? = nil
local failureReason: string? = nil
local ackRemote: RemoteEvent? = nil
local listeners: {() -> ()} = {}

local function fire()
	for _, listener in table.clone(listeners) do
		listener()
	end
end

function TutorialState.seen(): boolean
	return seen
end

function TutorialState.known(): boolean
	return known
end

function TutorialState.saveState(): string
	return saveState
end

function TutorialState.attempt(): number
	return attempt
end

function TutorialState.serial(): number?
	return serial
end

function TutorialState.failureReason(): string?
	return failureReason
end

function TutorialState.onChanged(listener: () -> ()): () -> ()
	table.insert(listeners, listener)
	return function()
		local index = table.find(listeners, listener)
		if index ~= nil then
			table.remove(listeners, index)
		end
	end
end

function TutorialState.acknowledge()
	local remote = ackRemote
	if remote == nil then
		return
	end
	saveState = "saving"
	fire()
	remote:FireServer()
end

function TutorialState.start()
	if started then
		return
	end
	started = true
	local request = ReplicatedStorage:WaitForChild("TutorialRequest") :: RemoteEvent
	local state = ReplicatedStorage:WaitForChild("TutorialState") :: RemoteEvent
	ackRemote = ReplicatedStorage:WaitForChild("TutorialAck") :: RemoteEvent
	state.OnClientEvent:Connect(function(message: any)
		if type(message) ~= "table" or type(message.saveState) ~= "string" then
			return
		end
		if message.saveState == "loading" and saveState ~= "loading" then
			return
		end
		if type(message.attempt) == "number" then
			attempt = message.attempt
		end
		if type(message.serial) == "number" then
			serial = message.serial
		end
		saveState = message.saveState
		if saveState == "unavailable" and type(message.reason) == "string" and message.reason ~= "" then
			failureReason = message.reason
		elseif saveState == "ready" or saveState == "saved" then
			failureReason = nil
		end
		if saveState ~= "loading" and saveState ~= "unavailable" then
			known = true
			seen = TutorialRules.seenOf(message.seen)
		end
		fire()
	end)
	request:FireServer()
end

return TutorialState

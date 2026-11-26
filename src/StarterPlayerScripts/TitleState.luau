--!strict
-- Server-confirmed owned titles and the equipped id.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TitleState = {}

local reason = "ok"
local mode = "auto"
local equipped = 0
local titles: {number} = {}
local received = false
local started = false
local listeners: {() -> ()} = {}

local function fire()
	for _, listener in table.clone(listeners) do
		listener()
	end
end

function TitleState.reason(): string
	return reason
end

function TitleState.mode(): string
	return mode
end

function TitleState.equipped(): number
	return equipped
end

function TitleState.titles(): {number}
	return titles
end

function TitleState.received(): boolean
	return received
end

function TitleState.listen(callback: () -> ()): () -> ()
	table.insert(listeners, callback)
	return function()
		local index = table.find(listeners, callback)
		if index ~= nil then
			table.remove(listeners, index)
		end
	end
end

local function send(action: string, titleId: number?)
	local remote = ReplicatedStorage:FindFirstChild("TitleRequest")
	if remote == nil or not remote:IsA("RemoteEvent") then
		return
	end
	if titleId == nil then
		remote:FireServer(action)
	else
		remote:FireServer(action, titleId)
	end
end

function TitleState.sync()
	send("sync")
end

function TitleState.equip(titleId: number)
	send("equip", titleId)
end

function TitleState.auto()
	send("auto")
end

function TitleState.bind(): () -> ()
	if started then
		return function() end
	end
	started = true
	local state = ReplicatedStorage:WaitForChild("TitleState")
	assert(state:IsA("RemoteEvent"))
	local connection = state.OnClientEvent:Connect(function(message: any)
		if type(message) ~= "table" then
			return
		end
		local nextTitles: {number} = {}
		if type(message.titles) == "table" then
			for _, id in message.titles do
				if type(id) == "number" then
					table.insert(nextTitles, id)
				end
			end
		end
		received = true
		reason = if type(message.reason) == "string" then message.reason else "ok"
		mode = if message.mode == "manual" then "manual" else "auto"
		equipped = if type(message.equipped) == "number" then message.equipped else 0
		titles = nextTitles
		fire()
	end)
	TitleState.sync()
	return function()
		connection:Disconnect()
	end
end

return TitleState

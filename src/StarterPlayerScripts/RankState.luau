--!strict
-- The latest global board for this client. The server owns the query.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type Row = {
	userId: number,
	name: string,
	score: number,
	rank: number,
	cpm: number?,
	language: string?,
}

local RankState = {}

local status = "loading"
local rows: {Row} = {}
local recorded = false
local bestScore: number? = nil
local received = false
local bestScoreLanguage: string? = nil
local bestScoreCpm: number? = nil
local started = false
local requestRemote: RemoteEvent? = nil
local listeners: {() -> ()} = {}

local function fire()
	for _, listener in table.clone(listeners) do
		listener()
	end
end

function RankState.status(): string
	return status
end

function RankState.rows(): {Row}
	return rows
end

function RankState.recorded(): boolean
	return recorded
end

function RankState.bestScore(): number?
	return bestScore
end

function RankState.received(): boolean
	return received
end

function RankState.onChanged(listener: () -> ()): () -> ()
	table.insert(listeners, listener)
	return function()
		local index = table.find(listeners, listener)
		if index ~= nil then
			table.remove(listeners, index)
		end
	end
end

function RankState.bestScoreLanguage(): string?
	return bestScoreLanguage
end

function RankState.bestScoreCpm(): number?
	return bestScoreCpm
end

function RankState.request()
	if not received or (status == "failed" and #rows == 0) then
		status = "loading"
		fire()
	end
	local remote = requestRemote
	if remote ~= nil then
		remote:FireServer()
	end
end

local function onState(message: any)
	if type(message) ~= "table" or type(message.status) ~= "string" or type(message.rows) ~= "table" then
		return
	end
	local nextRows: {Row} = {}
	for _, row in message.rows do
		if type(row) == "table" and type(row.userId) == "number" and type(row.score) == "number" and type(row.rank) == "number" then
			table.insert(nextRows, {
				userId = row.userId,
				name = if type(row.name) == "string" then row.name else tostring(row.userId),
				score = row.score,
				language = if type(row.language) == "string" then row.language else nil,
				cpm = if type(row.cpm) == "number" then row.cpm else nil,
				rank = row.rank,
			})
		end
	end
	received = true
	status = message.status
	rows = nextRows
	recorded = message.recorded == true
	bestScoreLanguage = if recorded and type(message.bestScoreLanguage) == "string" then message.bestScoreLanguage else nil
	bestScoreCpm = if recorded and type(message.bestScoreCpm) == "number" then message.bestScoreCpm else nil
	bestScore = if recorded and type(message.bestScore) == "number" then message.bestScore else nil
	fire()
end

function RankState.start()
	if started then
		return
	end
	started = true
	requestRemote = ReplicatedStorage:WaitForChild("RankRequest") :: RemoteEvent
	local state = ReplicatedStorage:WaitForChild("RankState") :: RemoteEvent
	state.OnClientEvent:Connect(onState)
end

return RankState

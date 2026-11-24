--!strict
-- Publishes finished best scores and serves one shared top-50 board per server.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local constants = require(ReplicatedStorage.Shared.IngameConstants)
local RankRules = require(ReplicatedStorage.Shared.RankRules)
local DataConfig = require(script.Parent.DataConfig)
local ProfileService = require(script.Parent.ProfileService)

local RankService = {}

local scope = if RunService:IsStudio() then DataConfig.studioScope else DataConfig.liveScope
local store = DataStoreService:GetOrderedDataStore(DataConfig.rankStoreName, scope)
local started = false
local stateEvent: RemoteEvent? = nil
local names: {[number]: string} = {}
local pending: {[number]: number} = {}
local publishing: {[number]: boolean} = {}
local boardRows: {RankRules.Placed}? = nil
local boardAt = 0
local boardFailedAt = -10
local boardStatus = "empty"
local fetching = false
local waiters: {thread} = {}

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

local function playerName(userId: number): string
	local cached = names[userId]
	if cached ~= nil then
		return cached
	end
	local player = Players:GetPlayerByUserId(userId)
	if player ~= nil then
		names[userId] = player.Name
		return player.Name
	end
	local ok, result = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local name = if ok and type(result) == "string" and result ~= "" then result else tostring(userId)
	names[userId] = name
	return name
end

local function publish(userId: number, score: number): boolean
	local ok = pcall(function()
		store:UpdateAsync(tostring(userId), function(previous)
			return RankRules.storedValue(previous, score)
		end)
	end)
	return ok
end

local function pump(userId: number)
	if publishing[userId] then
		return
	end
	publishing[userId] = true
	task.spawn(function()
		local tries = 0
		while pending[userId] ~= nil and tries < 3 do
			local target = pending[userId]
			if publish(userId, target) then
				if pending[userId] == target then
					pending[userId] = nil
				end
				tries = 0
			else
				tries += 1
				if pending[userId] ~= nil and tries < 3 then
					task.wait(2)
				end
			end
		end
		publishing[userId] = false
	end)
end

function RankService.noteSaved(userId: number)
	local profile = ProfileService.read(userId)
	if profile == nil then
		return
	end
	local score, recorded = RankRules.recordOf(profile.bestScore, profile.ranked)
	if not recorded or score == nil then
		return
	end
	local queued = pending[userId]
	pending[userId] = if queued == nil then score else math.max(queued, score)
	pump(userId)
end

local function fetchBoard(): boolean
	local ok, page = pcall(function()
		return store:GetSortedAsync(false, constants.Rank.TopCount):GetCurrentPage()
	end)
	if not ok or type(page) ~= "table" then
		return false
	end
	local entries: {RankRules.Entry} = {}
	for _, item in page do
		if type(item) ~= "table" then
			continue
		end
		local userId = tonumber(item.key)
		local score = item.value
		if type(userId) == "number" and type(score) == "number" then
			table.insert(entries, {
				userId = userId,
				name = playerName(userId),
				score = score,
			})
		end
	end
	boardRows = RankRules.place(entries)
	boardAt = os.clock()
	boardStatus = if #boardRows == 0 then "empty" else "ready"
	return true
end

local function board(): {RankRules.Placed}?
	local now = os.clock()
	if boardRows ~= nil and now - boardAt < constants.Rank.CacheSeconds then
		boardStatus = if #boardRows == 0 then "empty" else "ready"
		return boardRows
	end
	if now - boardFailedAt < 2 then
		return boardRows
	end
	if fetching then
		table.insert(waiters, coroutine.running())
		coroutine.yield()
		return boardRows
	end
	fetching = true
	local ok = fetchBoard()
	if not ok then
		boardFailedAt = os.clock()
		if boardRows ~= nil then
			boardStatus = "stale"
		else
			boardStatus = "failed"
		end
	end
	fetching = false
	local waiting = waiters
	waiters = {}
	for _, thread in waiting do
		task.spawn(thread)
	end
	return boardRows
end

local function payload(userId: number)
	board()
	local profile = ProfileService.read(userId)
	local score, recorded = nil, false
	if profile ~= nil then
		score, recorded = RankRules.recordOf(profile.bestScore, profile.ranked)
	end
	return {
		status = boardStatus,
		rows = boardRows or {},
		recorded = recorded,
		bestScore = score,
	}
end

local function push(player: Player)
	local event = stateEvent
	if event == nil or player.Parent == nil then
		return
	end
	event:FireClient(player, payload(player.UserId))
end

function RankService.start()
	if started then
		return
	end
	started = true
	stateEvent = remote("RankState")
	local request = remote("RankRequest")
	ProfileService.setReadyHandler(function(userId: number)
		RankService.noteSaved(userId)
	end)
	request.OnServerEvent:Connect(function(player: Player)
		push(player)
	end)
end

return RankService

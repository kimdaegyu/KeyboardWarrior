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

local PlayerStore = require(script.Parent.PlayerStore)

local RankService = {}

local scope = if RunService:IsStudio() then DataConfig.studioScope else DataConfig.liveScope
local store = DataStoreService:GetOrderedDataStore(DataConfig.rankStoreName, scope)
local snapshots = require(script.Parent.RankSnapshots).new(store, DataConfig.rankStoreName, scope)
local confirmed: {[number]: number} = {}
local changedAt: {[number]: number} = {}
local started = false
local stateEvent: RemoteEvent? = nil
local names: {[number]: string} = {}
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

local pending: {[number]: number} = {}
local publishing: {[number]: boolean} = {}
local boardRows: {RankRules.Placed}? = nil
local boardAt = 0
local nextBoardCheck = 0
local boardStatus = "loading"
local fetching = false

local function publish(userId: number, score: number): boolean
	local changed = false
	local ok = pcall(function()
		store:UpdateAsync(tostring(userId), function(previous)
			local nextScore = RankRules.storedValue(previous, score)
			changed = nextScore ~= nil
			return nextScore
		end)
	end)
	if ok then
		confirmed[userId] = score
		if changed then changedAt[userId] = os.time() end
	end
	return ok
end

local function noteSaved(userId: number, score: number)
	if not RankRules.shouldPublish(score, confirmed[userId], snapshots.cutoff()) then return end
	pending[userId] = math.max(pending[userId] or score, score)
	if publishing[userId] then return end
	publishing[userId] = true
	task.spawn(function()
		local backoff = 2
		while pending[userId] ~= nil do
			local target = pending[userId]
			if not RankRules.shouldPublish(target, confirmed[userId], snapshots.cutoff()) or publish(userId, target) then
				if pending[userId] == target then pending[userId] = nil end
				backoff = 2
			else
				if not Players:GetPlayerByUserId(userId) then break end
				task.wait(backoff)
				backoff = math.min(backoff * 2, 60)
			end
		end
		publishing[userId] = nil
		if not Players:GetPlayerByUserId(userId) then
			pending[userId], confirmed[userId], changedAt[userId] = nil, nil, nil
		end
	end)
end

-- Reuse offline profile reads across board refreshes. A changed score bypasses the cache.
local details: {[number]: {score: number, cpm: number?, language: string?, expires: number}} = {}
local function scoreDetails(userId: number, score: number): (number?, string?)
	local profile = ProfileService.read(userId)
	if profile then
		if profile.bestScore == score then return profile.bestScoreCpm, profile.bestScoreLanguage end
		return nil, nil
	end
	local cached = details[userId]
	if cached and cached.score == score and os.clock() < cached.expires then
		return cached.cpm, cached.language
	end
	local ok, result = pcall(function()
		return PlayerStore.getDocument(userId):Read()
	end)
	if ok and result.success then
		local data = result.data
		local cpm = if data.bestScore == score then data.bestScoreCpm else nil
		local language = if data.bestScore == score then data.bestScoreLanguage else nil
		details[userId] = {score = score, cpm = cpm, language = language, expires = os.clock() + constants.Rank.CacheSeconds * 5}
		return cpm, language
	end
	if cached and cached.score == score then return cached.cpm, cached.language end
	return nil, nil
end

local function buildBoard(keepLease: (() -> ())?): {RankRules.Placed}
	local ok, page = pcall(function()
		return store:GetSortedAsync(false, constants.Rank.TopCount):GetCurrentPage()
	end)
	if not ok or type(page) ~= "table" then
		error("rank score page unavailable")
	end
	for userId, detail in details do
		if detail.expires <= os.clock() then details[userId] = nil end
	end
	local entries: {RankRules.Entry} = {}
	for _, item in page do
		if keepLease then keepLease() end
		if type(item) ~= "table" then
			continue
		end
		local userId = tonumber(item.key)
		local score = item.value
		if type(userId) == "number" and type(score) == "number" then
			local cpm, language = scoreDetails(userId, score)
			table.insert(entries, {
				userId = userId,
				name = playerName(userId),
				cpm = cpm,
				language = language,
				score = score,
			})
		end
	end
	return RankRules.place(entries)
end

local function refreshBoard()
	local ok, data = pcall(snapshots.top, buildBoard)
	-- If MemoryStore is unavailable, keep serving a server-local board.
	if not ok and (not boardRows or os.time() - boardAt >= constants.Rank.CacheSeconds) then
		local built, rows = pcall(buildBoard)
		if built then data = {rows = rows, at = os.time()} else data = nil end
	end
	if type(data) == "table" and data.at >= boardAt then
		boardRows, boardAt = data.rows, data.at
	end
	nextBoardCheck = os.clock() + (if boardRows and os.time() - boardAt < constants.Rank.CacheSeconds
		then math.max(2, constants.Rank.CacheSeconds - (os.time() - boardAt)) else 5)
	fetching = false
	if not boardRows then boardStatus = if ok then "loading" else "failed" end
end

local function snapshot()
	if os.clock() >= nextBoardCheck and not fetching then
		fetching = true
		if boardRows then
			task.spawn(refreshBoard)
		else
			refreshBoard()
		end
	end
	if boardRows then
		boardStatus = if os.time() - boardAt >= constants.Rank.CacheSeconds then "stale"
			elseif #boardRows == 0 then "empty" else "ready"
	elseif fetching then
		boardStatus = "loading"
	end
	return boardStatus, boardRows or {}
end

function RankService.noteSaved(userId: number)
	local profile = ProfileService.read(userId)
	if not profile then return end
	local score, recorded = RankRules.recordOf(profile.bestScore, profile.ranked)
	if recorded and score ~= nil then
		details[userId] = nil
		noteSaved(userId, score)
	end
end

local function payload(userId: number)
	local status, rows = snapshot()
	local profile = ProfileService.read(userId)
	local best, recorded = nil, false
	if profile then
		best, recorded = RankRules.recordOf(profile.bestScore, profile.ranked)
	end
	local place, outside = nil, false
	if best ~= nil then
		for _, row in rows do
			if row.userId == userId and row.score == best then
				place = row.rank
				break
			end
		end
		if not place then
			place, outside = snapshots.personal(userId, best, confirmed[userId], changedAt[userId])
		end
	end
	return {status = status, rows = rows, recorded = recorded, personalRank = place, outside = outside, bestScore = best, bestScoreLanguage = if profile then profile.bestScoreLanguage else nil, bestScoreCpm = if profile then profile.bestScoreCpm else nil}
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
	task.spawn(function()
		while true do
			local ok, err = pcall(snapshots.refreshIndex)
			if not ok then warn("Global rank index refresh failed", err) end
			task.wait(constants.Rank.CacheSeconds + math.random(0, 10))
		end
	end)
	local lastRequest: {[Player]: number} = {}
	local busy: {[Player]: boolean} = {}
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player], busy[player] = nil, nil
		local id = player.UserId
		if not publishing[id] then confirmed[id], changedAt[id] = nil, nil end
	end)
	request.OnServerEvent:Connect(function(player: Player)
		if busy[player] or os.clock() - (lastRequest[player] or -10) < 2 then return end
		lastRequest[player], busy[player] = os.clock(), true
		local ok, err = pcall(push, player)
		busy[player] = nil
		if not ok then warn("Global rank request failed", err) end
	end)
end

return RankService

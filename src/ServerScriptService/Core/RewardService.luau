--!strict
-- Settles one match from its sealed ranking. Saves never run on the match clock thread.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RewardRules = require(ReplicatedStorage.Shared.RewardRules)
local TableData = require(ReplicatedStorage.Shared.TableData)
local ProfileService = require(script.Parent.ProfileService)
local QuestionService = require(script.Parent.QuestionService)
local RankService = require(script.Parent.RankService)
local ShopService = require(script.Parent.ShopService)
local TitleService = require(script.Parent.TitleService)

type Person = QuestionService.Person

type Pending = {
	language: string,
	cpm: number?,
	settlementId: string,
	gold: number,
	exp: number,
	score: number,
	finished: boolean,
}

local RewardService = {}

local started = false
local rates: RewardRules.Rates? = nil
local levels: {RewardRules.LevelStep}? = nil
local resultEvent: RemoteEvent? = nil
local snapshots: {[string]: any} = {}
local snapshotOrder: {string} = {}
local latest: {[number]: string} = {}
local saveState: {[number]: string} = {}
local waiting: {[number]: Pending} = {}
local saving: {[number]: boolean} = {}

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

local function ensureTables()
	if rates ~= nil and levels ~= nil then
		return
	end
	rates = RewardRules.ratesFromRows(TableData.rows("RewardDataSheet"))
	levels = RewardRules.levelsFromRows(TableData.rows("LevelDataSheet"))
end

local function snapshotFor(userId: number): any?
	local settlementId = latest[userId]
	if settlementId == nil then
		return nil
	end
	return snapshots[settlementId]
end

local function personRecord(snapshot: any, userId: number): Person?
	for _, person in snapshot.rows do
		if person.userId == userId then
			return person
		end
	end
	for _, person in snapshot.departed do
		if person.userId == userId then
			return person
		end
	end
	return nil
end

local function viewFor(userId: number): {[string]: any}?
	local snapshot = snapshotFor(userId)
	if snapshot == nil then
		return nil
	end
	local mine = personRecord(snapshot, userId)
	if mine == nil or not mine.finished then
		return nil
	end
	local rows = table.create(#snapshot.rows)
	for index, person in snapshot.rows do
		rows[index] = {
			userId = person.userId,
			name = person.name,
			language = person.language,
			score = person.score,
			cpm = person.cpm,
			rank = person.rank,
		}
	end
	return {
		settlementId = snapshot.settlementId,
		matchId = snapshot.matchId,
		count = #snapshot.rows,
		rank = mine.rank,
		score = mine.score,
		cpm = mine.cpm,
		language = mine.language,
		titles = mine.titles,
		gold = mine.gold,
		exp = mine.exp,
		level = mine.level,
		totalExp = mine.totalExp,
		floorExp = mine.floorExp,
		nextExp = mine.nextExp,
		saveState = saveState[userId] or mine.saveState,
		rows = rows,
	}
end

local function push(userId: number)
	local event = resultEvent
	local payload = viewFor(userId)
	if event == nil or payload == nil then
		return
	end
	local player = Players:GetPlayerByUserId(userId)
	if player ~= nil then
		event:FireClient(player, payload)
	end
end

local function rememberTotals(person: Person)
	local cache = ProfileService.read(person.userId)
	local steps = levels
	if cache == nil or steps == nil then
		person.level = nil
		person.totalExp = nil
		person.floorExp = nil
		person.nextExp = nil
		return
	end
	local level, floorExp, nextExp = RewardRules.progress(cache.exp, steps)
	person.level = level
	person.totalExp = cache.exp
	person.floorExp = floorExp
	person.nextExp = nextExp
end

local function saveLater(userId: number)
	if saving[userId] then
		return
	end
	saving[userId] = true
	task.spawn(function()
		local saved = ProfileService.save(userId)
		saving[userId] = nil
		if saved then
			RankService.noteSaved(userId)
		end
		if ProfileService.isGone(userId) then
			return
		end
		saveState[userId] = if saved then "saved" else "failed"
		local snapshot = snapshotFor(userId)
		local person = if snapshot ~= nil then personRecord(snapshot, userId) else nil
		if person ~= nil then
			person.saveState = saveState[userId]
			rememberTotals(person)
		end
		push(userId)
	end)
end

local function grant(person: Person, settlementId: string, deferSave: boolean?)
	local currentRates = rates
	if currentRates == nil or settlementId == "" then
		person.saveState = "unavailable"
		saveState[person.userId] = person.saveState
		return
	end
	local player = Players:GetPlayerByUserId(person.userId)
	local friendPercent = if player then player:GetAttribute("FriendBoostPercent") else nil
	local gold, exp = RewardRules.reward(currentRates, person.words, person.sentences, person.finished, friendPercent)
	person.gold = gold
	person.exp = exp
	local ok, status, unlocked = ProfileService.commit(person.userId, settlementId, gold, exp, person.score, person.finished, person.cpm, person.language)
	if unlocked ~= nil then
		person.titles = unlocked
	end
	if ok and player ~= nil then
		TitleService.sync(player)
		ShopService.notify(player)
	end
	if not ok then
		person.saveState = "unavailable"
		saveState[person.userId] = person.saveState
		waiting[person.userId] = {
			settlementId = settlementId,
			gold = gold,
			exp = exp,
			score = person.score,
			cpm = person.cpm,
			language = person.language,
			finished = person.finished,
		}
		return
	end
	waiting[person.userId] = nil
	rememberTotals(person)
	if status == "pending" then
		person.saveState = "pending"
		saveState[person.userId] = person.saveState
		if deferSave ~= true and not ProfileService.isGone(person.userId) then
			saveLater(person.userId)
		end
	elseif saveState[person.userId] == nil then
		person.saveState = "pending"
		saveState[person.userId] = person.saveState
	else
		person.saveState = saveState[person.userId]
	end
end

local function retryWaiting(userId: number)
	local pending = waiting[userId]
	if pending == nil then
		return
	end
	local ok, status, unlocked = ProfileService.commit(userId, pending.settlementId, pending.gold, pending.exp, pending.score, pending.finished, pending.cpm, pending.language)
	if not ok then
		return
	end
	waiting[userId] = nil
	local snapshot = snapshotFor(userId)
	local person = if snapshot ~= nil then personRecord(snapshot, userId) else nil
	if unlocked ~= nil and person ~= nil then
		person.titles = unlocked
	end
	local player = Players:GetPlayerByUserId(userId)
	if player ~= nil then
		TitleService.sync(player)
		ShopService.notify(player)
	end
	if person ~= nil then
		rememberTotals(person)
	end
	if status == "pending" then
		saveState[userId] = "pending"
		if person ~= nil then
			person.saveState = "pending"
		end
		if not ProfileService.isGone(userId) then
			saveLater(userId)
		end
	end
	push(userId)
end

function RewardService.query(userId: number): {[string]: any}?
	local payload = viewFor(userId)
	if payload == nil then
		return nil
	end
	if payload.saveState == "failed" then
		saveLater(userId)
	end
	return payload
end

function RewardService.finalize(captured: QuestionService.Capture)
	ensureTables()
	local rows = RewardRules.displayRows(captured.rows)
	for _, person in rows do
		grant(person, captured.settlementId)
	end
	for _, person in captured.departed do
		grant(person, captured.settlementId)
	end
	snapshots[captured.settlementId] = {
		settlementId = captured.settlementId,
		matchId = captured.matchId,
		rows = rows,
		departed = captured.departed,
	}
	table.insert(snapshotOrder, captured.settlementId)
	while #snapshotOrder > 8 do
		local oldest = table.remove(snapshotOrder, 1)
		if oldest ~= nil then
			snapshots[oldest] = nil
		end
	end
	for _, person in rows do
		latest[person.userId] = captured.settlementId
		push(person.userId)
	end
	for _, person in captured.departed do
		latest[person.userId] = captured.settlementId
	end
end

function RewardService.settleDeparture(userId: number, deferSave: boolean?)
	local preview = QuestionService.preview(userId)
	if preview == nil or rates == nil then
		ensureTables()
		preview = QuestionService.preview(userId)
	end
	if preview == nil or preview.sealed then
		return
	end
	local person: Person = {
		userId = userId,
		name = preview.name,
		language = preview.language,
		rank = 0,
		score = preview.score,
		words = preview.words,
		sentences = preview.sentences,
		finished = false,
		gold = 0,
		exp = 0,
		saveState = "pending",
	}
	grant(person, preview.settlementId, deferSave == true)
end

function RewardService.onPlayerRemoving(userId: number)
	RewardService.settleDeparture(userId, true)
end

function RewardService.read(settlementId: string): any?
	return snapshots[settlementId]
end

function RewardService.start()
	if started then
		return
	end
	started = true
	ensureTables()
	resultEvent = remote("ResultState")
	local request = remote("ResultRequest")
	ProfileService.setReadyHandler(retryWaiting)
	request.OnServerEvent:Connect(function(player: Player)
		local payload = RewardService.query(player.UserId)
		if payload ~= nil and resultEvent ~= nil then
			resultEvent:FireClient(player, payload)
		end
	end)
end

return RewardService

--!strict
-- Serves one shared deck per match. Gold and saved rewards stay outside this service.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local constants = require(ReplicatedStorage.Shared.IngameConstants)
local QuestionRules = require(ReplicatedStorage.Shared.QuestionRules)
local PlaytestMetrics = require(ReplicatedStorage.Shared.PlaytestMetrics)
local RewardRules = require(ReplicatedStorage.Shared.RewardRules)
local SettingsRules = require(ReplicatedStorage.Shared.SettingsRules)
local TableData = require(ReplicatedStorage.Shared.TableData)
local ProfileService = require(script.Parent.ProfileService)
local SettingsService = require(script.Parent.SettingsService)

export type Person = {
	userId: number,
	name: string,
	language: string,
	rank: number,
	score: number,
	words: number,
	sentences: number,
	finished: boolean,
	gold: number,
	exp: number,
	saveState: string,
	level: number?,
	totalExp: number?,
	floorExp: number?,
	nextExp: number?,
}

export type Capture = {
	settlementId: string,
	matchId: number,
	rows: {Person},
	departed: {Person},
}

export type Preview = {
	settlementId: string,
	name: string,
	language: string,
	score: number,
	words: number,
	sentences: number,
	sealed: boolean,
}

local SCORE: QuestionRules.ScoreConfig = {
	doubleSeconds = constants.Match.DoubleScoreSeconds,
	multiplier = constants.Match.EndScoreMultiplier,
}

local QuestionService = {}

local started = false
local deck: {QuestionRules.Prompt} = {}
local round: QuestionRules.Round? = nil
local names: {[number]: string} = {}
local feedbackEvent: RemoteEvent? = nil
local scoreEvent: RemoteEvent? = nil

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

local function ensureDeck()
	if #deck > 0 then
		return
	end
	deck = QuestionRules.deckFromRows(TableData.rows("QuestionDataSheet"), TableData.rows("GradeDataSheet"))
	assert(#deck > 0, "No enabled questions")
end

local function playerName(userId: number): string
	local saved = names[userId]
	if saved ~= nil and saved ~= "" then
		return saved
	end
	local player = Players:GetPlayerByUserId(userId)
	if player == nil then
		return tostring(userId)
	end
	if player.DisplayName ~= "" then
		return player.DisplayName
	end
	return player.Name
end

local function playedLanguage(current: QuestionRules.Round, userId: number): string
	local solver = current.solvers[userId]
	if solver ~= nil then
		return QuestionRules.languageCode(solver.language)
	end
	local left = current.departed[userId]
	if left ~= nil then
		return QuestionRules.languageCode(left.language)
	end
	return QuestionRules.languageCode(nil)
end

local function scoreSnapshot(): {[string]: any}?
	local current = round
	if current == nil then
		return nil
	end
	local order = QuestionRules.leaderboard(current)
	local rows = table.create(#order)
	for index, standing in order do
		rows[index] = {
			userId = standing.userId,
			name = playerName(standing.userId),
			language = playedLanguage(current, standing.userId),
			score = standing.score,
			rank = standing.rank,
		}
	end
	return {
		matchId = current.matchId,
		sealed = current.sealed,
		rows = rows,
	}
end

local function broadcastScores()
	local score = scoreEvent
	local payload = scoreSnapshot()
	local current = round
	if score == nil or payload == nil or current == nil then
		return
	end
	local recipients: {[number]: boolean} = {}
	for userId in current.solvers do
		recipients[userId] = true
	end
	if current.sealed and current.finalOrder ~= nil then
		for _, standing in current.finalOrder do
			recipients[standing.userId] = true
		end
	end
	for userId in recipients do
		local player = Players:GetPlayerByUserId(userId)
		if player ~= nil then
			score:FireClient(player, payload)
		end
	end
end

function QuestionService.start()
	if started then
		return
	end
	started = true
	ensureDeck()
	local request = remote("QuestionRequest")
	local submit = remote("QuestionSubmit")
	local feedback = remote("QuestionFeedback")
	local scoreRequest = remote("ScoreRequest")
	local score = remote("ScoreState")
	feedbackEvent = feedback
	scoreEvent = score

	request.OnServerEvent:Connect(function(player: Player)
		local message = QuestionRules.current(round, player.UserId, Workspace:GetServerTimeNow())
		feedback:FireClient(player, message)
		local payload = scoreSnapshot()
		if payload ~= nil and round ~= nil and round.solvers[player.UserId] ~= nil then
			score:FireClient(player, payload)
		end
	end)

	scoreRequest.OnServerEvent:Connect(function(player: Player)
		local payload = scoreSnapshot()
		if payload ~= nil and round ~= nil and (round.solvers[player.UserId] ~= nil or round.sealed) then
			score:FireClient(player, payload)
		end
	end)

	submit.OnServerEvent:Connect(function(player: Player, matchId: any, issue: any, text: any, method: any)
		if typeof(matchId) ~= "number" or typeof(issue) ~= "number" or typeof(text) ~= "string" then
			return
		end
		local message = QuestionRules.submit(round, player.UserId, matchId, issue, text, Workspace:GetServerTimeNow(), method)
		feedback:FireClient(player, message)
		if message.awarded == true then
			broadcastScores()
		end
	end)

	print(`[KeyboardWarrior] Questions {#deck}`)
end

local function settlementToken(): string
	if game.JobId ~= "" then
		return game.JobId
	end
	return "studio"
end

local function makePerson(userId: number, language: string, rank: number, score: number, words: number, sentences: number, finished: boolean): Person
	return {
		userId = userId,
		name = playerName(userId),
		language = language,
		rank = rank,
		score = score,
		words = words,
		sentences = sentences,
		finished = finished,
		gold = 0,
		exp = 0,
		saveState = "pending",
	}
end

local function capture(current: QuestionRules.Round): Capture
	local outcome = QuestionRules.outcome(current)
	local rows: {Person} = table.create(#outcome.rows)
	for index, person in outcome.rows do
		rows[index] = makePerson(person.userId, person.language, person.rank, person.score, person.words, person.sentences, person.finished)
	end
	local departed: {Person} = table.create(#outcome.departed)
	for index, person in outcome.departed do
		departed[index] = makePerson(person.userId, person.language, person.rank, person.score, person.words, person.sentences, person.finished)
	end
	return {
		settlementId = current.settlementId,
		matchId = current.matchId,
		rows = rows,
		departed = departed,
	}
end

function QuestionService.noteClock()
	local current = round
	if current == nil then
		return
	end
	QuestionRules.noteClock(current, Workspace:GetServerTimeNow())
end

function QuestionService.openMatch(matchId: number, userIds: {number}, endsAt: number)
	if not started then
		QuestionService.start()
	end
	ensureDeck()
	local now = Workspace:GetServerTimeNow()
	local settlementId = RewardRules.settlementId(settlementToken(), matchId, HttpService:GenerateGUID(false))
	local byUser: {[number]: string} = {}
	local catalog = SettingsService.languages()
	for _, userId in ipairs(userIds) do
		local profile = ProfileService.read(userId)
		local saved = if profile ~= nil then profile.typing else nil
		local languageId = SettingsRules.sessionTyping(catalog, saved, SettingsService.isMobile(userId))
		if languageId == "" then
			languageId = "en"
		end
		byUser[userId] = languageId
	end
	round = QuestionRules.begin(deck, matchId, endsAt, userIds, now, SCORE, settlementId, byUser)
	table.clear(names)
	for _, userId in ipairs(userIds) do
		names[userId] = playerName(userId)
	end
	local feedback = feedbackEvent
	if feedback ~= nil then
		for _, userId in ipairs(userIds) do
			local player = Players:GetPlayerByUserId(userId)
			if player ~= nil then
				feedback:FireClient(player, QuestionRules.current(round, userId, now))
			end
		end
	end
	broadcastScores()
end

function QuestionService.closeMatch(): Capture?
	local current = round
	if current == nil or not current.open then
		return nil
	end
	QuestionRules.noteClock(current, Workspace:GetServerTimeNow())
	QuestionRules.close(current)
	QuestionRules.seal(current)
	if RunService:IsStudio() then
		print(PlaytestMetrics.report(current))
	end
	PlaytestMetrics.clear(current.metrics)
	broadcastScores()
	return capture(current)
end

function QuestionService.preview(userId: number): Preview?
	local current = round
	if current == nil then
		return nil
	end
	local solver = current.solvers[userId]
	if solver ~= nil then
		return {
			settlementId = current.settlementId,
			name = playerName(userId),
			language = playedLanguage(current, userId),
			score = solver.score,
			words = solver.wordCount,
			sentences = solver.sentenceCount,
			sealed = current.sealed,
		}
	end
	local left = current.departed[userId]
	if left == nil then
		return nil
	end
	return {
		settlementId = current.settlementId,
		name = playerName(userId),
		language = playedLanguage(current, userId),
		score = left.score,
		words = left.words,
		sentences = left.sentences,
		sealed = current.sealed,
	}
end

function QuestionService.forget(userId: number)
	QuestionRules.forget(round, userId, Workspace:GetServerTimeNow())
	if round ~= nil and not round.sealed then
		broadcastScores()
	end
end

function QuestionService.results(): {QuestionRules.Standing}?
	if round == nil then
		return nil
	end
	return QuestionRules.leaderboard(round)
end

function QuestionService.deckSize(): number
	ensureDeck()
	return #deck
end

return QuestionService

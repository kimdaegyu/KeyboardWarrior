--!strict
-- Serves one shared deck per match. Score and rewards stay outside this service.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local QuestionRules = require(ReplicatedStorage.Shared.QuestionRules)
local TableData = require(ReplicatedStorage.Shared.TableData)

local QuestionService = {}

local started = false
local deck: {QuestionRules.Prompt} = {}
local round: QuestionRules.Round? = nil
local feedbackEvent: RemoteEvent? = nil

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
	deck = QuestionRules.deckFromRows(TableData.rows("QuestionDataSheet"))
	assert(#deck > 0, "No enabled questions")
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
	feedbackEvent = feedback

	request.OnServerEvent:Connect(function(player: Player)
		local message = QuestionRules.current(round, player.UserId, Workspace:GetServerTimeNow())
		feedback:FireClient(player, message)
	end)

	submit.OnServerEvent:Connect(function(player: Player, matchId: any, issue: any, text: any)
		if typeof(matchId) ~= "number" or typeof(issue) ~= "number" or typeof(text) ~= "string" then
			return
		end
		local message = QuestionRules.submit(round, player.UserId, matchId, issue, text, Workspace:GetServerTimeNow())
		feedback:FireClient(player, message)
	end)

	print(`[KeyboardWarrior] Questions {#deck}`)
end

function QuestionService.openMatch(matchId: number, userIds: {number}, endsAt: number)
	if not started then
		QuestionService.start()
	end
	ensureDeck()
	round = QuestionRules.begin(deck, matchId, endsAt, userIds)
	local feedback = feedbackEvent
	if feedback == nil then
		return
	end
	local now = Workspace:GetServerTimeNow()
	for _, userId in ipairs(userIds) do
		local player = Players:GetPlayerByUserId(userId)
		if player ~= nil then
			feedback:FireClient(player, QuestionRules.current(round, userId, now))
		end
	end
end

function QuestionService.closeMatch()
	QuestionRules.close(round)
end

function QuestionService.forget(userId: number)
	QuestionRules.forget(round, userId)
end

function QuestionService.deckSize(): number
	ensureDeck()
	return #deck
end

return QuestionService

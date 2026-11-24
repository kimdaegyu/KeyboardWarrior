--!strict
-- Server clock for rest → play → result. Clients read the same phase end time.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local constants = require(ReplicatedStorage.Shared.IngameConstants)
local MatchRules = require(ReplicatedStorage.Shared.MatchRules)
local ArenaService = require(script.Parent.ArenaService)
local ShopService = require(script.Parent.ShopService)
local ProfileService = require(script.Parent.ProfileService)
local QuestionService = require(script.Parent.QuestionService)
local RewardService = require(script.Parent.RewardService)

local MATCH = constants.Match

type Phase = "Rest" | "Play" | "Result"

type Assignment = {
	padIndex: number,
	slot: number,
	characterConn: RBXScriptConnection?,
}

local NEXT_PHASE: {[Phase]: Phase} = {
	Rest = "Play",
	Play = "Result",
	Result = "Rest",
}

local PHASE_SECONDS: {[Phase]: number} = {
	Rest = MATCH.RestSeconds,
	Play = MATCH.PlaySeconds,
	Result = MATCH.ResultSeconds,
}

local MatchService = {}

local started = false
local phase: Phase = "Rest"
local phaseEndsAt = 0
local cycleId = 0
local matchId = 0
local participantCount = 0
local waitingStarted: {[Player]: number} = {}
local assignments: {[Player]: Assignment} = {}
local state: Folder? = nil
local random = Random.new()

local function publish()
	local folder = state
	if folder == nil then
		return
	end
	folder:SetAttribute("Phase", phase)
	folder:SetAttribute("PhaseEndsAt", phaseEndsAt)
	folder:SetAttribute("CycleId", cycleId)
	folder:SetAttribute("MatchId", matchId)
	folder:SetAttribute("ParticipantCount", participantCount)
	folder:SetAttribute("MaxParticipants", MATCH.MaxParticipants)
	local waitingCount = 0
	for _ in waitingStarted do
		waitingCount += 1
	end
	folder:SetAttribute("WaitingCount", waitingCount)
end

local function playerPosition(player: Player): Vector3?
	local character = player.Character
	if character == nil then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return nil
	end
	return root.Position
end

local function refreshZone()
	local seen: {[Player]: boolean} = {}
	for _, player in Players:GetPlayers() do
		seen[player] = true
		local position = playerPosition(player)
		local inside = position ~= nil and ArenaService.isInsideJoinZone(position)
		if inside then
			if waitingStarted[player] == nil then
				waitingStarted[player] = Workspace:GetServerTimeNow()
			end
		else
			waitingStarted[player] = nil
		end
		if player:GetAttribute("InJoinZone") ~= inside then
			player:SetAttribute("InJoinZone", inside)
		end
	end
	local stale = {}
	for player in waitingStarted do
		if not seen[player] then
			table.insert(stale, player)
		end
	end
	for _, player in ipairs(stale) do
		waitingStarted[player] = nil
	end
	local folder = state
	if folder == nil then
		return
	end
	local waitingCount = 0
	for _ in waitingStarted do
		waitingCount += 1
	end
	if folder:GetAttribute("WaitingCount") ~= waitingCount then
		folder:SetAttribute("WaitingCount", waitingCount)
	end
end

local function collectCandidates(): {MatchRules.Candidate}
	local candidates = {}
	for _, player in Players:GetPlayers() do
		local startedAt = waitingStarted[player]
		if startedAt ~= nil then
			table.insert(candidates, {
				userId = player.UserId,
				inZone = true,
				waitStartedAt = startedAt,
			})
		end
	end
	return candidates
end

local function disconnectAssignment(assignment: Assignment)
	if assignment.characterConn ~= nil then
		assignment.characterConn:Disconnect()
	end
end

local function clearAssignments()
	ArenaService.undressAll()
	for player, assignment in assignments do
		disconnectAssignment(assignment)
		player:SetAttribute("InMatch", false)
	end
	table.clear(assignments)
	participantCount = 0
	matchId = 0
end

local function placeAssigned(player: Player, assignment: Assignment, character: Model)
	if assignments[player] ~= assignment or character.Parent == nil then
		return
	end
	if character:FindFirstChild("HumanoidRootPart") == nil or character:FindFirstChildOfClass("Humanoid") == nil then
		task.defer(function()
			if assignments[player] ~= assignment or character.Parent == nil then
				return
			end
			character:WaitForChild("HumanoidRootPart", 5)
			character:WaitForChild("Humanoid", 5)
			if assignments[player] == assignment and character.Parent ~= nil then
				ArenaService.placeOnPad(character, assignment.padIndex)
			end
		end)
		return
	end
	ArenaService.placeOnPad(character, assignment.padIndex)
end

local function watchPad(player: Player, assignment: Assignment)
	if player.Character ~= nil then
		placeAssigned(player, assignment, player.Character)
	end
	assignment.characterConn = player.CharacterAdded:Connect(function(character)
		placeAssigned(player, assignment, character)
	end)
end

local function lockParticipants()
	refreshZone()
	local selected = MatchRules.selectParticipants(collectCandidates(), MATCH.MaxParticipants, MATCH.MinParticipants)
	cycleId += 1
	clearAssignments()
	if #selected == 0 then
		-- The pilot clock still advances. No pads, rewards, or participant snapshot.
		matchId = 0
		participantCount = 0
		return
	end
	matchId = cycleId
	participantCount = #selected
	local padByUser = MatchRules.assignPads(selected, MATCH.MaxParticipants, random)
	local byUserId: {[number]: Player} = {}
	for _, player in Players:GetPlayers() do
		byUserId[player.UserId] = player
	end
	local participants: {number} = {}
	for slot, userId in ipairs(selected) do
		local player = byUserId[userId]
		local padIndex = padByUser[userId]
		if player ~= nil and padIndex ~= nil then
			local assignment: Assignment = {
				padIndex = padIndex,
				slot = slot,
			}
			assignments[player] = assignment
			player:SetAttribute("InMatch", true)
			ArenaService.dress(padIndex, ShopService.paintFor(userId))
			watchPad(player, assignment)
			table.insert(participants, userId)
		end
	end
	refreshZone()
	if #participants > 0 then
		QuestionService.openMatch(matchId, participants, phaseEndsAt)
	end
end

local function releaseParticipants()
	local leaving = assignments
	assignments = {}
	local total = 0
	for _ in leaving do
		total += 1
	end
	for player, assignment in leaving do
		disconnectAssignment(assignment)
		ArenaService.undress(assignment.padIndex)
		player:SetAttribute("InMatch", false)
		local character = player.Character
		if character ~= nil and player.Parent ~= nil then
			ArenaService.placeInLobby(character, assignment.slot, total)
		end
	end
	participantCount = 0
	matchId = 0
	refreshZone()
end

local function enter(nextPhase: Phase)
	local previous = phase
	if previous == "Play" then
		local captured = QuestionService.closeMatch()
		if captured ~= nil then
			RewardService.finalize(captured)
		end
	end
	phase = nextPhase
	local duration = PHASE_SECONDS[nextPhase]
	local now = Workspace:GetServerTimeNow()
	-- Extend the scheduled end so a late wakeup does not shift the shared clock.
	local nextEnd = phaseEndsAt + duration
	if nextEnd < now then
		nextEnd = now + duration
	end
	phaseEndsAt = nextEnd
	if nextPhase == "Play" then
		lockParticipants()
	elseif nextPhase == "Rest" and previous == "Result" then
		releaseParticipants()
	end
	publish()
	print(
		`[KeyboardWarrior] {phase} endsAt={string.format("%.3f", phaseEndsAt)} participants={participantCount}`
	)
end

local function advance()
	enter(NEXT_PHASE[phase])
end

function MatchService.start()
	if started then
		return
	end
	started = true
	assert(RunService:IsServer(), "MatchService runs on the server")
	QuestionService.start()
	ArenaService.start()
	local folder = ReplicatedStorage:FindFirstChild("MatchState")
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = "MatchState"
		folder.Parent = ReplicatedStorage
	end
	state = folder :: Folder
	-- Pilot: the server opens on the rest window so late joins wait for the next start.
	phase = "Rest"
	phaseEndsAt = Workspace:GetServerTimeNow() + PHASE_SECONDS.Rest
	refreshZone()
	publish()
	print(`[KeyboardWarrior] {phase} endsAt={string.format("%.3f", phaseEndsAt)} participants={participantCount}`)

	Players.PlayerRemoving:Connect(function(player)
		local assignment = assignments[player]
		if assignment ~= nil then
			disconnectAssignment(assignment)
			ArenaService.undress(assignment.padIndex)
			assignments[player] = nil
		end
		waitingStarted[player] = nil
		RewardService.onPlayerRemoving(player.UserId)
		QuestionService.forget(player.UserId)
		player:SetAttribute("InJoinZone", nil)
		player:SetAttribute("InMatch", nil)
		publish()
		ProfileService.close(player.UserId)
	end)

	RunService.Heartbeat:Connect(function()
		refreshZone()
		if phase == "Play" then
			QuestionService.noteClock()
		end
	end)

	task.spawn(function()
		while true do
			local remain = phaseEndsAt - Workspace:GetServerTimeNow()
			if remain > 0 then
				task.wait(remain)
			end
			if Workspace:GetServerTimeNow() + 0.001 < phaseEndsAt then
				continue
			end
			advance()
		end
	end)
end

return MatchService

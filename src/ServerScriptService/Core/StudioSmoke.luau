--!strict
-- Run from the Studio server command bar during Play.
return function()
	assert(game:GetService("RunService"):IsStudio(), "Studio only")
	local shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
	local constants = require(shared.IngameConstants)
	local match = constants.Match
	local arena = constants.Arena
	assert(match.MinParticipants == 1 and match.MaxParticipants == 12)
	assert(arena.Diameter == 100 and arena.PadDiameter == 12 and arena.PadGap == 4)
	assert(math.abs(arena.PadCenterRadius - 30.91) < 0.01)
	assert(arena.PadCenterRadius + arena.PadDiameter / 2 <= arena.Diameter / 2)
	assert(match.PlaySeconds + match.ResultSeconds + match.RestSeconds == 180)
	local tables = require(shared.TableData)
	local grades = {}
	for _, row in tables.rows("GradeDataSheet") do
		grades[row.Id] = true
	end
	local enabled = 0
	for _, row in tables.rows("QuestionDataSheet") do
		assert(grades[row.GradeId], row.Id)
		if row.Enabled == "1" then
			assert(tonumber(row.Score) and row.en ~= "", row.Id)
			enabled += 1
		end
	end
	assert(enabled > 0)
	local icons = require(shared.ItemIconUtil)
	for _, row in tables.rows("ItemDataSheet") do
		assert(icons.get(assert(tonumber(row.Id))), row.Id)
	end
	local panel = require(shared.UIImageUtil).get("panel-9slice")
	assert(panel and panel.HasAtlas and panel.SliceCenter)
	local config = require(script.Parent.DataConfig)
	assert(config.check(config.default))
	assert(not config.check({ schemaVersion = 1, gold = -1, exp = 0, bestScore = 0 }))
	assert(config.studioScope ~= config.liveScope)
	local rules = require(shared.MatchRules)
	rules.selfCheck(constants)
	local arenaModel = workspace:FindFirstChild("Arena")
	assert(arenaModel ~= nil and arenaModel:IsA("Folder"), "Workspace.Arena")
	local join = arenaModel:FindFirstChild("JoinZone", true)
	local center = arenaModel:FindFirstChild("ArenaCenter", true)
	local lobby = arenaModel:FindFirstChild("LobbySpawn", true)
	assert(join ~= nil and join:IsA("BasePart"), "Workspace.Arena.JoinZone")
	assert(center ~= nil and center:IsA("BasePart"), "Workspace.Arena.ArenaCenter")
	assert(lobby ~= nil and lobby:IsA("SpawnLocation"), "Workspace.Arena.LobbySpawn")
	local ArenaService = require(script.Parent.ArenaService)
	assert(ArenaService.isInsideJoinZone(join.Position + Vector3.new(0, 3, 0)), "join center")
	local away = Vector3.new(join.CFrame.UpVector.X, 0, join.CFrame.UpVector.Z)
	if away.Magnitude < 0.1 then
		away = Vector3.new(1, 0, 0)
	end
	local outside = join.Position + away.Unit * (math.max(join.Size.X, join.Size.Y, join.Size.Z) + 4) + Vector3.new(0, 3, 0)
	assert(not ArenaService.isInsideJoinZone(outside), "outside join")
	assert(not ArenaService.isInsideJoinZone(lobby.Position + Vector3.new(0, 3, 0)), "lobby spawn is outside the circle")
	local padFolder = arenaModel:FindFirstChild("Pads")
	assert(padFolder ~= nil and #padFolder:GetChildren() == match.MaxParticipants, "12 pads")
	local first = padFolder:FindFirstChild("Pad01")
	local second = padFolder:FindFirstChild("Pad02")
	assert(first ~= nil and second ~= nil and first:IsA("BasePart") and second:IsA("BasePart"))
	local centerFlat = Vector3.new(center.Position.X, 0, center.Position.Z)
	local firstFlat = Vector3.new(first.Position.X, 0, first.Position.Z)
	local secondFlat = Vector3.new(second.Position.X, 0, second.Position.Z)
	assert(math.abs((firstFlat - centerFlat).Magnitude - arena.PadCenterRadius) < 0.05, "pad radius")
	assert(math.abs((firstFlat - secondFlat).Magnitude - (arena.PadDiameter + arena.PadGap)) < 0.05, "pad gap")
	local yExtent = math.abs(first.CFrame.RightVector.Y) * first.Size.X
		+ math.abs(first.CFrame.UpVector.Y) * first.Size.Y
		+ math.abs(first.CFrame.LookVector.Y) * first.Size.Z
	assert(math.abs(yExtent - 1) < 0.05, "pad lies flat")
	local identity = {}
	for _, child in padFolder:GetChildren() do
		identity[child] = true
	end
	ArenaService.ensurePads()
	local kept = 0
	for _, child in padFolder:GetChildren() do
		assert(identity[child], "pad instance was recreated")
		kept += 1
	end
	assert(kept == match.MaxParticipants, "next match keeps 12 pads")
	local state = game:GetService("ReplicatedStorage"):FindFirstChild("MatchState")
	assert(state ~= nil and typeof(state:GetAttribute("PhaseEndsAt")) == "number", "shared phase end")
	assert(state:GetAttribute("MaxParticipants") == match.MaxParticipants)
	local phaseName = state:GetAttribute("Phase")
	assert(phaseName == "Rest" or phaseName == "Play" or phaseName == "Result", "phase")
	local questionRows = tables.rows("QuestionDataSheet")
	require(shared.QuestionRules).selfCheck(questionRows)
	require(shared.TypingLayout).selfCheck()
	local questions = require(script.Parent.QuestionService)
	assert(questions.deckSize() == enabled, "question deck")
	local request = game:GetService("ReplicatedStorage"):FindFirstChild("QuestionRequest")
	local submit = game:GetService("ReplicatedStorage"):FindFirstChild("QuestionSubmit")
	local feedback = game:GetService("ReplicatedStorage"):FindFirstChild("QuestionFeedback")
	assert(request ~= nil and request:IsA("RemoteEvent"), "QuestionRequest")
	assert(submit ~= nil and submit:IsA("RemoteEvent"), "QuestionSubmit")
	assert(feedback ~= nil and feedback:IsA("RemoteEvent"), "QuestionFeedback")
	print("[KeyboardWarrior] Core smoke passed", enabled, "enabled questions")
end

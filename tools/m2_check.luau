--!strict
local fs = require("@lune/fs")
local Gloss = require("../src/ReplicatedStorage/Shared/Gloss")
local HangulInput = require("../src/ReplicatedStorage/Shared/HangulInput")
local InputPress = require("../src/ReplicatedStorage/Shared/InputPress")
local PracticeRules = require("../src/ReplicatedStorage/Shared/PracticeRules")
local SettingsLayout = require("../src/ReplicatedStorage/Shared/SettingsLayout")
local TutorialLayout = require("../src/ReplicatedStorage/Shared/TutorialLayout")
local TutorialRules = require("../src/ReplicatedStorage/Shared/TutorialRules")
local SettingsRules = require("../src/ReplicatedStorage/Shared/SettingsRules")
local QuestionRules = require("../src/ReplicatedStorage/Shared/QuestionRules")
local ResultLayout = require("../src/ReplicatedStorage/Shared/ResultLayout")
local RankLayout = require("../src/ReplicatedStorage/Shared/RankLayout")
local ShopLayout = require("../src/ReplicatedStorage/Shared/ShopLayout")
local ShopRules = require("../src/ReplicatedStorage/Shared/ShopRules")
local TitleRules = require("../src/ReplicatedStorage/Shared/TitleRules")
local RankRules = require("../src/ReplicatedStorage/Shared/RankRules")
local RewardRules = require("../src/ReplicatedStorage/Shared/RewardRules")
local TypingLayout = require("../src/ReplicatedStorage/Shared/TypingLayout")
local FloorRules = require("../src/ReplicatedStorage/Shared/FloorRules")

local function readSheet(path: string): {QuestionRules.SheetRow}
	local content = string.gsub(fs.readFile(path), "\r\n", "\n")
	local lines = string.split(content, "\n")
	local headers = string.split(lines[1], ",")
	local rows: {QuestionRules.SheetRow} = {}
	for index = 2, #lines do
		local line = lines[index]
		if line ~= "" then
			local values = string.split(line, ",")
			local row: QuestionRules.SheetRow = {
				Id = "",
				Enabled = "",
				en = "",
				Score = "",
				GradeId = "",
				Kind = "",
			}
			for column, header in ipairs(headers) do
				if header == "Id" or header == "Enabled" or header == "en" or header == "ko" or header == "Score" or header == "GradeId" or header == "Kind" then
					row[header] = values[column] or ""
				end
			end
			table.insert(rows, row)
		end
	end
	return rows
end

local function readGrades(path: string): {QuestionRules.GradeRow}
	local content = string.gsub(fs.readFile(path), "\r\n", "\n")
	local lines = string.split(content, "\n")
	local headers = string.split(lines[1], ",")
	local rows: {QuestionRules.GradeRow} = {}
	for index = 2, #lines do
		local line = lines[index]
		if line ~= "" then
			local values = string.split(line, ",")
			local row: QuestionRules.GradeRow = { Id = "", ColorHex = "" }
			for column, header in ipairs(headers) do
				if header == "Id" or header == "ColorHex" then
					row[header] = values[column] or ""
				end
			end
			table.insert(rows, row)
		end
	end
	return rows
end

local rows = readSheet("src/ReplicatedStorage/Shared/Table/QuestionDataSheet.txt")
local grades = readGrades("src/ReplicatedStorage/Shared/Table/GradeDataSheet.txt")
local enabled = {}
for _, row in ipairs(rows) do
	if row.Enabled == "1" then
		table.insert(enabled, row.en)
	end
end
assert(enabled[1] == "apple" and enabled[2] == "star" and enabled[3] == "we play together", "the original prompts stay first")
local scores = {}
for _, row in ipairs(rows) do
	if row.Enabled == "1" then
		table.insert(scores, tonumber(row.Score))
	end
end
assert(scores[1] == 10 and scores[2] == 10 and scores[3] == 25, "sample scores")
QuestionRules.selfCheck(rows, grades)
TypingLayout.selfCheck()
FloorRules.selfCheck()
PracticeRules.selfCheck(rows)
SettingsRules.selfCheck()
SettingsLayout.selfCheck()
local glossRows: {Gloss.Row} = {}
for _, row in rows do
	table.insert(glossRows, { Id = row.Id, ko = (row :: any).ko, en = row.en })
end
Gloss.selfCheck(glossRows)
HangulInput.selfCheck()
InputPress.selfCheck()
assert(Gloss.textFor(glossRows, "1", "ko") == "사과", "apple's meaning is on its own row")
assert(Gloss.textFor(glossRows, "apple", "ko") == nil, "the English prompt is not the meaning key")
assert(Gloss.textFor(glossRows, "2", "ko") == "별", "star's meaning is on its own row")
assert(Gloss.textFor(glossRows, "2", "en") == "star", "a meaning column follows the selected language")
assert(Gloss.textFor(glossRows, "3", "ko") == "우리는 함께 놀아요", "the sentence meaning stays on its id")

local function readLanguages(path: string): {SettingsRules.Row}
	local content = string.gsub(fs.readFile(path), "\r\n", "\n")
	local lines = string.split(content, "\n")
	local headers = string.split(lines[1], ",")
	local sheet: {SettingsRules.Row} = {}
	for index = 2, #lines do
		local line = lines[index]
		if line ~= "" then
			local values = string.split(line, ",")
			local row: SettingsRules.Row = {
				Id = "",
				NativeName = "",
				SortOrder = "",
				UiEnabled = "",
				PcTypingEnabled = "",
				MobileTypingEnabled = "",
				GlossEnabled = "",
			}
			for column, header in ipairs(headers) do
				if header == "Id" or header == "NativeName" or header == "SortOrder" or header == "UiEnabled" or header == "PcTypingEnabled" or header == "MobileTypingEnabled" or header == "GlossEnabled" then
					row[header] = values[column] or ""
				end
			end
			table.insert(sheet, row)
		end
	end
	return sheet
end

local languageRows = readLanguages("src/ReplicatedStorage/Shared/Table/LanguageDataSheet.txt")
local loadedLanguages, languageReason = SettingsRules.catalog(languageRows)
assert(languageReason == "ok" and loadedLanguages ~= nil, "language sheet")
local loaded = loadedLanguages :: {SettingsRules.Language}
assert(loaded[1].id == "en" and loaded[1].nativeName == "English" and loaded[1].ui and loaded[1].pcTyping and loaded[1].mobileTyping and loaded[1].gloss, "English flags")
assert(loaded[2].id == "ko" and loaded[2].nativeName == "한국어" and loaded[2].ui and loaded[2].gloss and loaded[2].pcTyping and not loaded[2].mobileTyping, "Korean flags")
assert(#SettingsRules.typingChoices(loaded, false) == 2 and #SettingsRules.typingChoices(loaded, true) == 1, "PC typing follows the sheet and mobile stays on its own flag")
TutorialRules.selfCheck()
TutorialLayout.selfCheck()
RankRules.selfCheck()
RankLayout.selfCheck()
ShopRules.selfCheck()
TitleRules.selfCheck()
ShopLayout.selfCheck()

local function readTutorial(path: string): {TutorialRules.Row}
	local content = string.gsub(fs.readFile(path), "\r\n", "\n")
	local lines = string.split(content, "\n")
	local headers = string.split(lines[1], ",")
	local sheet: {TutorialRules.Row} = {}
	for index = 2, #lines do
		local line = lines[index]
		if line ~= "" then
			local values = string.split(line, ",")
			local row: TutorialRules.Row = {
				Id = "",
				SortOrder = "",
				TitleKey = "",
				BodyKey = "",
				Enabled = "",
			}
			for column, header in ipairs(headers) do
				if header == "Id" or header == "SortOrder" or header == "TitleKey" or header == "BodyKey" or header == "Enabled" then
					row[header] = values[column] or ""
				end
			end
			table.insert(sheet, row)
		end
	end
	return sheet
end

local tutorialRows = readTutorial("src/ReplicatedStorage/Shared/Table/TutorialDataSheet.txt")
local tutorialSteps, tutorialReason = TutorialRules.catalog(tutorialRows)
assert(tutorialReason == "ok" and tutorialSteps ~= nil, "tutorial sheet")
local tutorialActive = TutorialRules.active(tutorialSteps :: {TutorialRules.Step})
assert(#tutorialActive == 4 and tutorialActive[1].id == "join" and tutorialActive[4].id == "shop", "four tutorial pages are active")
assert(TutorialRules.progress(1, #tutorialActive) == "1/4" and TutorialRules.progress(4, #tutorialActive) == "4/4", "the live counter includes the shop page")
local practiceWords, practiceSentences = PracticeRules.catalog(rows)
assert(practiceWords[1].text == "apple" and practiceWords[2].text == "star", "word practice keeps the original words first")
assert(practiceSentences[1].text == "we play together", "sentence practice keeps the original sentence first")
ResultLayout.selfCheck()

local function readPlain(path: string): {RewardRules.RewardRow}
	local content = string.gsub(fs.readFile(path), "\r\n", "\n")
	local lines = string.split(content, "\n")
	local headers = string.split(lines[1], ",")
	local sheet: {RewardRules.RewardRow} = {}
	for index = 2, #lines do
		local line = lines[index]
		if line ~= "" then
			local values = string.split(line, ",")
			local row: RewardRules.RewardRow = { Id = "", Gold = "", Exp = "" }
			for column, header in ipairs(headers) do
				if header == "Id" or header == "Gold" or header == "Exp" or header == "TotalExp" then
					if header == "TotalExp" then
						row.Exp = values[column] or ""
					else
						row[header] = values[column] or ""
					end
				end
			end
			table.insert(sheet, row)
		end
	end
	return sheet
end

local rewardRows = readPlain("src/ReplicatedStorage/Shared/Table/RewardDataSheet.txt")
local levelRows: {RewardRules.LevelRow} = {}
for _, row in readPlain("src/ReplicatedStorage/Shared/Table/LevelDataSheet.txt") do
	table.insert(levelRows, { Id = row.Id, TotalExp = row.Exp })
end
RewardRules.selfCheck(rewardRows, levelRows)
local PlaytestMetrics = require("../src/ReplicatedStorage/Shared/PlaytestMetrics")
PlaytestMetrics.selfCheck(QuestionRules)
local constants = require("../src/ReplicatedStorage/Shared/IngameConstants")
local MatchRegression = require("../src/ReplicatedStorage/Shared/MatchRegression")
local function readLanguage(path: string): {SettingsRules.Row}
	local content = string.gsub(fs.readFile(path), "\r\n", "\n")
	local lines = string.split(content, "\n")
	local headers = string.split(lines[1], ",")
	local sheet: {SettingsRules.Row} = {}
	for index = 2, #lines do
		local line = lines[index]
		if line ~= "" then
			local values = string.split(line, ",")
			local row: SettingsRules.Row = {
				Id = "",
				NativeName = "",
				SortOrder = "",
				UiEnabled = "",
				PcTypingEnabled = "",
				MobileTypingEnabled = "",
				GlossEnabled = "",
			}
			for column, header in ipairs(headers) do
				if header == "Id" or header == "NativeName" or header == "SortOrder" or header == "UiEnabled" or header == "PcTypingEnabled" or header == "MobileTypingEnabled" or header == "GlossEnabled" then
					row[header] = values[column] or ""
				end
			end
			table.insert(sheet, row)
		end
	end
	return sheet
end
MatchRegression.selfCheck(rows, grades, rewardRows, readLanguage("src/ReplicatedStorage/Shared/Table/LanguageDataSheet.txt"), constants)
print("PASS m2 question rules")

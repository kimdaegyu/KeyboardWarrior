--!strict
-- Applied settings for this client. The settings screen owns unsent edits.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Gloss = require(ReplicatedStorage.Shared.Gloss)
local Localization = require(ReplicatedStorage.Shared.Localization)
local SettingsRules = require(ReplicatedStorage.Shared.SettingsRules)
local TableData = require(ReplicatedStorage.Shared.TableData)

export type Choice = {
	uiLocale: string,
	gloss: string,
	typing: string,
}

local SettingsState = {}

local questions = TableData.rows("QuestionDataSheet")
local languageRows = TableData.rows("LanguageDataSheet") :: {SettingsRules.Row}
local languages, languageReason = SettingsRules.catalog(languageRows)
assert(languages ~= nil, languageReason)
local languageList = languages :: {SettingsRules.Language}
local applied: Choice = {
	uiLocale = "auto",
	gloss = "off",
	typing = SettingsRules.shownTyping(languageList, nil),
}
local saveState = "loading"
local started = false
local applyRemote: RemoteEvent? = nil
local deviceRemote: RemoteEvent? = nil
local listeners: {() -> ()} = {}

local function fire()
	for _, listener in table.clone(listeners) do
		listener()
	end
end

local function publishLocale()
	local choice = if applied.uiLocale == "auto" then nil else applied.uiLocale
	Localization.setPreferredLocale(choice)
end

function SettingsState.languages(): {SettingsRules.Language}
	return languageList
end

function SettingsState.applied(): Choice
	return { uiLocale = applied.uiLocale, gloss = applied.gloss, typing = applied.typing }
end

function SettingsState.sessionTyping(): string
	return SettingsRules.sessionTyping(languageList, applied.typing, UserInputService.TouchEnabled)
end

function SettingsState.saveState(): string
	return saveState
end

function SettingsState.glossText(questionId: string): string
	local column = applied.gloss
	if column == "off" then
		return ""
	end
	return Gloss.textFor(questions, questionId, column) or ""
end

function SettingsState.onChanged(listener: () -> ()): () -> ()
	table.insert(listeners, listener)
	return function()
		local index = table.find(listeners, listener)
		if index ~= nil then
			table.remove(listeners, index)
		end
	end
end

local function reportDevice()
	local remote = deviceRemote
	if remote ~= nil then
		remote:FireServer(UserInputService.TouchEnabled)
	end
end

function SettingsState.apply(uiLocale: string, gloss: string, typing: string)
	local remote = applyRemote
	if remote == nil then
		return
	end
	saveState = "saving"
	fire()
	remote:FireServer(uiLocale, gloss, typing)
end

function SettingsState.start()
	if started then
		return
	end
	started = true
	local request = ReplicatedStorage:WaitForChild("SettingsRequest") :: RemoteEvent
	local state = ReplicatedStorage:WaitForChild("SettingsState") :: RemoteEvent
	applyRemote = ReplicatedStorage:WaitForChild("SettingsApply") :: RemoteEvent
	deviceRemote = ReplicatedStorage:WaitForChild("TypingDevice") :: RemoteEvent
	reportDevice()
	state.OnClientEvent:Connect(function(message: any)
		if type(message) ~= "table" or type(message.saveState) ~= "string" then
			return
		end
		if message.saveState == "loading" and saveState ~= "loading" then
			return
		end
		applied = {
			uiLocale = SettingsRules.shownUi(languageList, message.uiLocale),
			gloss = SettingsRules.shownGloss(languageList, message.gloss),
			typing = SettingsRules.shownTyping(languageList, message.typing),
		}
		saveState = message.saveState
		if saveState ~= "loading" then
			publishLocale()
		end
		reportDevice()
		fire()
	end)
	request:FireServer()
end

return SettingsState

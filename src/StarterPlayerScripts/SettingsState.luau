--!strict
-- Applied settings for this client. Unsent edits wait here so closing the screen cannot drop them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Gloss = require(ReplicatedStorage.Shared.Gloss)
local Localization = require(ReplicatedStorage.Shared.Localization)
local SettingsRules = require(ReplicatedStorage.Shared.SettingsRules)
local TableData = require(ReplicatedStorage.Shared.TableData)
local SoundManager = require(script.Parent.SoundManager)

export type Choice = {
	uiLocale: string,
	gloss: string,
	typing: string,
	bgmVolume: number,
	sfxVolume: number,
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
	bgmVolume = 100,
	sfxVolume = 100,
}
local saveState = "loading"
local started = false
local awaiting = false
local pending: Choice? = nil
local sent: Choice? = nil
local debounce: thread? = nil
local applyRemote: RemoteEvent? = nil
local deviceRemote: RemoteEvent? = nil
local listeners: {() -> ()} = {}

local function copyChoice(choice: Choice): Choice
	return {
		uiLocale = choice.uiLocale,
		gloss = choice.gloss,
		typing = choice.typing,
		bgmVolume = choice.bgmVolume,
		sfxVolume = choice.sfxVolume,
	}
end

local function sameChoice(left: Choice, right: Choice): boolean
	return left.uiLocale == right.uiLocale
		and left.gloss == right.gloss
		and left.typing == right.typing
		and left.bgmVolume == right.bgmVolume
		and left.sfxVolume == right.sfxVolume
end

local function cancelDebounce()
	if debounce ~= nil then
		task.cancel(debounce)
		debounce = nil
	end
end

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
	return {
		uiLocale = applied.uiLocale,
		gloss = applied.gloss,
		typing = applied.typing,
		bgmVolume = applied.bgmVolume,
		sfxVolume = applied.sfxVolume,
	}
end

function SettingsState.sessionTyping(): string
	return SettingsRules.sessionTyping(languageList, applied.typing, UserInputService.TouchEnabled)
end

function SettingsState.saveState(): string
	return saveState
end

function SettingsState.pending(): Choice?
	if pending == nil then
		return nil
	end
	return copyChoice(pending)
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

local function choiceFrom(uiLocale: string, gloss: string, typing: string, bgmVolume: number, sfxVolume: number): Choice
	return {
		uiLocale = uiLocale,
		gloss = gloss,
		typing = typing,
		bgmVolume = bgmVolume,
		sfxVolume = sfxVolume,
	}
end

function SettingsState.apply(uiLocale: string, gloss: string, typing: string, bgmVolume: number, sfxVolume: number)
	local remote = applyRemote
	local choice = choiceFrom(uiLocale, gloss, typing, bgmVolume, sfxVolume)
	pending = choice
	if sameChoice(choice, applied) and not awaiting then
		pending = nil
		return
	end
	if awaiting or remote == nil then
		return
	end
	sent = copyChoice(choice)
	awaiting = true
	saveState = "saving"
	fire()
	remote:FireServer(uiLocale, gloss, typing, bgmVolume, sfxVolume)
end

function SettingsState.queue(choice: Choice)
	pending = copyChoice(choice)
	cancelDebounce()
	if sameChoice(pending, applied) and not awaiting then
		pending = nil
		fire()
		return
	end
	debounce = task.delay(0.5, function()
		debounce = nil
		local held = pending
		if held ~= nil then
			SettingsState.apply(held.uiLocale, held.gloss, held.typing, held.bgmVolume, held.sfxVolume)
		end
	end)
end

function SettingsState.flush()
	cancelDebounce()
	local held = pending
	if held == nil then
		return
	end
	SettingsState.apply(held.uiLocale, held.gloss, held.typing, held.bgmVolume, held.sfxVolume)
end

function SettingsState.retry()
	if saveState ~= "failed" and saveState ~= "unavailable" then
		return
	end
	local held = if pending ~= nil then pending else applied
	local remote = applyRemote
	pending = copyChoice(held)
	if awaiting or remote == nil then
		return
	end
	sent = copyChoice(held)
	awaiting = true
	saveState = "saving"
	fire()
	remote:FireServer(held.uiLocale, held.gloss, held.typing, held.bgmVolume, held.sfxVolume)
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
		local incoming: Choice = {
			uiLocale = SettingsRules.shownUi(languageList, message.uiLocale),
			gloss = SettingsRules.shownGloss(languageList, message.gloss),
			typing = SettingsRules.shownTyping(languageList, message.typing),
			bgmVolume = SettingsRules.shownVolume(message.bgmVolume),
			sfxVolume = SettingsRules.shownVolume(message.sfxVolume),
		}
		local function preview()
			local heard = if pending ~= nil then pending else applied
			SoundManager.setVolumes(heard.bgmVolume, heard.sfxVolume)
		end
		if awaiting then
			if message.saveState == "saving" then
				if pending == nil or (sent ~= nil and sameChoice(pending, sent)) then
					applied = incoming
					publishLocale()
				end
				saveState = "saving"
				preview()
				fire()
				return
			end
			if message.saveState == "saved" then
				awaiting = false
				applied = incoming
				publishLocale()
				if pending ~= nil and not sameChoice(pending, applied) then
					saveState = "saving"
					preview()
					fire()
					local held = pending
					SettingsState.apply(held.uiLocale, held.gloss, held.typing, held.bgmVolume, held.sfxVolume)
					return
				end
				pending = nil
				sent = nil
				saveState = "saved"
				preview()
				reportDevice()
				fire()
				return
			end
			if message.saveState == "failed" or message.saveState == "unavailable" then
				awaiting = false
				sent = nil
				saveState = message.saveState
				preview()
				fire()
				return
			end
			return
		end
		if message.saveState == "loading" and saveState ~= "loading" then
			return
		end
		applied = incoming
		if pending ~= nil and sameChoice(pending, applied) then
			pending = nil
		end
		saveState = message.saveState
		if saveState ~= "loading" then
			publishLocale()
		end
		preview()
		reportDevice()
		fire()
	end)
	request:FireServer()
end

return SettingsState

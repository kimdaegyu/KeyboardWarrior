--!strict
-- Opens one session-locked profile per player. A failed open is remembered and never replaced with the default.

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RewardRules = require(ReplicatedStorage.Shared.RewardRules)
local SettingsRules = require(ReplicatedStorage.Shared.SettingsRules)
local TableData = require(ReplicatedStorage.Shared.TableData)
local TitleRules = require(ReplicatedStorage.Shared.TitleRules)
local TutorialRules = require(ReplicatedStorage.Shared.TutorialRules)
local PlayerStore = require(script.Parent.PlayerStore)

type Profile = RewardRules.Profile

local ProfileService = {}

local started = false
local sessions: {[number]: any} = {}
local gone: {[number]: boolean} = {}
local failed: {[number]: string} = {}
local readyHandlers: {(number) -> ()} = {}
local saveRunning: {[number]: boolean} = {}
local savePending: {[number]: boolean} = {}
local saveWaiters: {[number]: {thread}} = {}
local saveResult: {[number]: boolean} = {}

local function copyProfile(cache: any): Profile
	local grants: {string} = {}
	if type(cache.grants) == "table" then
		for _, id in cache.grants do
			if type(id) == "string" then
				table.insert(grants, id)
			end
		end
	end
	local profile: Profile = {
		schemaVersion = cache.schemaVersion,
		gold = cache.gold,
		exp = cache.exp,
		bestScore = cache.bestScore,
		bestScoreCpm = cache.bestScoreCpm,
		bestScoreLanguage = cache.bestScoreLanguage,
		grants = grants,
	}
	if type(cache.uiLocale) == "string" then
		profile.uiLocale = cache.uiLocale
	end
	if type(cache.gloss) == "string" then
		profile.gloss = cache.gloss
	end
	if type(cache.typing) == "string" then
		profile.typing = cache.typing
	end
	if type(cache.bgmVolume) == "number" then
		profile.bgmVolume = cache.bgmVolume
	end
	if type(cache.sfxVolume) == "number" then
		profile.sfxVolume = cache.sfxVolume
	end
	if type(cache.tutorialSeen) == "boolean" then
		profile.tutorialSeen = cache.tutorialSeen
	end
	if cache.ranked == true then
		profile.ranked = true
	end
	if type(cache.owned) == "table" then
		local owned: {string} = {}
		for _, id in cache.owned do
			if type(id) == "string" then
				table.insert(owned, id)
			end
		end
		profile.owned = owned
	end
	if type(cache.body) == "string" then
		profile.body = cache.body
	end
	if type(cache.rim) == "string" then
		profile.rim = cache.rim
	end
	if type(cache.effect) == "string" then
		profile.effect = cache.effect
	end
	TitleRules.copyInto(profile, cache)
	return profile
end

local function publishBalances(userId: number, profile: Profile)
	local player = Players:GetPlayerByUserId(userId)
	if player then
		player:SetAttribute("ProfileGold", profile.gold)
		player:SetAttribute("ProfileExp", profile.exp)
	end
end

local function normalize(document: any)
	local cache = document:GetCache()
	if type(cache.grants) == "table" then
		return
	end
	document:SetCache(copyProfile(cache))
end

local function open(player: Player)
	local userId = player.UserId
	local document = PlayerStore.getDocument(userId)
	local result = document:Open()
	if player.Parent == nil then
		gone[userId] = true
	end
	if result.success ~= true then
		failed[userId] = if type(result.reason) == "string" then result.reason else "open-failed"
		return
	end
	failed[userId] = nil
	sessions[userId] = document
	normalize(document)
	publishBalances(userId, document:GetCache())
	for _, handler in readyHandlers do
		handler(userId)
	end
	if gone[userId] and document:IsOpen() and not document:IsClosing() then
		sessions[userId] = nil
		document:Close()
	end
end

function ProfileService.setReadyHandler(handler: (number) -> ())
	table.insert(readyHandlers, handler)
end

function ProfileService.start()
	if started then
		return
	end
	started = true
	local function watch(player: Player)
		gone[player.UserId] = nil
		failed[player.UserId] = nil
		task.spawn(open, player)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

function ProfileService.isOpen(userId: number): boolean
	local document = sessions[userId]
	return document ~= nil and document:IsOpen()
end

function ProfileService.isGone(userId: number): boolean
	return gone[userId] == true
end

function ProfileService.failure(userId: number): string?
	return failed[userId]
end

function ProfileService.read(userId: number): Profile?
	local document = sessions[userId]
	if document == nil or not document:IsOpen() then
		return nil
	end
	return copyProfile(document:GetCache())
end

function ProfileService.replace(userId: number, profile: Profile): boolean
	local document = sessions[userId]
	if document == nil or not document:IsOpen() or document:IsClosing() then
		return false
	end
	document:SetCache(profile)
	publishBalances(userId, profile)
	return true
end

function ProfileService.commit(userId: number, settlementId: string, gold: number, exp: number, score: number, finished: boolean, cpm: number?, language: string?): (boolean, string, {number}?)
	local document = sessions[userId]
	if document == nil or not document:IsOpen() or document:IsClosing() then
		return false, "unavailable", nil
	end
	local loaded = TitleRules.catalog(TableData.rows("AchievementDataSheet") :: {TitleRules.Row})
	local updated, applied, unlocked = RewardRules.applyGrant(document:GetCache(), settlementId, gold, exp, score, finished, cpm, language, if loaded ~= nil then loaded else nil)
	if applied then
		document:SetCache(updated)
		publishBalances(userId, updated)
		return true, "pending", unlocked
	end
	return true, "already", unlocked
end

function ProfileService.applySettings(userId: number, uiLocale: any, gloss: any, typing: any, languages: any, bgmVolume: any, sfxVolume: any): (boolean, string)
	local document = sessions[userId]
	if document == nil or not document:IsOpen() or document:IsClosing() then
		return false, "unavailable"
	end
	if type(languages) ~= "table" then
		return false, "invalid"
	end
	local updated, reason = SettingsRules.apply(copyProfile(document:GetCache()), languages, uiLocale, gloss, typing, bgmVolume, sfxVolume)
	if updated == nil then
		return false, reason
	end
	document:SetCache(updated)
	return true, "pending"
end

function ProfileService.acknowledgeTutorial(userId: number): (boolean, string)
	local document = sessions[userId]
	if document == nil or not document:IsOpen() or document:IsClosing() then
		return false, "unavailable"
	end
	document:SetCache(TutorialRules.acknowledge(copyProfile(document:GetCache())))
	return true, "pending"
end

local function writeProfile(userId: number): boolean
	local document = sessions[userId]
	if document == nil or not document:IsOpen() or document:IsClosing() then
		return false
	end
	local result = document:Save()
	if result.success ~= true and document:IsOpen() and not document:IsClosing() then
		result = document:Save()
	end
	return result.success == true
end

function ProfileService.save(userId: number): boolean
	if saveRunning[userId] then
		savePending[userId] = true
		local waiting = saveWaiters[userId]
		if waiting == nil then
			waiting = {}
			saveWaiters[userId] = waiting
		end
		table.insert(waiting, coroutine.running())
		coroutine.yield()
		return saveResult[userId] == true
	end
	saveRunning[userId] = true
	local ok = false
	repeat
		savePending[userId] = false
		ok = writeProfile(userId)
		saveResult[userId] = ok
	until savePending[userId] ~= true
	saveRunning[userId] = false
	local waiting = saveWaiters[userId]
	saveWaiters[userId] = nil
	if waiting ~= nil then
		for _, thread in waiting do
			task.spawn(thread)
		end
	end
	return ok
end

function ProfileService.close(userId: number)
	gone[userId] = true
	local document = sessions[userId]
	sessions[userId] = nil
	if document ~= nil and document:IsOpen() and not document:IsClosing() then
		document:Close()
	end
end

return ProfileService

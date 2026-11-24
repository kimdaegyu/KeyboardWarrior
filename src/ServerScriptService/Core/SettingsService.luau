--!strict
-- Saves explicit UI locale and gloss choices. Reward fields stay on the same profile cache.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProfileService = require(script.Parent.ProfileService)
local SettingsRules = require(game:GetService("ReplicatedStorage").Shared.SettingsRules)
local TableData = require(game:GetService("ReplicatedStorage").Shared.TableData)

local SettingsService = {}

local started = false
local stateEvent: RemoteEvent? = nil
local languages: {SettingsRules.Language} = {}
local mobileByUser: {[number]: boolean} = {}

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

local function payload(userId: number, saveState: string)
	local profile = ProfileService.read(userId)
	return {
		uiLocale = if profile ~= nil then SettingsRules.shownUi(languages, profile.uiLocale) else "auto",
		gloss = if profile ~= nil then SettingsRules.shownGloss(languages, profile.gloss) else "off",
		typing = SettingsRules.shownTyping(languages, if profile ~= nil then profile.typing else nil),
		saveState = saveState,
	}
end

local function push(player: Player, saveState: string)
	if stateEvent == nil or player.Parent == nil then
		return
	end
	stateEvent:FireClient(player, payload(player.UserId, saveState))
end

function SettingsService.start()
	if started then
		return
	end
	started = true
	local catalog, reason = SettingsRules.catalog(TableData.rows("LanguageDataSheet") :: {SettingsRules.Row})
	assert(catalog ~= nil, reason)
	languages = catalog :: {SettingsRules.Language}
	stateEvent = remote("SettingsState")
	local request = remote("SettingsRequest")
	local apply = remote("SettingsApply")
	local device = remote("TypingDevice")
	Players.PlayerRemoving:Connect(function(player: Player)
		mobileByUser[player.UserId] = nil
	end)
	device.OnServerEvent:Connect(function(player: Player, mobile: any)
		if typeof(mobile) ~= "boolean" then
			return
		end
		mobileByUser[player.UserId] = mobile
	end)
	ProfileService.setReadyHandler(function(userId: number)
		local player = Players:GetPlayerByUserId(userId)
		if player ~= nil then
			push(player, "ready")
		end
	end)
	request.OnServerEvent:Connect(function(player: Player)
		if ProfileService.isOpen(player.UserId) then
			push(player, "ready")
		elseif ProfileService.failure(player.UserId) ~= nil then
			push(player, "unavailable")
		else
			push(player, "loading")
		end
	end)
	apply.OnServerEvent:Connect(function(player: Player, uiLocale: any, gloss: any, typing: any)
		if typeof(uiLocale) ~= "string" or typeof(gloss) ~= "string" or typeof(typing) ~= "string" then
			return
		end
		if not ProfileService.isOpen(player.UserId) then
			push(player, "unavailable")
			return
		end
		local ok, applyReason = ProfileService.applySettings(player.UserId, uiLocale, gloss, typing, languages)
		if not ok then
			push(player, if applyReason == "unavailable" then "unavailable" else "failed")
			return
		end
		push(player, "saving")
		task.spawn(function()
			local saved = ProfileService.save(player.UserId)
			if player.Parent ~= nil then
				push(player, if saved then "saved" else "failed")
			end
		end)
	end)
end

function SettingsService.languages(): {SettingsRules.Language}
	return languages
end

function SettingsService.isMobile(userId: number): boolean
	return mobileByUser[userId] ~= false
end

return SettingsService

--!strict
-- Equips an owned title. Unlocking stays on the match settlement.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TableData = require(ReplicatedStorage.Shared.TableData)
local TitleRules = require(ReplicatedStorage.Shared.TitleRules)

local ProfileService = require(script.Parent.ProfileService)
local ShopService = require(script.Parent.ShopService)

local TitleService = {}

local started = false
local catalog: {TitleRules.Achievement}? = nil
local stateEvent: RemoteEvent? = nil
local requestTimes: {[Player]: {number}} = {}

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

local function achievements(): {TitleRules.Achievement}
	local current = catalog
	if current ~= nil then
		return current
	end
	local loaded = TitleRules.catalog(TableData.rows("AchievementDataSheet") :: {TitleRules.Row})
	catalog = loaded or {}
	return catalog
end

local function known(id: number): boolean
	return TitleRules.find(achievements(), id) ~= nil
end

local function payload(profile: any, reason: string)
	local titles = if profile ~= nil and type(profile.titles) == "table" then profile.titles else {}
	return {
		reason = reason,
		mode = if profile ~= nil and profile.titleMode == "manual" then "manual" else "auto",
		equipped = if profile ~= nil and type(profile.equippedTitle) == "number" then profile.equippedTitle else 0,
		titles = titles,
	}
end

local function push(player: Player, reason: string)
	local event = stateEvent
	if event == nil or player.Parent == nil then
		return
	end
	event:FireClient(player, payload(ProfileService.read(player.UserId), reason))
end

function TitleService.sync(player: Player)
	local profile = ProfileService.read(player.UserId)
	if profile == nil then
		return
	end
	local cleaned = TitleRules.sanitize(profile, known)
	if cleaned ~= nil and ProfileService.replace(player.UserId, cleaned) then
		profile = cleaned
		task.spawn(ProfileService.save, player.UserId)
	end
	local equipped = if type(profile.equippedTitle) == "number" then profile.equippedTitle else 0
	if player:GetAttribute(TitleRules.EQUIPPED_ATTRIBUTE) ~= equipped then
		player:SetAttribute(TitleRules.EQUIPPED_ATTRIBUTE, equipped)
	end
	if #TitleRules.badgesFor(achievements(), profile.titles) > 0 then
		local BadgeService = game:GetService("BadgeService")
		for _, row in TitleRules.badgesFor(achievements(), profile.titles) do
			local badgeId = tonumber(row.badgeId)
			if badgeId ~= nil then
				task.spawn(function()
					pcall(function()
						BadgeService:AwardBadgeAsync(player.UserId, badgeId)
					end)
				end)
			end
		end
	end
	push(player, "ok")
end

local function choose(player: Player, titleId: number)
	local allowed, times = TitleRules.allowRequest(requestTimes[player] or {}, os.clock())
	requestTimes[player] = times
	if not allowed then
		push(player, "busy")
		return
	end
	local profile = ProfileService.read(player.UserId)
	if profile == nil then
		push(player, "unavailable")
		return
	end
	local updated, reason = TitleRules.choose(profile, titleId, known)
	if reason ~= "ok" then
		push(player, reason)
		return
	end
	if updated ~= profile and not ProfileService.replace(player.UserId, updated) then
		push(player, "unavailable")
		return
	end
	if updated ~= profile then
		task.spawn(ProfileService.save, player.UserId)
		ShopService.notify(player)
	end
	TitleService.sync(player)
end

function TitleService.start()
	if started then
		return
	end
	started = true
	achievements()
	stateEvent = remote("TitleState")
	local request = remote("TitleRequest")
	request.OnServerEvent:Connect(function(player: Player, action: any, titleId: any)
		if action == "sync" then
			TitleService.sync(player)
			return
		end
		if action == "auto" then
			choose(player, 0)
			return
		end
		if action ~= "equip" or type(titleId) ~= "number" then
			push(player, "invalid")
			return
		end
		choose(player, titleId)
	end)
	local function bind(player: Player)
		player.CharacterAdded:Connect(function()
			TitleService.sync(player)
		end)
		if player.Character ~= nil then
			TitleService.sync(player)
		end
	end
	Players.PlayerAdded:Connect(bind)
	for _, player in Players:GetPlayers() do
		bind(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		requestTimes[player] = nil
	end)
	ProfileService.setReadyHandler(function(userId: number)
		local player = Players:GetPlayerByUserId(userId)
		if player ~= nil then
			TitleService.sync(player)
		end
	end)
end

return TitleService

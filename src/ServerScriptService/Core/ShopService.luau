--!strict
-- Confirms gold purchases and one-slot equips. The client cannot grant either.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RewardRules = require(ReplicatedStorage.Shared.RewardRules)
local ShopRules = require(ReplicatedStorage.Shared.ShopRules)
local TableData = require(ReplicatedStorage.Shared.TableData)
local TitleRules = require(ReplicatedStorage.Shared.TitleRules)
local ProfileService = require(script.Parent.ProfileService)

local ShopService = {}

local started = false
local catalog: {ShopRules.Item}? = nil
local titleRows: {TitleRules.Achievement}? = nil
local levels: {RewardRules.LevelStep}? = nil
local stateEvent: RemoteEvent? = nil

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

local function items(): {ShopRules.Item}
	local current = catalog
	if current ~= nil then
		return current
	end
	local loaded, reason = ShopRules.catalog(TableData.rows("ShopDataSheet") :: {ShopRules.Row})
	assert(loaded ~= nil, reason)
	catalog = loaded
	return loaded
end

local function remember(userId: number, updated: ShopRules.Profile)
	if not ProfileService.replace(userId, updated :: any) then
		return false
	end
	task.spawn(function()
		ProfileService.save(userId)
	end)
	return true
end

function ShopService.paintFor(userId: number): ShopRules.Paint
	local list = items()
	return ShopRules.paint(list, ProfileService.read(userId) :: any)
end

local function achievements(): {TitleRules.Achievement}
	local current = titleRows
	if current ~= nil then
		return current
	end
	local loaded = TitleRules.catalog(TableData.rows("AchievementDataSheet") :: {TitleRules.Row})
	titleRows = loaded or {}
	return titleRows
end

local function payload(userId: number, reason: string)
	local list = items()
	local profile = ProfileService.read(userId)
	local inStudio = RunService:IsStudio()
	local worn = ShopRules.loadout(list, profile :: any)
	local owned: {string} = {}
	local scoreFor: {[string]: number} = {}
	for _, achievement in achievements() do
		scoreFor[achievement.shopId] = achievement.score
	end
	local rows = {}
	for _, item in list do
		if ShopRules.listed(item, inStudio) then
			local has = ShopRules.owns(profile :: any, item)
			if has and item.release ~= "Default" then
				table.insert(owned, item.id)
			end
			table.insert(rows, {
				id = item.id,
				category = item.category,
				price = item.price,
				release = item.release,
				color = item.color,
				preset = item.preset,
				currency = item.currency,
				score = scoreFor[item.id],
				owned = has,
			})
		end
	end
	local steps = levels or RewardRules.levelsFromRows(TableData.rows("LevelDataSheet"))
	levels = steps
	return {
		level = if profile and steps and #steps > 0 then RewardRules.progress(profile.exp, steps) else nil,
		status = if profile == nil then "unavailable" else "ready",
		reason = reason,
		gold = if profile ~= nil then profile.gold else 0,
		owned = owned,
		body = worn.body,
		rim = worn.rim,
		effect = worn.effect,
		items = rows,
	}
end

local function push(player: Player, reason: string)
	local event = stateEvent
	if event == nil or player.Parent == nil then
		return
	end
	event:FireClient(player, payload(player.UserId, reason))
end

local function mutate(player: Player, action: string, itemId: string)
	local profile = ProfileService.read(player.UserId)
	if profile == nil then
		push(player, "unavailable")
		return
	end
	local item = ShopRules.find(items(), itemId)
	local updated, reason
	if action == "buy" then
		updated, reason = ShopRules.purchase(profile :: any, item, RunService:IsStudio())
	elseif action == "equip" then
		updated, reason = ShopRules.equip(profile :: any, item)
	else
		push(player, "invalid")
		return
	end
	if (reason == "bought" or reason == "equipped") and updated ~= profile then
		if not remember(player.UserId, updated) then
			push(player, "unavailable")
			return
		end
	end
	push(player, reason)
end

function ShopService.notify(player: Player)
	push(player, "ok")
end

function ShopService.start()
	if started then
		return
	end
	started = true
	items()
	stateEvent = remote("ShopState")
	local request = remote("ShopRequest")
	request.OnServerEvent:Connect(function(player: Player, action: any, itemId: any)
		if action == "sync" then
			push(player, "ok")
			return
		end
		if type(action) ~= "string" or type(itemId) ~= "string" then
			push(player, "invalid")
			return
		end
		mutate(player, action, itemId)
	end)
end

return ShopService

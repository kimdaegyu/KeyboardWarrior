--!strict
-- Studio-only profile cheats. A published server never creates the request.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ProfileService = require(script.Parent.ProfileService)
local RankService = require(script.Parent.RankService)
local SettingsService = require(script.Parent.SettingsService)
local ShopService = require(script.Parent.ShopService)
local TitleService = require(script.Parent.TitleService)
local TutorialService = require(script.Parent.TutorialService)

local CheatService = {}

local GOLD_LIMIT = 1000000000

local function reply(player: Player, event: RemoteEvent, code: string)
	if player.Parent ~= nil then
		event:FireClient(player, { code = code })
	end
end

local function parseGold(value: any): number?
	if type(value) ~= "string" or string.match(value, "^%d+$") == nil then
		return nil
	end
	local amount = tonumber(value)
	if amount == nil or amount < 0 or amount > GOLD_LIMIT or amount % 1 ~= 0 then
		return nil
	end
	return amount
end

local function refresh(player: Player)
	TitleService.sync(player)
	ShopService.notify(player)
	SettingsService.refresh(player)
	TutorialService.refresh(player)
	RankService.refresh(player)
end

function CheatService.start()
	if not RunService:IsStudio() then
		return
	end
	local event = Instance.new("RemoteEvent")
	event.Name = "CheatRequest"
	event.Parent = ReplicatedStorage
	event.OnServerEvent:Connect(function(player: Player, action: any, parameter1: any)
		if not RunService:IsStudio() or player ~= Players:GetPlayerByUserId(player.UserId) then
			return
		end
		local profile = ProfileService.read(player.UserId)
		if profile == nil then
			reply(player, event, "unavailable")
			return
		end
		if action == "reset" then
			local replaced = ProfileService.replace(player.UserId, {
				schemaVersion = 1,
				gold = 0,
				exp = 0,
				bestScore = 0,
			})
			if not replaced then
				reply(player, event, "failed")
				return
			end
			local saved = ProfileService.save(player.UserId)
			RankService.forget(player.UserId)
			refresh(player)
			reply(player, event, if saved then "done" else "failed")
			return
		end
		if action == "gold" then
			local amount = parseGold(parameter1)
			if amount == nil then
				reply(player, event, "invalid")
				return
			end
			profile.gold = amount
			if not ProfileService.replace(player.UserId, profile) then
				reply(player, event, "failed")
				return
			end
			local saved = ProfileService.save(player.UserId)
			refresh(player)
			reply(player, event, if saved then "done" else "failed")
			return
		end
		reply(player, event, "invalid")
	end)
end

return CheatService

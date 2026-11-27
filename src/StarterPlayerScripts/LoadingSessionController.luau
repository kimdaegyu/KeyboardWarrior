--!strict
-- One loading cover per visit to this lobby server.
-- Respawn, practice, and match start do not open it again.
-- Waiting here does not delay any other player's match.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local constants = require(Shared:WaitForChild("IngameConstants"))
local ItemIconUtil = require(Shared:WaitForChild("ItemIconUtil"))
local LoadingArt = require(Shared:WaitForChild("LoadingArt"))
local LoadingPolicy = require(Shared:WaitForChild("LoadingPolicy"))
local UIImageAssetIds = require(Shared:WaitForChild("UIImageAssetIds"))
local AssetPreload = require(script.Parent.AssetPreload)
local LoadingPresenter = require(script.Parent.LoadingPresenter)
local TutorialState = require(script.Parent.TutorialState)

local FIRST_SCREEN_ITEMS = { 10063, 10073 }

local LoadingSessionController = {}

local generation = 0
local began = false
local startAttempt: () -> ()

local function hudReady(): boolean
	local gui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	return gui ~= nil and gui:GetAttribute("LobbyHudReady") == true
end

local function preloadList(): ( { string }, string, string )
	local background = LoadingArt.backgroundUrl()
	local title = LoadingArt.titleUrl()
	local allowed = { background, title }
	local uiId = UIImageAssetIds.KeyboardWarriorUI
	if type(uiId) == "number" and uiId > 0 then
		table.insert(allowed, `rbxassetid://{uiId}`)
	end
	for _, itemId in FIRST_SCREEN_ITEMS do
		local info = ItemIconUtil.get(itemId)
		if info ~= nil and info.Image ~= "" then
			table.insert(allowed, info.Image)
		end
	end
	return LoadingPolicy.collectPreload(allowed, {}), background, title
end

local function waitProfile(token: number, serial: number?): "ready" | "failed" | "timeout" | "cancelled"
	local deadline = os.clock() + constants.Loading.PlayerDataTimeoutSeconds
	local function classify(): "ready" | "failed" | "pending"
		if serial ~= nil and TutorialState.serial() ~= serial then
			return "pending"
		end
		return LoadingPolicy.profileOutcome(TutorialState.known(), TutorialState.saveState())
	end
	if serial == nil then
		local immediate = classify()
		if immediate ~= "pending" then
			return immediate
		end
	end
	while LoadingPolicy.isCurrent(generation, token) and os.clock() < deadline do
		local outcome = classify()
		if outcome ~= "pending" then
			return outcome
		end
		task.wait(0.05)
	end
	if not LoadingPolicy.isCurrent(generation, token) then
		return "cancelled"
	end
	local final = classify()
	if final ~= "pending" then
		return final
	end
	return "timeout"
end

local function waitHud(token: number): "ready" | "timeout" | "cancelled"
	local deadline = os.clock() + constants.Loading.LobbyHudTimeoutSeconds
	while LoadingPolicy.isCurrent(generation, token) and os.clock() < deadline do
		if hudReady() then
			return "ready"
		end
		task.wait(0.05)
	end
	if not LoadingPolicy.isCurrent(generation, token) then
		return "cancelled"
	end
	if hudReady() then
		return "ready"
	end
	return "timeout"
end

local function showFailure(token: number, code: string, messageName: string)
	if not LoadingPolicy.isCurrent(generation, token) then
		return
	end
	LoadingPresenter.fail(code, messageName, function()
		if LoadingPolicy.isCurrent(generation, token) then
			startAttempt()
		end
	end)
end

local function run(token: number)
	local urls, backgroundUrl, titleUrl = preloadList()
	local artReport: AssetPreload.Report? = nil
	local artStarted = os.clock()
	task.spawn(function()
		local ok, result = pcall(function()
			return AssetPreload.load(urls, function()
				return LoadingPolicy.isCurrent(generation, token)
			end, constants.Loading.DecorativeTimeoutSeconds, 1)
		end)
		if LoadingPolicy.isCurrent(generation, token) then
			artReport = if ok and typeof(result) == "table" then result else { Statuses = {} } :: any
		end
	end)

	TutorialState.start()
	local serial: number? = nil
	if token > 1 then
		serial = token
		local remote = ReplicatedStorage:WaitForChild("ProfileRetry", 5)
		if remote ~= nil and remote:IsA("RemoteEvent") then
			remote:FireServer(serial)
		end
	end
	local profile = waitProfile(token, serial)
	if not LoadingPolicy.isCurrent(generation, token) then
		return
	end
	if profile ~= "ready" then
		local code = "LD-TIMEOUT"
		if profile == "failed" then
			local reason = TutorialState.failureReason()
			code = if type(reason) == "string" and reason ~= "" then reason else "LD-DATA"
		end
		showFailure(token, code, "DataFailed")
		return
	end

	LoadingPresenter.setPhase(LoadingPolicy.Phase.Lobby)
	local hud = waitHud(token)
	if not LoadingPolicy.isCurrent(generation, token) then
		return
	end
	if hud ~= "ready" then
		showFailure(token, "LD-HUD", "HudFailed")
		return
	end

	local limit = constants.Loading.DecorativeTimeoutSeconds
	while LoadingPolicy.isCurrent(generation, token) and artReport == nil do
		local decision = LoadingPolicy.decorativeWait(false, os.clock() - artStarted, limit)
		if decision == "fallback" then
			break
		end
		task.wait(0.05)
	end
	if not LoadingPolicy.isCurrent(generation, token) then
		return
	end
	local statuses: { [string]: string } = {}
	if artReport ~= nil and typeof(artReport.Statuses) == "table" then
		statuses = artReport.Statuses
	end
	LoadingPresenter.applyArt(backgroundUrl, titleUrl, statuses)
	if not LoadingPolicy.isCurrent(generation, token) then
		return
	end
	LoadingPresenter.fadeOut()
end

startAttempt = function()
	generation += 1
	local token = generation
	LoadingPresenter.show(LoadingPolicy.Phase.PlayerData)
	task.spawn(function()
		run(token)
	end)
end

function LoadingSessionController.begin()
	if began then
		return
	end
	began = true
	startAttempt()
end

return LoadingSessionController

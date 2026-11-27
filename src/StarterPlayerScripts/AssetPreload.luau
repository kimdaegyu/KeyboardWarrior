--!strict
-- Requests image content ids once, and preloads only the ones that are not ready.
-- Passing the image string alone makes Studio report Failure immediately.
-- A temporary ImageLabel is the instance PreloadAsync receives. pcall success is not completion.
-- The temporary image is destroyed after the check. Success means this place received it.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LoadingPolicy = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LoadingPolicy"))

export type Report = {
	Ok: boolean,
	Reason: string,
	Requested: number,
	AlreadySuccess: number,
	PreloadRequested: number,
	Succeeded: number,
	Failed: number,
	FailedIds: { string },
	Attempts: number,
	Elapsed: number,
	Statuses: { [string]: string },
}

local AssetPreload = {}

local loadedThisPlace: { [string]: boolean } = {}
local outcome: { [string]: string } = {}
local active: { [string]: boolean } = {}

local function fetchStatus(url: string): string
	local ok, status = pcall(function()
		return ContentProvider:GetAssetFetchStatus(url)
	end)
	if not ok or typeof(status) ~= "EnumItem" then
		return "None"
	end
	return status.Name
end

local function assetIdOf(value: string): string?
	return string.match(value, "(%d+)")
end

local function knownReady(url: string): boolean
	return loadedThisPlace[url] == true or not LoadingPolicy.assetNeedsFetch(fetchStatus(url))
end

local function createHolder(): Instance
	local player = Players.LocalPlayer
	local playerGui = if player ~= nil then player:FindFirstChildOfClass("PlayerGui") else nil
	if playerGui ~= nil then
		local screen = Instance.new("ScreenGui")
		screen.Name = "AssetPreload"
		screen.ResetOnSpawn = false
		screen.Enabled = true
		screen.DisplayOrder = -100
		screen.Parent = playerGui
		return screen
	end
	local folder = Instance.new("Folder")
	folder.Name = "AssetPreload"
	folder.Parent = ReplicatedStorage
	return folder
end

local function publish(url: string, status: string, statuses: { [string]: string })
	statuses[url] = status
	outcome[url] = status
	if status == "Success" then
		loadedThisPlace[url] = true
	end
	active[url] = nil
end

local function preloadImages(urls: { string }, isCurrent: () -> boolean, timeoutSeconds: number, statuses: { [string]: string })
	local holder = createHolder()
	local labels: { [string]: ImageLabel } = {}
	local callbackStatus: { [string]: string } = {}
	local byId: { [string]: string } = {}
	for _, url in urls do
		local id = assetIdOf(url)
		if id ~= nil then
			byId[id] = url
		end
		local label = Instance.new("ImageLabel")
		label.Name = "Image"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromOffset(1, 1)
		label.Position = UDim2.fromOffset(-100, -100)
		label.Image = url
		label.Parent = holder
		labels[url] = label
	end

	local returned = false
	task.spawn(function()
		pcall(function()
			local instances: { Instance } = {}
			for _, url in urls do
				table.insert(instances, labels[url])
			end
			ContentProvider:PreloadAsync(instances, function(contentId: string, status: Enum.AssetFetchStatus)
				local id = assetIdOf(contentId)
				local url = if id ~= nil then byId[id] else nil
				if url == nil or callbackStatus[url] == "Success" then
					return
				end
				callbackStatus[url] = status.Name
			end)
		end)
		returned = true
	end)

	local deadline = os.clock() + timeoutSeconds
	while isCurrent() and os.clock() < deadline do
		local pending = false
		for _, url in urls do
			local label = labels[url]
			local callback = callbackStatus[url] or ""
			local ready = label.IsLoaded or callback == "Success" or not LoadingPolicy.assetNeedsFetch(fetchStatus(url))
			if ready then
				publish(url, "Success", statuses)
			else
				pending = true
			end
		end
		local rejected = returned
		if rejected then
			for _, url in urls do
				if statuses[url] ~= "Success" and callbackStatus[url] ~= "Failure" then
					rejected = false
					break
				end
			end
		end
		if not pending or rejected then
			break
		end
		task.wait(0.05)
	end

	for _, url in urls do
		if statuses[url] ~= "Success" then
			local label = labels[url]
			local status = LoadingPolicy.imageLoadStatus(fetchStatus(url), callbackStatus[url] or "", label.IsLoaded)
			publish(url, status, statuses)
		end
	end
	holder:Destroy()
end

function AssetPreload.load(urls: { string }, isCurrent: () -> boolean, timeoutSeconds: number, maxAttempts: number): Report
	local started = os.clock()
	local unique = LoadingPolicy.dedupeAssetUrls(urls)
	local statuses: { [string]: string } = {}
	local alreadySuccess = 0
	local preloadRequested = 0
	local attempts = 0
	local countedPreload = false

	local function report(ok: boolean, reason: string): Report
		local succeeded = 0
		local failed = 0
		local failedIds: { string } = {}
		for _, url in unique do
			if statuses[url] == "Success" then
				succeeded += 1
			else
				failed += 1
				table.insert(failedIds, url)
			end
		end
		return {
			Ok = ok and failed == 0,
			Reason = if ok and failed == 0 then "" else reason,
			Requested = #unique,
			AlreadySuccess = alreadySuccess,
			PreloadRequested = preloadRequested,
			Succeeded = succeeded,
			Failed = failed,
			FailedIds = failedIds,
			Attempts = attempts,
			Elapsed = os.clock() - started,
			Statuses = statuses,
		}
	end

	if not isCurrent() then
		return report(false, "cancelled")
	end

	for _, url in unique do
		if knownReady(url) then
			statuses[url] = "Success"
			alreadySuccess += 1
		else
			statuses[url] = fetchStatus(url)
		end
	end

	for attempt = 1, math.max(1, maxAttempts) do
		if not isCurrent() then
			return report(false, "cancelled")
		end
		local todo: { string } = {}
		for _, url in unique do
			if statuses[url] == "Success" or knownReady(url) then
				statuses[url] = "Success"
			else
				table.insert(todo, url)
			end
		end
		if #todo == 0 then
			break
		end
		attempts = attempt
		if not countedPreload then
			preloadRequested = #todo
			countedPreload = true
		end

		local mine: { string } = {}
		local waiting: { string } = {}
		for _, url in todo do
			if active[url] then
				table.insert(waiting, url)
			else
				active[url] = true
				table.insert(mine, url)
			end
		end

		if #mine > 0 then
			preloadImages(mine, isCurrent, timeoutSeconds, statuses)
		end

		local deadline = os.clock() + timeoutSeconds
		while isCurrent() and os.clock() < deadline do
			local stillWaiting = false
			for _, url in waiting do
				if knownReady(url) or outcome[url] == "Success" then
					statuses[url] = "Success"
				elseif active[url] then
					stillWaiting = true
				elseif outcome[url] ~= nil then
					statuses[url] = outcome[url]
				else
					stillWaiting = true
				end
			end
			if not stillWaiting then
				break
			end
			task.wait(0.05)
		end
	end

	if not isCurrent() then
		return report(false, "cancelled")
	end

	for _, url in unique do
		if statuses[url] ~= "Success" and knownReady(url) then
			statuses[url] = "Success"
		end
	end

	local final = report(true, "")
	if final.Failed > 0 then
		final.Ok = false
		final.Reason = "LD-CONTENT"
	end
	return final
end

return AssetPreload

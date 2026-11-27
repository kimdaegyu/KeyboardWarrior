--!strict
-- Decisions for the first-join loading screen. This module does not call Roblox services.

local LoadingPolicy = {}

LoadingPolicy.Phase = {
	PlayerData = "PlayerData",
	Lobby = "Lobby",
	Failed = "Failed",
}

LoadingPolicy.FallbackText = {
	PlayerData = "플레이어 데이터 불러오는 중",
	Lobby = "로비 준비 중",
	Failed = "불러오기를 마치지 못했습니다",
	DataFailed = "플레이어 데이터를 불러오지 못했습니다",
	HudFailed = "로비 화면을 준비하지 못했습니다",
	Retry = "다시 시도",
	ErrorCode = "오류 {code}",
	Title = "Typing GOD",
}

local MESSAGE_KEY = {
	PlayerData = "Loading.PlayerData",
	Lobby = "Loading.Lobby",
	Failed = "Loading.Failed",
	DataFailed = "Loading.DataFailed",
	HudFailed = "Loading.HudFailed",
	Retry = "Loading.Retry",
	ErrorCode = "Loading.ErrorCode",
	Title = "Loading.Title",
}

function LoadingPolicy.messageKey(name: string): string
	return MESSAGE_KEY[name] or "Loading.Failed"
end

-- A successful open is ready for a new player's default profile and for saved data.
-- unavailable is a read failure. It is not a new player and must not be saved as the default.
function LoadingPolicy.profileOutcome(known: boolean, saveState: string): "ready" | "failed" | "pending"
	if known and (saveState == "ready" or saveState == "saved") then
		return "ready"
	end
	if saveState == "unavailable" then
		return "failed"
	end
	return "pending"
end

-- hold: the loading cover is up, so the tutorial must not open or be completed.
-- tutorial: first join, profile confirmed, not yet seen.
-- lobby: already seen, or the profile is not a confirmed unseen tutorial.
function LoadingPolicy.tutorialAction(cover: boolean, known: boolean, seen: boolean, saveState: string): "hold" | "tutorial" | "lobby"
	if cover then
		return "hold"
	end
	if known and not seen and saveState == "ready" then
		return "tutorial"
	end
	return "lobby"
end

function LoadingPolicy.isCurrent(generation: number, token: number): boolean
	return generation == token
end

function LoadingPolicy.imageUrl(id: string): string
	if id == "" then
		return ""
	end
	if string.find(id, "://", 1, true) ~= nil then
		return id
	end
	if string.match(id, "^[1-9]%d*$") ~= nil then
		return "rbxassetid://" .. id
	end
	return ""
end

-- A visible loaded image stays. An empty id, a failed fetch, or a timed-out fetch uses the fallback.
function LoadingPolicy.artMode(url: string, status: string?, imageLoaded: boolean?): "image" | "fallback"
	if url ~= "" and (status == "Success" or imageLoaded == true) then
		return "image"
	end
	return "fallback"
end

function LoadingPolicy.decorativeWait(finished: boolean, elapsed: number, timeoutSeconds: number): "done" | "fallback" | "wait"
	if finished then
		return "done"
	end
	if elapsed >= timeoutSeconds then
		return "fallback"
	end
	return "wait"
end

function LoadingPolicy.dedupeAssetUrls(urls: { string }): { string }
	local order: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, url in urls do
		if url ~= "" and not seen[url] then
			seen[url] = true
			table.insert(order, url)
		end
	end
	return order
end

-- Only the urls the caller lists are requested. Denied urls are the shop, rank portraits, and sounds.
function LoadingPolicy.collectPreload(allowed: { string }, denied: { string }): { string }
	local block: { [string]: boolean } = {}
	for _, url in denied do
		block[url] = true
	end
	local urls: { string } = {}
	for _, url in allowed do
		if not block[url] then
			table.insert(urls, url)
		end
	end
	return LoadingPolicy.dedupeAssetUrls(urls)
end

function LoadingPolicy.assetNeedsFetch(statusName: string): boolean
	return statusName ~= "Success"
end

-- An image string can stay Failure in GetAssetFetchStatus until a real image instance is requested.
function LoadingPolicy.imageLoadStatus(fetchStatus: string, callbackStatus: string, imageLoaded: boolean): string
	if imageLoaded or callbackStatus == "Success" or fetchStatus == "Success" then
		return "Success"
	end
	if callbackStatus == "Failure" then
		return "Failure"
	end
	if callbackStatus ~= "" then
		return callbackStatus
	end
	if fetchStatus == "Failure" or fetchStatus == "" then
		return "None"
	end
	return fetchStatus
end

return LoadingPolicy

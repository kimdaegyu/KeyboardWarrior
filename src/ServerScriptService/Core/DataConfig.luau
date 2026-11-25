--!strict
local function isCount(value: any): boolean
	return type(value) == "number" and value >= 0 and value < math.huge and value % 1 == 0
end

local function isGrantList(value: any): boolean
	if value == nil then
		return true
	end
	if type(value) ~= "table" then
		return false
	end
	local count = 0
	for index, entry in ipairs(value) do
		if type(entry) ~= "string" or entry == "" then
			return false
		end
		count = index
	end
	if count > 64 then
		return false
	end
	local size = 0
	for _ in value do
		size += 1
	end
	return size == count
end

local function isLanguageCode(value: any): boolean
	if type(value) ~= "string" then
		return false
	end
	local length = string.len(value)
	return length >= 2 and length <= 8 and string.match(value, "^[a-z][a-z0-9]+$") ~= nil
end

local function isUiLocale(value: any): boolean
	return value == nil or value == "auto" or isLanguageCode(value)
end

local function isGloss(value: any): boolean
	return value == nil or value == "off" or isLanguageCode(value)
end

local function isTyping(value: any): boolean
	return value == nil or isLanguageCode(value)
end

local function isVolume(value: any): boolean
	return value == nil or (type(value) == "number" and value == math.floor(value) and value >= 0 and value <= 100 and value % 5 == 0)
end

local function isSeen(value: any): boolean
	return value == nil or type(value) == "boolean"
end

local function isShopId(value: any): boolean
	if type(value) ~= "string" then
		return false
	end
	local length = string.len(value)
	return length >= 2 and length <= 32 and string.match(value, "^[a-z][a-z0-9_]+$") ~= nil
end

local function isSlot(value: any): boolean
	return value == nil or isShopId(value)
end

local function isOwnedList(value: any): boolean
	if value == nil then
		return true
	end
	if type(value) ~= "table" then
		return false
	end
	local count = 0
	for index, entry in ipairs(value) do
		if not isShopId(entry) then
			return false
		end
		count = index
	end
	if count > 64 then
		return false
	end
	local size = 0
	for _ in value do
		size += 1
	end
	return size == count
end

local function check(value: any)
	if type(value) ~= "table" or value.schemaVersion ~= 1 then
		return false, value
	end
	local recordLanguage = value.bestScoreLanguage
	local validRecordLanguage = recordLanguage == nil or (type(recordLanguage) == "string" and isLanguageCode(string.lower(recordLanguage)))
	local economy = validRecordLanguage and isCount(value.gold) and isCount(value.exp) and (value.bestScoreCpm == nil or isCount(value.bestScoreCpm)) and isCount(value.bestScore) and isGrantList(value.grants)
	local settings = isUiLocale(value.uiLocale) and isGloss(value.gloss) and isTyping(value.typing) and isSeen(value.tutorialSeen) and isSeen(value.ranked) and isVolume(value.bgmVolume) and isVolume(value.sfxVolume)
	local shop = isOwnedList(value.owned) and isSlot(value.body) and isSlot(value.rim) and isSlot(value.effect)
	return economy and settings and shop, value
end

return {
	storeName = "KeyboardWarrior_Player_v1",
	rankStoreName = "KeyboardWarrior_Rank_v1",
	studioScope = "studio",
	liveScope = "live",
	keyPrefix = "KW_Player_",
	default = { schemaVersion = 1, gold = 0, exp = 0, bestScore = 0 },
	check = check,
	migrations = {},
}

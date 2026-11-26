--!strict
-- One finished match score unlocks every title at or below that score, once per account.

export type Row = {
	Id: string,
	TitleKey: string,
	Score: string,
	ShopId: string,
	RobloxBadgeId: string,
	itemId: string,
}

export type Achievement = {
	id: number,
	titleKey: string,
	score: number,
	shopId: string,
	badgeId: string,
	itemId: number,
}

local TitleRules = {}

TitleRules.EQUIPPED_ATTRIBUTE = "EquippedTitleId"
TitleRules.RATE_WINDOW_SECONDS = 2
TitleRules.RATE_MAX_REQUESTS = 6

local function copyNumbers(source: {number}?): {number}
	local copy: {number} = {}
	if type(source) ~= "table" then
		return copy
	end
	for _, id in source do
		if type(id) == "number" then
			table.insert(copy, id)
		end
	end
	return copy
end

local function copyStrings(source: {string}?): {string}
	local copy: {string} = {}
	if type(source) ~= "table" then
		return copy
	end
	for _, id in source do
		if type(id) == "string" then
			table.insert(copy, id)
		end
	end
	return copy
end

local function hasNumber(list: {number}, id: number): boolean
	return table.find(list, id) ~= nil
end

local function highest(list: {number}): number
	local best = 0
	for _, id in list do
		if id > best then
			best = id
		end
	end
	return best
end

function TitleRules.copyInto(target: any, source: any)
	if type(source) ~= "table" then
		return
	end
	if type(source.titles) == "table" then
		target.titles = copyNumbers(source.titles)
	end
	if source.titleMode == "auto" or source.titleMode == "manual" then
		target.titleMode = source.titleMode
	end
	if type(source.equippedTitle) == "number" then
		target.equippedTitle = source.equippedTitle
	end
	if type(source.titleGrantId) == "string" then
		target.titleGrantId = source.titleGrantId
	end
	if type(source.titleGrantIds) == "table" then
		target.titleGrantIds = copyNumbers(source.titleGrantIds)
	end
end

function TitleRules.catalog(rows: {Row}): ({Achievement}?, string)
	local seen: {[number]: boolean} = {}
	local seenItems: {[number]: boolean} = {}
	local shops: {[string]: boolean} = {}
	local items: {Achievement} = {}
	for _, row in rows do
		local id = tonumber(row.Id)
		if id == nil or id < 1 or id % 1 ~= 0 or seen[id] then
			return nil, "id"
		end
		seen[id] = true
		if type(row.TitleKey) ~= "string" or string.match(row.TitleKey, "^[%w_.]+$") == nil then
			return nil, "key"
		end
		local score = tonumber(row.Score)
		if score == nil or score < 1 or score % 1 ~= 0 or score >= math.huge then
			return nil, "score"
		end
		local shopId = row.ShopId
		if type(shopId) ~= "string" or string.match(shopId, "^[a-z][a-z0-9_]+$") == nil or shops[shopId] then
			return nil, "shop"
		end
		shops[shopId] = true
		local badge = row.RobloxBadgeId or ""
		if badge ~= "" and string.match(badge, "^%d+$") == nil then
			return nil, "badge"
		end
		local itemId = tonumber(row.itemId)
		if itemId == nil or itemId < 1 or itemId % 1 ~= 0 or seenItems[itemId] then
			return nil, "item"
		end
		seenItems[itemId] = true
		table.insert(items, {
			id = id,
			titleKey = row.TitleKey,
			score = score,
			shopId = shopId,
			badgeId = badge,
			itemId = itemId,
		})
	end
	table.sort(items, function(left, right)
		return left.id < right.id
	end)
	return items, "ok"
end

function TitleRules.find(items: {Achievement}, id: number): Achievement?
	for _, row in items do
		if row.id == id then
			return row
		end
	end
	return nil
end

-- Finished scores only. Practice and leaving pass finished=false and unlock nothing.
function TitleRules.applyScore(profile: any, score: number, finished: boolean, catalog: {Achievement}): {number}
	local titles = copyNumbers(profile.titles)
	local owned = copyStrings(profile.owned)
	local hadOwned = type(profile.owned) == "table"
	local mode = if profile.titleMode == "manual" then "manual" else "auto"
	local equipped = if type(profile.equippedTitle) == "number" then math.floor(profile.equippedTitle) else 0
	local fresh: {number} = {}
	if finished and type(score) == "number" and score >= 0 and score < math.huge then
		for _, row in catalog do
			if score >= row.score and not hasNumber(titles, row.id) then
				table.insert(titles, row.id)
				table.insert(fresh, row.id)
				if table.find(owned, row.shopId) == nil then
					table.insert(owned, row.shopId)
				end
			end
		end
	end
	table.sort(titles)
	table.sort(fresh)
	if #titles > 0 or type(profile.titles) == "table" then
		profile.titles = titles
	end
	if #fresh > 0 or hadOwned then
		profile.owned = owned
	end
	if mode == "auto" and #fresh > 0 then
		equipped = highest(titles)
		profile.equippedTitle = equipped
		profile.titleMode = "auto"
	elseif profile.titleMode == "manual" or type(profile.equippedTitle) == "number" then
		profile.equippedTitle = equipped
		profile.titleMode = mode
	end
	return fresh
end

function TitleRules.rememberGrant(profile: any, settlementId: string, fresh: {number})
	profile.titleGrantId = settlementId
	profile.titleGrantIds = table.clone(fresh)
end

function TitleRules.storedGrant(profile: any, settlementId: string): {number}?
	if profile.titleGrantId ~= settlementId or type(profile.titleGrantIds) ~= "table" then
		return nil
	end
	return copyNumbers(profile.titleGrantIds)
end

local function cloneProfile(profile: any): any
	local copy = {}
	for key, value in profile do
		if key == "grants" or key == "owned" or key == "titles" or key == "titleGrantIds" then
			if type(value) == "table" then
				local listed = {}
				for _, entry in value do
					table.insert(listed, entry)
				end
				copy[key] = listed
			end
		else
			copy[key] = value
		end
	end
	return copy
end

function TitleRules.choose(profile: any, titleId: number, catalogHas: (number) -> boolean): (any, string)
	if type(titleId) ~= "number" or titleId ~= math.floor(titleId) or titleId < 0 then
		return profile, "invalid"
	end
	local updated = cloneProfile(profile)
	local titles = copyNumbers(updated.titles)
	updated.titles = titles
	if titleId == 0 then
		updated.titleMode = "auto"
		updated.equippedTitle = highest(titles)
		return updated, "ok"
	end
	if not catalogHas(titleId) then
		return profile, "missing"
	end
	if not hasNumber(titles, titleId) then
		return profile, "unowned"
	end
	updated.titleMode = "manual"
	updated.equippedTitle = titleId
	return updated, "ok"
end

function TitleRules.sanitize(profile: any, catalogHas: (number) -> boolean): any?
	local titles = copyNumbers(profile.titles)
	local kept: {number} = {}
	local changed = false
	for _, id in titles do
		if id == math.floor(id) and id >= 1 and catalogHas(id) and not hasNumber(kept, id) then
			table.insert(kept, id)
		else
			changed = true
		end
	end
	table.sort(kept)
	local mode = if profile.titleMode == "manual" then "manual" else "auto"
	if profile.titleMode ~= nil and profile.titleMode ~= "auto" and profile.titleMode ~= "manual" then
		changed = true
	end
	local equipped = if type(profile.equippedTitle) == "number" then math.floor(profile.equippedTitle) else 0
	if mode == "manual" and (equipped < 1 or not hasNumber(kept, equipped) or not catalogHas(equipped)) then
		mode = "auto"
		equipped = highest(kept)
		changed = true
	elseif mode == "auto" then
		local best = highest(kept)
		if equipped ~= best then
			equipped = best
			changed = true
		end
	end
	if not changed then
		return nil
	end
	local updated = cloneProfile(profile)
	updated.titles = kept
	updated.titleMode = mode
	updated.equippedTitle = equipped
	return updated
end

function TitleRules.badgesFor(catalog: {Achievement}, titles: {number}?): {Achievement}
	local pending = {}
	local owned = copyNumbers(titles)
	for _, row in catalog do
		if row.badgeId ~= "" and hasNumber(owned, row.id) then
			table.insert(pending, row)
		end
	end
	return pending
end

function TitleRules.allowRequest(timestamps: {number}, now: number): (boolean, {number})
	local kept = {}
	if type(now) ~= "number" then
		return false, kept
	end
	for _, timestamp in timestamps do
		if now - timestamp < TitleRules.RATE_WINDOW_SECONDS then
			table.insert(kept, timestamp)
		end
	end
	if #kept >= TitleRules.RATE_MAX_REQUESTS then
		return false, kept
	end
	table.insert(kept, now)
	return true, kept
end

function TitleRules.selfCheck()
	local function row(id: number, score: number): Row
		return {
			Id = tostring(id),
			TitleKey = "Achievement.Title" .. tostring(id),
			Score = tostring(score),
			ShopId = string.format("rim_title_%02d", id),
			RobloxBadgeId = "",
			itemId = tostring(10079 + id),
		}
	end
	local sheet = {}
	local scores = { 200, 500, 700, 900, 1000, 1100, 1200, 1300, 1400, 1500 }
	for index, score in scores do
		table.insert(sheet, row(index, score))
	end
	local items, reason = TitleRules.catalog(sheet)
	assert(reason == "ok" and items ~= nil and #items == 10 and items[1].itemId == 10080 and items[10].itemId == 10089, "the title sheet loads")
	local catalog = items :: {Achievement}
	local function count(score: number, finished: boolean): {number}
		local profile = { schemaVersion = 1, gold = 1, exp = 2, bestScore = 3, rim = "starter_rim" }
		return TitleRules.applyScore(profile, score, finished, catalog), profile
	end
	local none, noneProfile = count(199, true)
	assert(#none == 0 and noneProfile.titles == nil and noneProfile.rim == "starter_rim", "199 unlocks nothing and keeps the rim")
	local one, oneProfile = count(200, true)
	assert(#one == 1 and one[1] == 1 and oneProfile.equippedTitle == 1 and oneProfile.titleMode == "auto", "200 unlocks the first title and equips it")
	assert(oneProfile.owned ~= nil and oneProfile.owned[1] == "rim_title_01" and oneProfile.rim == "starter_rim", "the reward rim is owned and the worn rim stays")
	local three, threeProfile = count(720, true)
	assert(#three == 3 and three[1] == 1 and three[3] == 3 and threeProfile.equippedTitle == 3, "720 unlocks the first three titles")
	local all, allProfile = count(1500, true)
	assert(#all == 10 and allProfile.equippedTitle == 10, "1500 unlocks every title")
	local practice, practiceProfile = count(1500, false)
	assert(#practice == 0 and practiceProfile.titles == nil, "practice and leaving do not unlock titles")
	local again = TitleRules.applyScore(threeProfile, 700, true, catalog)
	assert(#again == 0 and #threeProfile.titles == 3 and #threeProfile.owned == 3, "the same or a lower score does not grant again")
	local manual = {
		schemaVersion = 1,
		gold = 1,
		exp = 2,
		bestScore = 720,
		titles = { 1, 2, 3 },
		titleMode = "manual",
		equippedTitle = 1,
		owned = { "rim_title_01", "rim_title_02", "rim_title_03" },
		rim = "pilot_rim",
	}
	local gained = TitleRules.applyScore(manual, 900, true, catalog)
	assert(gained[1] == 4 and manual.equippedTitle == 1 and manual.titleMode == "manual" and manual.rim == "pilot_rim", "a manual title stays equipped")
	assert(table.find(manual.owned, "rim_title_04") ~= nil, "the new rim is still granted")
	local auto, autoReason = TitleRules.choose(manual, 0, function()
		return true
	end)
	assert(autoReason == "ok" and auto.titleMode == "auto" and auto.equippedTitle == 4 and auto.gold == 1, "auto equips the highest owned title")
	local rejected, rejectReason = TitleRules.choose(manual, 9, function()
		return true
	end)
	assert(rejectReason == "unowned" and rejected == manual, "an unowned title is rejected")
	local missing, missingReason = TitleRules.choose(manual, 4, function()
		return false
	end)
	assert(missingReason == "missing" and missing.equippedTitle == 1, "an unknown title is rejected")
	local cleaned = TitleRules.sanitize({
		titles = { 1, 99 },
		titleMode = "manual",
		equippedTitle = 99,
		gold = 8,
	}, function(id)
		return id <= 10
	end)
	assert(cleaned ~= nil and cleaned.equippedTitle == 1 and cleaned.titleMode == "auto" and cleaned.gold == 8, "a bad equipped title falls back to auto")
	assert(#TitleRules.badgesFor(catalog, { 1, 2 }) == 0, "an empty badge id does not call the badge list")
	local times = {}
	local allowed = true
	for index = 1, TitleRules.RATE_MAX_REQUESTS do
		allowed, times = TitleRules.allowRequest(times, index * 0.1)
		assert(allowed, "a title request inside the window is allowed")
	end
	allowed, times = TitleRules.allowRequest(times, 0.2)
	assert(not allowed, "too many title requests are rejected")
end

return TitleRules

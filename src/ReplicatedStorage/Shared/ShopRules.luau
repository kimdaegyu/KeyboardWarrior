--!strict
-- Gold shop. Defaults are owned by every profile. Studio rows sell only in Studio.

export type Row = {
	Id: string,
	Category: string,
	Currency: string,
	Price: string,
	PlatformProductId: string,
	Enabled: string,
	Release: string,
	Style: string,
}

export type Item = {
	id: string,
	category: string,
	currency: string,
	price: number,
	platformProductId: string,
	enabled: boolean,
	release: string,
	style: string,
}

export type Profile = {
	schemaVersion: number,
	gold: number,
	exp: number,
	bestScore: number,
	bestScoreCpm: number?,
	bestScoreLanguage: string?,
	grants: {string}?,
	uiLocale: string?,
	gloss: string?,
	typing: string?,
	tutorialSeen: boolean?,
	ranked: boolean?,
	owned: {string}?,
	body: string?,
	rim: string?,
	effect: string?,
	bgmVolume: number?,
	sfxVolume: number?,
}

export type Loadout = {
	body: string,
	rim: string,
	effect: string,
}

export type Paint = {
	body: string,
	rim: string,
	effect: string,
}

local ShopRules = {}

local STYLE = {
	Body = { purple = true, cyan = true },
	Rim = { none = true, gold = true },
	Effect = { none = true, spark = true },
}

local function flag(value: string): boolean?
	if value == "1" then
		return true
	end
	if value == "0" then
		return false
	end
	return nil
end

local function copyList(source: {string}?): {string}
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

local function copyProfile(profile: Profile): Profile
	local updated: Profile = {
		schemaVersion = profile.schemaVersion,
		gold = profile.gold,
		exp = profile.exp,
		bestScore = profile.bestScore,
		bestScoreCpm = profile.bestScoreCpm,
		bestScoreLanguage = profile.bestScoreLanguage,
		grants = copyList(profile.grants),
		owned = copyList(profile.owned),
	}
	if type(profile.uiLocale) == "string" then
		updated.uiLocale = profile.uiLocale
	end
	if type(profile.gloss) == "string" then
		updated.gloss = profile.gloss
	end
	if type(profile.typing) == "string" then
		updated.typing = profile.typing
	end
	if type(profile.bgmVolume) == "number" then
		updated.bgmVolume = profile.bgmVolume
	end
	if type(profile.sfxVolume) == "number" then
		updated.sfxVolume = profile.sfxVolume
	end
	if type(profile.tutorialSeen) == "boolean" then
		updated.tutorialSeen = profile.tutorialSeen
	end
	if profile.ranked == true then
		updated.ranked = true
	end
	if type(profile.body) == "string" then
		updated.body = profile.body
	end
	if type(profile.rim) == "string" then
		updated.rim = profile.rim
	end
	if type(profile.effect) == "string" then
		updated.effect = profile.effect
	end
	return updated
end

function ShopRules.catalog(rows: {Row}): ({Item}?, string)
	local seen: {[string]: boolean} = {}
	local items: {Item} = {}
	for _, row in rows do
		local length = string.len(row.Id)
		if length < 2 or length > 32 or string.match(row.Id, "^[a-z][a-z0-9_]+$") == nil then
			return nil, "id"
		end
		if seen[row.Id] then
			return nil, "duplicate"
		end
		seen[row.Id] = true
		local styles = STYLE[row.Category]
		if styles == nil or styles[row.Style] ~= true then
			return nil, "style"
		end
		if row.Currency ~= "Gold" and row.Currency ~= "Robux" then
			return nil, "currency"
		end
		local enabled = flag(row.Enabled)
		if enabled == nil then
			return nil, "flag"
		end
		if row.Release ~= "Default" and row.Release ~= "Studio" and row.Release ~= "Live" then
			return nil, "release"
		end
		local price = tonumber(row.Price)
		if price == nil or price < 0 or price % 1 ~= 0 or price >= math.huge then
			return nil, "price"
		end
		if row.Release == "Default" and price ~= 0 then
			return nil, "price"
		end
		if row.Release ~= "Default" and row.Currency == "Gold" and enabled and price <= 0 then
			return nil, "price"
		end
		if enabled and row.Currency == "Robux" and row.PlatformProductId == "" then
			return nil, "product"
		end
		table.insert(items, {
			id = row.Id,
			category = row.Category,
			currency = row.Currency,
			price = price,
			platformProductId = row.PlatformProductId,
			enabled = enabled,
			release = row.Release,
			style = row.Style,
		})
	end
	for _, category in { "Body", "Rim", "Effect" } do
		local defaults = 0
		for _, item in items do
			if item.category == category and item.release == "Default" and item.enabled then
				defaults += 1
			end
		end
		if defaults ~= 1 then
			return nil, "default"
		end
	end
	return items, "ok"
end

function ShopRules.find(items: {Item}, id: string?): Item?
	if type(id) ~= "string" then
		return nil
	end
	for _, item in items do
		if item.id == id then
			return item
		end
	end
	return nil
end

function ShopRules.forSale(item: Item, inStudio: boolean): boolean
	if not item.enabled or item.currency ~= "Gold" or item.price <= 0 then
		return false
	end
	if item.release == "Live" then
		return true
	end
	if item.release == "Studio" then
		return inStudio
	end
	return false
end

function ShopRules.listed(item: Item, inStudio: boolean): boolean
	if not item.enabled then
		return false
	end
	if item.release == "Default" or item.release == "Live" then
		return true
	end
	return item.release == "Studio" and inStudio
end

function ShopRules.owns(profile: Profile?, item: Item): boolean
	if item.release == "Default" then
		return true
	end
	local owned = if profile ~= nil then profile.owned else nil
	if type(owned) ~= "table" then
		return false
	end
	return table.find(owned, item.id) ~= nil
end

local function fallback(items: {Item}, category: string): string
	for _, item in items do
		if item.category == category and item.release == "Default" and item.enabled then
			return item.id
		end
	end
	return ""
end

function ShopRules.loadout(items: {Item}, profile: Profile?): Loadout
	local function chosen(field: string, category: string): string
		local id = if profile ~= nil then (profile :: any)[field] else nil
		local item = ShopRules.find(items, id)
		if item ~= nil and item.category == category and item.enabled and ShopRules.owns(profile, item) then
			return item.id
		end
		return fallback(items, category)
	end
	return {
		body = chosen("body", "Body"),
		rim = chosen("rim", "Rim"),
		effect = chosen("effect", "Effect"),
	}
end

function ShopRules.preview(items: {Item}, bodyId: string, rimId: string, effectId: string): Paint
	local function style(id: string, category: string, plain: string): string
		local item = ShopRules.find(items, id)
		if item ~= nil and item.category == category and item.enabled then
			return item.style
		end
		return plain
	end
	return {
		body = style(bodyId, "Body", "purple"),
		rim = style(rimId, "Rim", "none"),
		effect = style(effectId, "Effect", "none"),
	}
end

function ShopRules.paint(items: {Item}, profile: Profile?): Paint
	local worn = ShopRules.loadout(items, profile)
	return ShopRules.preview(items, worn.body, worn.rim, worn.effect)
end

function ShopRules.purchase(profile: Profile, item: Item?, inStudio: boolean): (Profile, string)
	if item == nil or not ShopRules.forSale(item, inStudio) then
		return profile, "closed"
	end
	if ShopRules.owns(profile, item) then
		return profile, "owned"
	end
	if profile.gold < item.price then
		return profile, "funds"
	end
	local updated = copyProfile(profile)
	updated.gold = profile.gold - item.price
	table.insert(updated.owned :: {string}, item.id)
	return updated, "bought"
end

function ShopRules.equip(profile: Profile, item: Item?): (Profile, string)
	if item == nil or not item.enabled then
		return profile, "invalid"
	end
	if not ShopRules.owns(profile, item) then
		return profile, "missing"
	end
	local current = if item.category == "Body" then profile.body elseif item.category == "Rim" then profile.rim else profile.effect
	if item.category ~= "Body" and item.category ~= "Rim" and item.category ~= "Effect" then
		return profile, "invalid"
	end
	if current == item.id then
		return profile, "equipped"
	end
	local updated = copyProfile(profile)
	if item.category == "Body" then
		updated.body = item.id
	elseif item.category == "Rim" then
		updated.rim = item.id
	else
		updated.effect = item.id
	end
	return updated, "equipped"
end

function ShopRules.selfCheck()
	local function row(id: string, category: string, price: string, release: string, style: string): Row
		return {
			Id = id,
			Category = category,
			Currency = "Gold",
			Price = price,
			PlatformProductId = "",
			Enabled = "1",
			Release = release,
			Style = style,
		}
	end
	local items, reason = ShopRules.catalog({
		row("starter_body", "Body", "0", "Default", "purple"),
		row("starter_rim", "Rim", "0", "Default", "none"),
		row("starter_effect", "Effect", "0", "Default", "none"),
		row("pilot_body", "Body", "20", "Studio", "cyan"),
		row("pilot_rim", "Rim", "30", "Studio", "gold"),
		row("pilot_effect", "Effect", "40", "Studio", "spark"),
	})
	assert(reason == "ok" and items ~= nil, "the shop sheet loads")
	local catalog = items :: {Item}
	local body = ShopRules.find(catalog, "pilot_body") :: Item
	local rim = ShopRules.find(catalog, "pilot_rim") :: Item
	local fresh: Profile = { schemaVersion = 1, gold = 51, exp = 9, bestScore = 8, grants = { "keep" }, uiLocale = "ko", gloss = "ko", typing = "ko", tutorialSeen = true, ranked = true }
	local closed, closedReason = ShopRules.purchase(fresh, body, false)
	assert(closedReason == "closed" and closed.gold == 51 and closed.owned == nil, "a studio sample does not sell on a live server")
	local poor: Profile = { schemaVersion = 1, gold = 19, exp = 0, bestScore = 0 }
	local broke, brokeReason = ShopRules.purchase(poor, body, true)
	assert(brokeReason == "funds" and broke.gold == 19 and broke.owned == nil, "a short balance is unchanged")
	local bought, buyReason = ShopRules.purchase(fresh, body, true)
	local again, againReason = ShopRules.purchase(bought, body, true)
	assert(buyReason == "bought" and bought.gold == 31 and againReason == "owned" and again.gold == 31, "one purchase charges once")
	assert(bought.exp == 9 and bought.bestScore == 8 and bought.uiLocale == "ko" and bought.typing == "ko" and bought.tutorialSeen == true and bought.ranked == true, "a purchase keeps the rest of the profile")
	assert(bought.grants ~= nil and bought.grants[1] == "keep", "a purchase keeps the reward ledger")
	local worn, equipReason = ShopRules.equip(bought, body)
	local repeated, repeatReason = ShopRules.equip(worn, body)
	assert(equipReason == "equipped" and worn.body == "pilot_body" and worn.gold == 31 and worn.rim == nil, "equip changes one slot")
	assert(repeatReason == "equipped" and repeated == worn, "equipping the same item does not write again")
	local withRim, rimReason = ShopRules.equip(worn, rim)
	assert(rimReason == "missing" and withRim.gold == 31 and withRim.body == "pilot_body", "an unowned rim cannot be equipped")
	local plain = ShopRules.loadout(catalog, nil)
	assert(plain.body == "starter_body" and plain.rim == "starter_rim" and plain.effect == "starter_effect", "a profile without cosmetics uses the defaults")
	local saved = ShopRules.loadout(catalog, worn)
	assert(saved.body == "pilot_body" and saved.rim == "starter_rim", "a saved body stays equipped")
	local preview = ShopRules.preview(catalog, "pilot_body", "pilot_rim", "starter_effect")
	local bodyOnly = ShopRules.preview(catalog, "pilot_body", "starter_rim", "starter_effect")
	assert(preview.body == "cyan" and preview.rim == "gold" and bodyOnly.body == "cyan" and bodyOnly.rim == "none", "a preview changes one slot and keeps the others")
	assert(ShopRules.paint(catalog, nil).body == "purple" and ShopRules.paint(catalog, worn).body == "cyan", "the match uses the saved body")
end

return ShopRules

--!strict
-- Gold shop. Defaults are owned by every profile. Studio rows sell only in Studio.
-- Achievement rims are granted by a title and are not sold.

local TitleRules = if script then require(script.Parent.TitleRules) else require("./TitleRules")
local DigitPadEffect = if script then require(script.Parent.DigitPadEffect) else require("./DigitPadEffect")

export type Row = {
	Id: string,
	Category: string,
	Currency: string,
	Price: string,
	PlatformProductId: string,
	Enabled: string,
	Release: string,
	Color: string,
	EffectPresetId: string?,
}

export type Item = {
	id: string,
	category: string,
	currency: string,
	price: number,
	platformProductId: string,
	enabled: boolean,
	release: string,
	color: string,
	preset: string,
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
	titles: {number}?,
	titleMode: string?,
	equippedTitle: number?,
	titleGrantId: string?,
	titleGrantIds: {number}?,
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
	preset: string,
}

local ShopRules = {}

local HIDDEN = {
	starter_rim = true,
	starter_effect = true,
}

local function colorText(value: string): string?
	local red, green, blue = string.match(value, "^(%d+);(%d+);(%d+)$")
	if red == nil or green == nil or blue == nil then
		return nil
	end
	for _, channel in { red, green, blue } do
		local number = tonumber(channel)
		if number == nil or number > 255 then
			return nil
		end
	end
	return value
end

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
	TitleRules.copyInto(updated, profile)
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
		if row.Category ~= "Body" and row.Category ~= "Rim" and row.Category ~= "Effect" then
			return nil, "category"
		end
		local color = colorText(row.Color)
		if color == nil then
			return nil, "color"
		end
		if row.Currency ~= "Gold" and row.Currency ~= "Robux" and row.Currency ~= "Achievement" then
			return nil, "currency"
		end
		if row.Currency == "Achievement" and row.Category ~= "Rim" then
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
		if row.Currency == "Achievement" and price ~= 0 then
			return nil, "price"
		end
		if row.Release ~= "Default" and row.Currency == "Gold" and enabled and price <= 0 then
			return nil, "price"
		end
		if enabled and row.Currency == "Robux" and row.PlatformProductId == "" then
			return nil, "product"
		end
		local preset = if type(row.EffectPresetId) == "string" then row.EffectPresetId else ""
		if preset ~= "" and preset ~= DigitPadEffect.Id then
			return nil, "preset"
		end
		table.insert(items, {
			id = row.Id,
			category = row.Category,
			currency = row.Currency,
			price = price,
			platformProductId = row.PlatformProductId,
			enabled = enabled,
			release = row.Release,
			color = color,
			preset = preset,
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
	local function token(id: string, category: string, plain: string): (string, string)
		local item = ShopRules.find(items, id)
		if item == nil or item.category ~= category or not item.enabled or HIDDEN[item.id] then
			return plain, ""
		end
		return item.color, item.preset
	end
	local bodyColor = token(bodyId, "Body", "126;84;255")
	local rimColor = token(rimId, "Rim", "none")
	local effectColor, effectPreset = token(effectId, "Effect", "none")
	return {
		body = bodyColor,
		rim = rimColor,
		effect = effectColor,
		preset = effectPreset,
	}
end

function ShopRules.paint(items: {Item}, profile: Profile?): Paint
	local worn = ShopRules.loadout(items, profile)
	return ShopRules.preview(items, worn.body, worn.rim, worn.effect)
end

function ShopRules.purchase(profile: Profile, item: Item?, inStudio: boolean): (Profile, string)
	if item == nil or item.currency == "Achievement" or not ShopRules.forSale(item, inStudio) then
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
	local function row(id: string, category: string, price: string, release: string, color: string, currency: string?, preset: string?): Row
		return {
			Id = id,
			Category = category,
			Currency = if currency ~= nil then currency else "Gold",
			Price = price,
			PlatformProductId = "",
			Enabled = "1",
			Release = release,
			Color = color,
			EffectPresetId = preset,
		}
	end
	local items, reason = ShopRules.catalog({
		row("starter_body", "Body", "0", "Default", "126;84;255"),
		row("starter_rim", "Rim", "0", "Default", "0;0;0"),
		row("starter_effect", "Effect", "0", "Default", "0;0;0"),
		row("pilot_body", "Body", "20", "Studio", "70;220;255"),
		row("pilot_rim", "Rim", "30", "Studio", "255;196;64"),
		row("pilot_effect", "Effect", "40", "Studio", "90;230;255"),
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
	assert(preview.body == "70;220;255" and preview.rim == "255;196;64" and bodyOnly.body == "70;220;255" and bodyOnly.rim == "none", "a preview changes one slot and keeps the others")
	assert(ShopRules.paint(catalog, nil).body == "126;84;255" and ShopRules.paint(catalog, worn).body == "70;220;255", "the match uses the saved body")
	local extra, extraReason = ShopRules.catalog({
		row("starter_body", "Body", "0", "Default", "126;84;255"),
		row("starter_rim", "Rim", "0", "Default", "0;0;0"),
		row("starter_effect", "Effect", "0", "Default", "0;0;0"),
		row("body_coral", "Body", "100", "Live", "248;105;100"),
		row("rim_title_01", "Rim", "0", "Live", "233;126;107", "Achievement"),
		row("ink_rim", "Rim", "15", "Studio", "0;0;0"),
	})
	assert(extraReason == "ok" and extra ~= nil, "live colors and achievement rims load")
	local live = extra :: {Item}
	local coral = ShopRules.find(live, "body_coral") :: Item
	local titleRim = ShopRules.find(live, "rim_title_01") :: Item
	local rich: Profile = { schemaVersion = 1, gold = 100, exp = 0, bestScore = 0 }
	local boughtLive, liveReason = ShopRules.purchase(rich, coral, false)
	assert(liveReason == "bought" and boughtLive.gold == 0, "a live gold pad sells outside Studio")
	local blocked, blockedReason = ShopRules.purchase(fresh, titleRim, true)
	assert(blockedReason == "closed" and blocked.gold == 51, "an achievement rim cannot be bought")
	local colors = ShopRules.preview(live, "starter_body", "ink_rim", "starter_effect")
	assert(colors.rim == "0;0;0" and colors.preset == "" and ShopRules.preview(live, "starter_body", "starter_rim", "starter_effect").rim == "none", "only the starter rim stays hidden")
	local digits, digitsReason = ShopRules.catalog({
		row("starter_body", "Body", "0", "Default", "126;84;255"),
		row("starter_rim", "Rim", "0", "Default", "0;0;0"),
		row("starter_effect", "Effect", "0", "Default", "0;0;0"),
		row("effect_coral", "Effect", "150", "Live", "255;139;126"),
		row("effect_sun_gold", "Effect", "2250", "Live", "255;226;114", nil, "digits"),
	})
	assert(digitsReason == "ok" and digits ~= nil, "an empty preset stays on the existing effect")
	local digitItems = digits :: {Item}
	local goldPreview = ShopRules.preview(digitItems, "starter_body", "starter_rim", "effect_sun_gold")
	local coralPreview = ShopRules.preview(digitItems, "starter_body", "starter_rim", "effect_coral")
	local barePreview = ShopRules.preview(digitItems, "starter_body", "starter_rim", "starter_effect")
	assert(goldPreview.effect == "255;226;114" and goldPreview.preset == "digits", "the golden digits preset follows the equipped effect id")
	assert(coralPreview.effect == "255;139;126" and coralPreview.preset == "", "a blank preset keeps the existing emitter")
	assert(barePreview.effect == "none" and barePreview.preset == "", "the default effect emits nothing")
	local wornDigits: Profile = { schemaVersion = 1, gold = 0, exp = 0, bestScore = 0, owned = { "effect_sun_gold" }, effect = "effect_sun_gold" }
	assert(ShopRules.paint(digitItems, wornDigits).preset == "digits" and wornDigits.effect == "effect_sun_gold", "equip still stores the product id")
	local rejected = ShopRules.catalog({
		row("starter_body", "Body", "0", "Default", "126;84;255"),
		row("starter_rim", "Rim", "0", "Default", "0;0;0"),
		row("starter_effect", "Effect", "0", "Default", "0;0;0"),
		row("effect_bad", "Effect", "10", "Live", "1;2;3", nil, "missing"),
	})
	assert(rejected == nil, "an unknown preset is rejected")
	local badColor = ShopRules.catalog({
		row("starter_body", "Body", "0", "Default", "256;0;0"),
		row("starter_rim", "Rim", "0", "Default", "0;0;0"),
		row("starter_effect", "Effect", "0", "Default", "0;0;0"),
	})
	assert(badColor == nil, "a color channel above 255 is rejected")
end

return ShopRules

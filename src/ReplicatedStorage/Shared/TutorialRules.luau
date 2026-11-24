--!strict
-- Tutorial pages come from TutorialDataSheet. Disabled pages stay in the sheet and out of the count.

export type Profile = {
	schemaVersion: number,
	gold: number,
	exp: number,
	bestScore: number,
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
}

export type Row = {
	Id: string,
	SortOrder: string,
	TitleKey: string,
	BodyKey: string,
	Enabled: string,
}

export type Step = {
	id: string,
	sortOrder: number,
	titleKey: string,
	bodyKey: string,
	enabled: boolean,
}

local TutorialRules = {}

local function flag(value: string): boolean?
	if value == "1" then
		return true
	end
	if value == "0" then
		return false
	end
	return nil
end

function TutorialRules.catalog(rows: {Row}): ({Step}?, string)
	local seen: {[string]: boolean} = {}
	local steps: {Step} = {}
	for _, row in rows do
		local length = string.len(row.Id)
		if length < 2 or length > 16 or string.match(row.Id, "^[a-z][a-z0-9]+$") == nil then
			return nil, "id"
		end
		if seen[row.Id] then
			return nil, "duplicate"
		end
		seen[row.Id] = true
		if row.TitleKey == "" or row.BodyKey == "" then
			return nil, "key"
		end
		local order = tonumber(row.SortOrder)
		if order == nil or order < 0 or order % 1 ~= 0 then
			return nil, "order"
		end
		local enabled = flag(row.Enabled)
		if enabled == nil then
			return nil, "flag"
		end
		table.insert(steps, {
			id = row.Id,
			sortOrder = order,
			titleKey = row.TitleKey,
			bodyKey = row.BodyKey,
			enabled = enabled,
		})
	end
	table.sort(steps, function(left, right)
		if left.sortOrder ~= right.sortOrder then
			return left.sortOrder < right.sortOrder
		end
		return left.id < right.id
	end)
	return steps, "ok"
end

function TutorialRules.active(steps: {Step}): {Step}
	local shown: {Step} = {}
	for _, step in steps do
		if step.enabled then
			table.insert(shown, step)
		end
	end
	return shown
end

function TutorialRules.progress(index: number, count: number): string
	return tostring(index) .. "/" .. tostring(count)
end

function TutorialRules.seenOf(value: any): boolean
	return value == true
end

function TutorialRules.acknowledge(profile: Profile): Profile
	local grants: {string} = {}
	if type(profile.grants) == "table" then
		for _, id in profile.grants do
			table.insert(grants, id)
		end
	end
	local updated: Profile = {
		schemaVersion = profile.schemaVersion,
		gold = profile.gold,
		exp = profile.exp,
		bestScore = profile.bestScore,
		grants = grants,
		tutorialSeen = true,
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
	if profile.ranked == true then
		updated.ranked = true
	end
	if type(profile.owned) == "table" then
		local owned: {string} = {}
		for _, id in profile.owned do
			if type(id) == "string" then
				table.insert(owned, id)
			end
		end
		updated.owned = owned
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

function TutorialRules.selfCheck()
	local function row(id: string, order: string, title: string, body: string, enabled: string): Row
		return {
			Id = id,
			SortOrder = order,
			TitleKey = title,
			BodyKey = body,
			Enabled = enabled,
		}
	end
	local duplicated = TutorialRules.catalog({
		row("join", "1", "Tutorial.JoinTitle", "Tutorial.JoinBody", "1"),
		row("join", "2", "Tutorial.JoinTitle", "Tutorial.JoinBody", "1"),
	})
	assert(duplicated == nil, "a repeated tutorial id is rejected")
	local flagged = TutorialRules.catalog({ row("join", "1", "Tutorial.JoinTitle", "Tutorial.JoinBody", "2") })
	assert(flagged == nil, "a tutorial flag must be zero or one")
	local steps, reason = TutorialRules.catalog({
		row("shop", "4", "Tutorial.ShopTitle", "Tutorial.ShopBody", "0"),
		row("join", "1", "Tutorial.JoinTitle", "Tutorial.JoinBody", "1"),
		row("practice", "3", "Tutorial.PracticeTitle", "Tutorial.PracticeBody", "1"),
		row("typing", "2", "Tutorial.TypingTitle", "Tutorial.TypingBody", "1"),
	})
	assert(reason == "ok" and steps ~= nil, "the tutorial sheet loads")
	local loaded = steps :: {Step}
	assert(loaded[1].id == "join" and loaded[4].id == "shop" and not loaded[4].enabled, "disabled pages keep their sort order")
	local shown = TutorialRules.active(loaded)
	assert(#shown == 3 and shown[3].id == "practice", "the shop page is prepared and hidden")
	assert(TutorialRules.progress(1, #shown) == "1/3" and TutorialRules.progress(3, #shown) == "3/3", "the counter uses enabled pages")
	loaded[4].enabled = true
	local released = TutorialRules.active(loaded)
	assert(#released == 4 and TutorialRules.progress(4, #released) == "4/4", "enabling the shop page extends the counter")
	assert(TutorialRules.seenOf(nil) == false and TutorialRules.seenOf(false) == false and TutorialRules.seenOf(true) == true, "a missing flag is unseen")
	local profile: Profile = {
		schemaVersion = 1,
		gold = 4,
		exp = 9,
		bestScore = 8,
		grants = { "a" },
		uiLocale = "ko",
		gloss = "ko",
		ranked = true,
		owned = { "pilot_body" },
		body = "pilot_body",
	}
	local first = TutorialRules.acknowledge(profile)
	local second = TutorialRules.acknowledge(first)
	assert(first.tutorialSeen == true and second.tutorialSeen == true, "completing twice leaves the flag set")
	assert(first.gold == 4 and second.gold == 4 and second.exp == 9 and second.bestScore == 8 and second.ranked == true, "tutorial confirmation keeps the balances")
	assert(second.grants ~= nil and second.grants[1] == "a" and second.uiLocale == "ko" and second.gloss == "ko", "tutorial confirmation keeps grants and language")
	assert(second.owned ~= nil and second.owned[1] == "pilot_body" and second.body == "pilot_body", "tutorial confirmation keeps the shop")
	assert(profile.tutorialSeen == nil, "confirmation does not edit the previous profile")
end

return TutorialRules

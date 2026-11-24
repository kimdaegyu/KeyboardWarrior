--!strict
-- Language choices come from LanguageDataSheet. auto is UI-only and off is gloss-only.

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
	NativeName: string,
	SortOrder: string,
	UiEnabled: string,
	PcTypingEnabled: string,
	MobileTypingEnabled: string,
	GlossEnabled: string,
}

export type Language = {
	id: string,
	nativeName: string,
	sortOrder: number,
	ui: boolean,
	pcTyping: boolean,
	mobileTyping: boolean,
	gloss: boolean,
}

export type Choice = {
	id: string,
	nativeName: string,
}

local SettingsRules = {}

local function flag(value: string): boolean?
	if value == "1" then
		return true
	end
	if value == "0" then
		return false
	end
	return nil
end

function SettingsRules.catalog(rows: {Row}): ({Language}?, string)
	local seen: {[string]: boolean} = {}
	local languages: {Language} = {}
	for _, row in rows do
		local length = string.len(row.Id)
		if row.Id == "auto" or row.Id == "off" or length < 2 or length > 8 or string.match(row.Id, "^[a-z][a-z0-9]+$") == nil then
			return nil, "id"
		end
		if seen[row.Id] then
			return nil, "duplicate"
		end
		seen[row.Id] = true
		if row.NativeName == "" then
			return nil, "name"
		end
		local order = tonumber(row.SortOrder)
		if order == nil or order < 0 or order % 1 ~= 0 then
			return nil, "order"
		end
		local ui = flag(row.UiEnabled)
		local pcTyping = flag(row.PcTypingEnabled)
		local mobileTyping = flag(row.MobileTypingEnabled)
		local gloss = flag(row.GlossEnabled)
		if ui == nil or pcTyping == nil or mobileTyping == nil or gloss == nil then
			return nil, "flag"
		end
		table.insert(languages, {
			id = row.Id,
			nativeName = row.NativeName,
			sortOrder = order,
			ui = ui,
			pcTyping = pcTyping,
			mobileTyping = mobileTyping,
			gloss = gloss,
		})
	end
	table.sort(languages, function(left, right)
		if left.sortOrder ~= right.sortOrder then
			return left.sortOrder < right.sortOrder
		end
		return left.id < right.id
	end)
	return languages, "ok"
end

function SettingsRules.uiChoices(languages: {Language}): {Choice}
	local choices: {Choice} = { { id = "auto", nativeName = "" } }
	for _, language in languages do
		if language.ui then
			table.insert(choices, { id = language.id, nativeName = language.nativeName })
		end
	end
	return choices
end

function SettingsRules.glossChoices(languages: {Language}): {Choice}
	local choices: {Choice} = { { id = "off", nativeName = "" } }
	for _, language in languages do
		if language.gloss then
			table.insert(choices, { id = language.id, nativeName = language.nativeName })
		end
	end
	return choices
end

function SettingsRules.typingChoices(languages: {Language}, mobile: boolean): {Choice}
	local choices: {Choice} = {}
	for _, language in languages do
		local enabled = if mobile then language.mobileTyping else language.pcTyping
		if enabled then
			table.insert(choices, { id = language.id, nativeName = language.nativeName })
		end
	end
	return choices
end

function SettingsRules.shownUi(languages: {Language}, value: any): string
	if type(value) ~= "string" or value == "" or value == "auto" then
		return "auto"
	end
	for _, language in languages do
		if language.id == value and language.ui then
			return value
		end
	end
	return "auto"
end

function SettingsRules.shownGloss(languages: {Language}, value: any): string
	if type(value) ~= "string" or value == "" or value == "off" then
		return "off"
	end
	for _, language in languages do
		if language.id == value and language.gloss then
			return value
		end
	end
	return "off"
end

function SettingsRules.shownTyping(languages: {Language}, value: any): string
	if type(value) == "string" then
		for _, language in languages do
			if language.id == value and language.pcTyping then
				return value
			end
		end
	end
	local choices = SettingsRules.typingChoices(languages, false)
	if choices[1] ~= nil then
		return choices[1].id
	end
	return ""
end

function SettingsRules.sessionTyping(languages: {Language}, saved: any, mobile: boolean): string
	local preference = SettingsRules.shownTyping(languages, saved)
	local choices = SettingsRules.typingChoices(languages, mobile)
	for _, choice in choices do
		if choice.id == preference then
			return preference
		end
	end
	if choices[1] ~= nil then
		return choices[1].id
	end
	return preference
end

function SettingsRules.apply(profile: Profile, languages: {Language}, uiLocale: any, gloss: any, typing: any): (Profile?, string)
	if type(uiLocale) ~= "string" or SettingsRules.shownUi(languages, uiLocale) ~= uiLocale then
		return nil, "invalid"
	end
	if type(gloss) ~= "string" or SettingsRules.shownGloss(languages, gloss) ~= gloss then
		return nil, "invalid"
	end
	if type(typing) ~= "string" or SettingsRules.shownTyping(languages, typing) ~= typing then
		return nil, "invalid"
	end
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
		uiLocale = uiLocale,
		gloss = gloss,
		typing = typing,
	}
	if type(profile.tutorialSeen) == "boolean" then
		updated.tutorialSeen = profile.tutorialSeen
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
	return updated, "ok"
end

function SettingsRules.selfCheck()
	local function row(id: string, name: string, order: string, ui: string, pc: string, mobile: string, gloss: string): Row
		return {
			Id = id,
			NativeName = name,
			SortOrder = order,
			UiEnabled = ui,
			PcTypingEnabled = pc,
			MobileTypingEnabled = mobile,
			GlossEnabled = gloss,
		}
	end
	local duplicated = SettingsRules.catalog({
		row("en", "English", "1", "1", "1", "1", "0"),
		row("en", "English", "2", "1", "1", "1", "0"),
	})
	assert(duplicated == nil, "a repeated language code is rejected")
	local flagged = SettingsRules.catalog({ row("en", "English", "1", "2", "1", "1", "0") })
	assert(flagged == nil, "a language flag must be zero or one")
	local legacy, legacyReason = SettingsRules.catalog({
		row("en", "English", "1", "1", "1", "1", "0"),
		row("ko", "한국어", "2", "1", "0", "0", "1"),
	})
	assert(legacyReason == "ok" and legacy ~= nil and #SettingsRules.typingChoices(legacy :: {Language}, false) == 1, "a disabled PC flag stays out of the typing list")
	local languages, reason = SettingsRules.catalog({
		row("en", "English", "1", "1", "1", "1", "1"),
		row("ko", "한국어", "2", "1", "1", "0", "1"),
		row("ja", "日本語", "3", "0", "0", "0", "0"),
	})
	assert(reason == "ok" and languages ~= nil, "the language sheet loads")
	local loaded = languages :: {Language}
	assert(loaded[1].id == "en" and loaded[1].ui and loaded[1].pcTyping and loaded[1].mobileTyping and loaded[1].gloss, "English is selectable as a meaning")
	assert(loaded[2].id == "ko" and loaded[2].nativeName == "한국어" and loaded[2].ui and loaded[2].gloss and loaded[2].pcTyping and not loaded[2].mobileTyping, "Korean is a UI, gloss, and PC typing language")
	assert(SettingsRules.shownUi(loaded, nil) == "auto" and SettingsRules.shownGloss(loaded, nil) == "off", "a profile without settings uses the defaults")
	assert(SettingsRules.shownTyping(loaded, nil) == loaded[1].id, "a profile without a typing language starts on the first PC language")
	assert(SettingsRules.shownUi(loaded, "ja") == "auto" and SettingsRules.shownGloss(loaded, "ja") == "off", "a disabled code is shown as the safe choice")
	assert(SettingsRules.shownGloss(loaded, "off") == "off" and SettingsRules.shownGloss(loaded, "en") == "en" and SettingsRules.shownGloss(loaded, "ko") == "ko", "off, English, and Korean meanings stay selectable")
	assert(SettingsRules.sessionTyping(loaded, nil, false) == loaded[1].id, "a missing typing value plays as the first PC language")
	assert(SettingsRules.sessionTyping(loaded, loaded[2].id, false) == loaded[2].id, "a saved PC language is used on PC")
	assert(SettingsRules.sessionTyping(loaded, loaded[2].id, true) == loaded[1].id, "a mobile session of a saved PC language uses the mobile list")
	assert(#SettingsRules.uiChoices(loaded) == 3 and #SettingsRules.glossChoices(loaded) == 3, "special values stay beside the enabled languages")
	assert(#SettingsRules.typingChoices(loaded, false) == 2 and #SettingsRules.typingChoices(loaded, true) == 1, "PC typing follows the sheet and mobile stays on its own flag")
	assert(SettingsRules.typingChoices(loaded, false)[2].nativeName == "한국어", "the typing row uses the language's own name")
	local dozenRows: {Row} = {}
	for index = 1, 12 do
		local id = "t" .. string.sub("abcdefghijkl", index, index)
		table.insert(dozenRows, row(id, id, tostring(index), "1", "0", "0", "0"))
	end
	local dozen, dozenReason = SettingsRules.catalog(dozenRows)
	assert(dozenReason == "ok" and dozen ~= nil and #SettingsRules.uiChoices(dozen :: {Language}) == 13, "a twelve-language test list stays out of the shipping sheet")
	local profile: Profile = {
		schemaVersion = 1,
		gold = 4,
		exp = 9,
		bestScore = 8,
		grants = { "a" },
	}
	local updated, applied = SettingsRules.apply(profile, loaded, "ko", "ko", "ko")
	assert(applied == "ok" and updated ~= nil and updated.uiLocale == "ko" and updated.gloss == "ko" and updated.typing == "ko", "an enabled choice is stored")
	assert(updated ~= nil and updated.gold == 4 and updated.exp == 9 and updated.bestScore == 8, "settings keep the balances")
	assert(updated ~= nil and updated.grants ~= nil and updated.grants[1] == "a", "settings keep the grant history")
	assert(profile.uiLocale == nil and profile.typing == nil and profile.gold == 4, "a rejected or applied choice does not edit the previous profile")
	assert(SettingsRules.apply(profile, loaded, "ja", "ko", "ko") == nil, "a disabled code is not saved")
	assert(SettingsRules.apply(profile, loaded, "ko", "ja", "ko") == nil and profile.gloss == nil, "a disabled gloss keeps the stored value")
	local glossed, glossReason = SettingsRules.apply(profile, loaded, "ko", "en", "ko")
	assert(glossReason == "ok" and glossed ~= nil and glossed.uiLocale == "ko" and glossed.gloss == "en" and glossed.typing == "ko", "English meaning is stored with Korean typing")
	assert(profile.gloss == nil and profile.typing == nil, "a stored gloss does not edit the previous profile")
	assert(SettingsRules.apply(profile, loaded, "ko", "ko", "ja") == nil and profile.typing == nil, "a disabled typing language is not saved")
	local cleared, clearReason = SettingsRules.apply(updated :: Profile, loaded, "auto", "off", "en")
	assert(clearReason == "ok" and cleared ~= nil and cleared.uiLocale == "auto" and cleared.gloss == "off" and cleared.typing == "en" and cleared.gold == 4, "auto and off are explicit saved values")
	local seenProfile: Profile = {
		schemaVersion = profile.schemaVersion,
		gold = profile.gold,
		exp = profile.exp,
		bestScore = profile.bestScore,
		grants = profile.grants,
		tutorialSeen = true,
		ranked = true,
		owned = { "pilot_body" },
		body = "pilot_body",
	}
	local kept, keptReason = SettingsRules.apply(seenProfile, loaded, "ko", "off", "ko")
	assert(keptReason == "ok" and kept ~= nil and kept.tutorialSeen == true and kept.ranked == true and kept.typing == "ko" and kept.gold == 4, "a language save keeps the tutorial flag")
	assert(kept.owned ~= nil and kept.owned[1] == "pilot_body" and kept.body == "pilot_body", "a language save keeps the shop")
end

return SettingsRules

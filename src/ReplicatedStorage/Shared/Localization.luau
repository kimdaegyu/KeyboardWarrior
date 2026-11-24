--!strict
--[[
	Localization
	역할: LocalizationTable 키를 통해 플레이어 언어에 맞는 문자열을 조회합니다.
	      클라이언트는 계정 LocaleId보다 경험 언어 Translator.LocaleId를 먼저 사용합니다.
]]

local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Localization = {}

export type TextArgs = { [string]: string | number }

local IS_SERVER = RunService:IsServer()
local translatorCache: { [Player]: Translator } = {}
local translatorLocales: { [Player]: string } = {}
local englishTranslator: Translator? = nil
local localTable: LocalizationTable? = nil
local localEntries: { [string]: any } = {}
local localTranslators: { [string]: Translator } = {}
local activeLocale: string? = nil
local pinnedLocale: string? = nil
local localeWatchStarted = false
local watchedTranslator: Translator? = nil
local translatorLocaleConnection: RBXScriptConnection? = nil
local listeners: { () -> () } = {}

type TextBinding = {
	object: TextLabel | TextButton | TextBox,
	key: string,
	args: TextArgs?,
	fallback: string?,
}

local bindings: { TextBinding } = {}

local function normalizeLocale(locale: string): string
	return string.lower((string.gsub(locale, "_", "-")))
end

local function accountLocale(player: Player?): string
	return if player then normalizeLocale(player.LocaleId) else "en-us"
end

local function playerLocale(player: Player?): string
	if not IS_SERVER and activeLocale ~= nil then
		local localPlayer = Players.LocalPlayer
		if player == nil or player == localPlayer then
			return activeLocale
		end
	end
	return accountLocale(player)
end

local function cachedPlayerTranslator(player: Player): Translator?
	if translatorLocales[player] ~= playerLocale(player) then
		translatorCache[player] = nil
		translatorLocales[player] = nil
	end
	return translatorCache[player]
end

local function resolvePlayer(player: Player?): Player?
	if player then
		return player
	end

	if not IS_SERVER then
		return Players.LocalPlayer
	end

	return nil
end

local watchPlayerLocale: (Player) -> ()
local watchTranslator: (Player, Translator) -> ()
local publishLocale: (string) -> ()
local adoptLocale: (string) -> ()

local function fetchTranslator(player: Player): Translator?
	local cached = cachedPlayerTranslator(player)
	if cached then
		return cached
	end

	local locale = playerLocale(player)
	local ok, translator = pcall(function()
		return LocalizationService:GetTranslatorForPlayerAsync(player)
	end)

	if not ok or translator == nil then
		warn(`[Localization] Failed to get translator for {player.Name}: {translator}`)
		return nil
	end

	if playerLocale(player) ~= locale then
		return nil
	end
	local reported = (translator :: any).LocaleId
	local translatorLocale = if typeof(reported) == "string" and reported ~= "" then normalizeLocale(reported) else locale
	translatorCache[player] = translator
	translatorLocales[player] = translatorLocale
	if not IS_SERVER and player == Players.LocalPlayer then
		watchPlayerLocale(player)
		watchTranslator(player, translator)
		if typeof(reported) == "string" and reported ~= "" then
			adoptLocale(translatorLocale)
		end
	end
	return translator
end

local function fetchEnglishTranslator(): Translator?
	if englishTranslator ~= nil then
		return englishTranslator
	end

	local ok, translator = pcall(function()
		return LocalizationService:GetTranslatorForLocaleAsync("en-us")
	end)
	if not ok or translator == nil then
		return nil
	end

	englishTranslator = translator
	return translator
end

local function normalizeArgs(args: TextArgs?): { [string]: string }?
	if args == nil then
		return nil
	end

	local normalized: { [string]: string } = {}
	for name, value in args do
		normalized[name] = tostring(value)
	end
	return normalized
end

local function formatByTranslator(translator: Translator, key: string, args: { [string]: string }?): string?
	local ok, text = pcall(function()
		if args ~= nil then
			return translator:FormatByKey(key, args)
		end
		return translator:FormatByKey(key)
	end)
	if not ok or typeof(text) ~= "string" or text == "" then
		return nil
	end
	if args ~= nil and string.find(text, "{", 1, true) ~= nil then
		return nil
	end
	return text
end

-- The Rojo CSV is the authoritative manual translation table. Only fall back
-- to Roblox's cloud translator when this key has no local value for the locale.
local function readLocal(key: string, locale: string, args: { [string]: string }?): string?
	local candidate = LocalizationService:FindFirstChild("CoreStrings")
	if candidate == nil or not candidate:IsA("LocalizationTable") then
		return nil
	end
	if localTable ~= candidate then
		local ok, entries = pcall(function()
			return candidate:GetEntries()
		end)
		if not ok then
			return nil
		end
		localTable = candidate
		localEntries = {}
		localTranslators = {}
		for _, entry in entries do
			if typeof(entry.Key) == "string" then
				localEntries[entry.Key] = entry
			end
		end
	end
	local entry = localEntries[key]
	if entry == nil then
		return nil
	end
	local language = string.match(locale, "^[^-]+") or locale
	local values = entry.Values or {}
	local targetLocale: string
	if typeof(values[locale]) == "string" and values[locale] ~= "" then
		targetLocale = locale
	elseif typeof(values[language]) == "string" and values[language] ~= "" then
		-- ja-jp -> ja, id-id -> id, vi-vn -> vi, th-th -> th,
		-- hi-in -> hi, es-es/es-mx -> es, ko-kr -> ko, pt-br/pt-pt -> pt.
		-- The pt column is authored in Brazilian Portuguese.
		targetLocale = language
	elseif language == (string.match(candidate.SourceLocaleId, "^[^-]+") or candidate.SourceLocaleId) and typeof(entry.Source) == "string" and entry.Source ~= "" then
		targetLocale = candidate.SourceLocaleId
	else
		return nil
	end
	local translator = localTranslators[targetLocale]
	if translator == nil then
		local ok, result = pcall(function()
			return candidate:GetTranslator(targetLocale)
		end)
		if not ok then
			return nil
		end
		translator = result :: Translator
		localTranslators[targetLocale] = translator
	end
	return formatByTranslator(translator, key, args)
end

local function readCached(key: string, player: Player?, args: { [string]: string }?): string?
	local manualText = readLocal(key, playerLocale(player), args)
	if manualText ~= nil then
		return manualText
	end
	if player ~= nil then
		local translator = cachedPlayerTranslator(player)
		if translator ~= nil then
			local text = formatByTranslator(translator, key, args)
			if text ~= nil then
				return text
			end
		end
	end

	local sourceText = readLocal(key, "en-us", args)
	if sourceText ~= nil then
		return sourceText
	end
	if englishTranslator ~= nil then
		return formatByTranslator(englishTranslator, key, args)
	end

	return nil
end

function Localization.preloadAsync(player: Player?): ()
	local targetPlayer = resolvePlayer(player)
	if targetPlayer ~= nil then
		fetchTranslator(targetPlayer)
	end
	fetchEnglishTranslator()
end

-- 언어가 바뀌면 다음 조회가 새 Translator 를 받게 합니다.
function Localization.invalidate(player: Player?)
	local targetPlayer = resolvePlayer(player)
	if targetPlayer ~= nil then
		translatorCache[targetPlayer] = nil
		translatorLocales[targetPlayer] = nil
	end
end

function Localization.currentLocale(player: Player?): string
	return playerLocale(resolvePlayer(player))
end

local function copyArgs(args: TextArgs?): TextArgs?
	if args == nil then
		return nil
	end
	local copy: TextArgs = {}
	for name, value in args do
		copy[name] = value
	end
	return copy
end

local function removeBinding(binding: TextBinding)
	local index = table.find(bindings, binding)
	if index ~= nil then
		table.remove(bindings, index)
	end
end

local function applyBinding(binding: TextBinding)
	local object = binding.object
	if object.Parent == nil then
		removeBinding(binding)
		return
	end
	local text = Localization.getText(binding.key, nil, binding.args)
	if (text == binding.key or text == "") and binding.fallback ~= nil then
		text = binding.fallback
	end
	object.AutoLocalize = false
	object.Text = text
end

local function defer(callback: () -> ())
	if typeof(task) == "table" and typeof(task.spawn) == "function" then
		task.spawn(callback)
		return
	end
	callback()
end

local function fireChanged()
	for _, callback in table.clone(listeners) do
		defer(callback)
	end
end

publishLocale = function(locale: string)
	local normalized = normalizeLocale(locale)
	if normalized == "" or normalized == activeLocale then
		return
	end
	activeLocale = normalized
	table.clear(translatorCache)
	table.clear(translatorLocales)
	local stale: { TextBinding } = {}
	for _, binding in bindings do
		table.insert(stale, binding)
	end
	for _, binding in stale do
		applyBinding(binding)
	end
	fireChanged()
end

adoptLocale = function(locale: string)
	if pinnedLocale ~= nil then
		return
	end
	publishLocale(locale)
end

function Localization.setPreferredLocale(choice: string?)
	if IS_SERVER then
		return
	end
	if choice == nil or choice == "" or choice == "auto" then
		pinnedLocale = nil
		local player = Players.LocalPlayer
		local reported: string? = nil
		if player ~= nil then
			local current = translatorCache[player] or watchedTranslator
			local localeId = if current ~= nil then (current :: any).LocaleId else nil
			reported = if typeof(localeId) == "string" and localeId ~= "" then localeId else accountLocale(player)
		end
		if reported ~= nil then
			publishLocale(reported)
		end
		return
	end
	pinnedLocale = choice
	publishLocale(choice)
end

watchTranslator = function(player: Player, translator: Translator)
	if watchedTranslator == translator then
		return
	end
	if translatorLocaleConnection ~= nil then
		translatorLocaleConnection:Disconnect()
		translatorLocaleConnection = nil
	end
	watchedTranslator = translator
	local signalSource = translator :: any
	if typeof(signalSource.GetPropertyChangedSignal) ~= "function" then
		return
	end
	translatorLocaleConnection = signalSource:GetPropertyChangedSignal("LocaleId"):Connect(function()
		if pinnedLocale ~= nil then
			return
		end
		local reported = signalSource.LocaleId
		if typeof(reported) ~= "string" or reported == "" then
			return
		end
		translatorCache[player] = nil
		translatorLocales[player] = nil
		adoptLocale(reported)
	end)
end

watchPlayerLocale = function(player: Player)
	if localeWatchStarted or typeof(player.GetPropertyChangedSignal) ~= "function" then
		return
	end
	localeWatchStarted = true
	player:GetPropertyChangedSignal("LocaleId"):Connect(function()
		if pinnedLocale ~= nil then
			return
		end
		translatorCache[player] = nil
		translatorLocales[player] = nil
		defer(function()
			local translator = fetchTranslator(player)
			local reported = if translator ~= nil then (translator :: any).LocaleId else nil
			if typeof(reported) ~= "string" or reported == "" then
				adoptLocale(accountLocale(player))
			end
		end)
	end)
	if typeof(task) ~= "table" or typeof(task.wait) ~= "function" then
		return
	end
	defer(function()
		while player.Parent ~= nil do
			task.wait(0.5)
			if pinnedLocale ~= nil then
				if activeLocale ~= pinnedLocale then
					publishLocale(pinnedLocale)
				end
				continue
			end
			local current = translatorCache[player]
			if current == nil then
				current = watchedTranslator
			end
			local reported = if current ~= nil then (current :: any).LocaleId else nil
			if typeof(reported) == "string" and reported ~= "" then
				local nextLocale = normalizeLocale(reported)
				if nextLocale ~= activeLocale then
					translatorCache[player] = nil
					translatorLocales[player] = nil
					adoptLocale(nextLocale)
				end
			end
		end
	end)
end

function Localization.onChanged(callback: () -> ()): () -> ()
	table.insert(listeners, callback)
	return function()
		local index = table.find(listeners, callback)
		if index ~= nil then
			table.remove(listeners, index)
		end
	end
end

function Localization.bind(object: TextLabel | TextButton | TextBox, key: string, args: TextArgs?, fallback: string?): () -> ()
	local binding: TextBinding = {
		object = object,
		key = key,
		args = copyArgs(args),
		fallback = fallback,
	}
	table.insert(bindings, binding)
	applyBinding(binding)
	local function remove()
		removeBinding(binding)
	end
	local destroying = (object :: any).Destroying
	if typeof(destroying) == "RBXScriptSignal" or (typeof(destroying) == "table" and typeof(destroying.Connect) == "function") then
		destroying:Connect(remove)
	end
	return remove
end

function Localization.getTextAsync(key: string, player: Player?, args: TextArgs?): string
	local normalized = normalizeArgs(args)
	local targetPlayer = resolvePlayer(player)
	local manualText = readLocal(key, playerLocale(targetPlayer), normalized)
	if manualText ~= nil then
		return manualText
	end

	if targetPlayer ~= nil then
		local translator = fetchTranslator(targetPlayer)
		if translator ~= nil then
			local text = formatByTranslator(translator, key, normalized)
			if text ~= nil then
				return text
			end
		end
	end

	local sourceText = readLocal(key, "en-us", normalized)
	if sourceText ~= nil then
		return sourceText
	end
	local english = fetchEnglishTranslator()
	if english ~= nil then
		local text = formatByTranslator(english, key, normalized)
		if text ~= nil then
			return text
		end
	end

	warn(`[Localization] Missing translation for key: {key}`)
	return key
end

function Localization.getText(key: string, player: Player?, args: TextArgs?): string
	local text = readCached(key, resolvePlayer(player), normalizeArgs(args))
	if text ~= nil then
		return text
	end

	return key
end

Players.PlayerRemoving:Connect(function(player: Player)
	translatorCache[player] = nil
	translatorLocales[player] = nil
end)

return Localization

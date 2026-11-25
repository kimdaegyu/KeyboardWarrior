--!strict
-- Local, table-driven 2D music and effects.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local TableData = require(ReplicatedStorage.Shared.TableData)

type Row = {[string]: string}
type Track = { sound: Sound, row: Row, tween: Tween? }
local SoundManager = {}
local emit: ((string) -> ())? = nil
local desiredBgm = 100
local desiredSfx = 100
local musicBus: SoundGroup? = nil
local effectBus: SoundGroup? = nil

local function pushVolumes()
	if musicBus ~= nil then
		musicBus.Volume = desiredBgm / 100
	end
	if effectBus ~= nil then
		effectBus.Volume = desiredSfx / 100
	end
end

function SoundManager.setVolumes(bgm: number, sfx: number)
	desiredBgm = math.clamp(bgm, 0, 100)
	desiredSfx = math.clamp(sfx, 0, 100)
	pushVolumes()
end

function SoundManager.play(key: string)
	if emit then emit(key) end
end

function SoundManager.bind(root: Frame): () -> ()
	local match = ReplicatedStorage:WaitForChild("MatchState")
	local player = Players.LocalPlayer
	local rows: {[string]: Row} = {}
	for _, row in TableData.rows("SoundDataSheet") do
		if row.Enabled == "1" and row.SpatialMode == "Global2D" and row.AssetId:match("^%d+$") then
			rows[row.SoundKey] = row
		end
	end
	local container = Instance.new("Folder")
	container.Name = "KeyboardWarriorAudio"
	container.Parent = SoundService
	local function group(name: string): SoundGroup
		local bus = Instance.new("SoundGroup")
		bus.Name = name
		bus.Parent = container
		return bus
	end
	local music, effects = group("BGM"), group("SFX")
	musicBus = music
	effectBus = effects
	pushVolumes()
	local function soundFor(row: Row, bus: SoundGroup): Sound
		local sound = Instance.new("Sound")
		sound.Name = row.SoundKey
		sound.SoundId = "rbxassetid://" .. row.AssetId
		sound.Volume = tonumber(row.Volume) or 0.5
		local low = tonumber(row.PlaybackSpeedMin) or 1
		local high = tonumber(row.PlaybackSpeedMax) or low
		sound.PlaybackSpeed = low + math.random() * math.max(0, high - low)
		sound.Looped = row.Looped == "1"
		sound.SoundGroup = bus
		sound.Parent = container
		return sound
	end

	local tracks: {[string]: Track} = {}
	local voices: {[string]: {Sound}} = {}
	local lastPlay: {[string]: number} = {}
	local function effect(key: string)
		local row = rows[key]
		if not row or row.Category == "BGM" then return end
		local now = os.clock()
		if now - (lastPlay[key] or -math.huge) < (tonumber(row.Cooldown) or 0) then return end
		local pool = voices[key] or {}
		voices[key] = pool
		local voice: Sound? = nil
		for _, sound in pool do
			if not sound.Playing then voice = sound break end
		end
		if not voice then
			if #pool >= (tonumber(row.MaxConcurrent) or 1) then return end
			voice = soundFor(row, effects)
			table.insert(pool, voice)
		end
		lastPlay[key] = now
		local sound = voice :: Sound
		local generation = (sound:GetAttribute("Generation") or 0) + 1
		sound:SetAttribute("Generation", generation)
		sound:Play()
		-- Allow the first download before starting the clip's duration limit.
		task.spawn(function()
			local deadline = os.clock() + 8
			while sound.Parent and sound:GetAttribute("Generation") == generation and not sound.IsLoaded and os.clock() < deadline do
				task.wait(0.1)
			end
			if not sound.Parent or sound:GetAttribute("Generation") ~= generation then return end
			local limit = tonumber(row.MaxDuration) or 0
			if sound.IsLoaded then
				if limit <= 0 then return end
				task.wait(limit)
			end
			if sound.Parent and sound:GetAttribute("Generation") == generation then sound:Stop() end
		end)
	end
	emit = effect

	local current: string? = nil
	local function fade(track: Track, volume: number, duration: number)
		if track.tween then track.tween:Cancel() end
		local tween = TweenService:Create(track.sound, TweenInfo.new(duration), {Volume = volume})
		track.tween = tween
		tween.Completed:Once(function(state)
			if state == Enum.PlaybackState.Completed and track.tween == tween then
				track.tween = nil
				if volume == 0 then track.sound:Stop() end
			end
		end)
		tween:Play()
	end
	local function syncMusic()
		local playing = match:GetAttribute("Phase") == "Play" and player:GetAttribute("InMatch") == true
		local key = if playing then "BgmMatch" else "BgmLobby"
		if current == key then return end
		local previous = if current then tracks[current] else nil
		if previous then fade(previous, 0, tonumber(previous.row.FadeOut) or 0) end
		current = key
		if playing then effect("MatchStart") end
		local row = rows[key]
		if not row then return end
		local track = tracks[key]
		if not track then
			track = {sound = soundFor(row, music), row = row, tween = nil}
			tracks[key] = track
		end
		if not track.sound.Playing then
			track.sound.Volume = 0
			track.sound:Play()
		end
		fade(track, tonumber(row.Volume) or 0.5, tonumber(row.FadeIn) or 0)
	end
	local connections = {
		match:GetAttributeChangedSignal("Phase"):Connect(syncMusic),
		player:GetAttributeChangedSignal("InMatch"):Connect(syncMusic),
	}
	for _, attribute in {"ShopOpen", "RankOpen", "SettingsOpen", "PracticeOpen", "TutorialOpen"} do
		local wasOpen = root:GetAttribute(attribute) == true
		table.insert(connections, root:GetAttributeChangedSignal(attribute):Connect(function()
			local open = root:GetAttribute(attribute) == true
			if open ~= wasOpen then
				wasOpen = open
				effect(if open then "UIOpen" else "UIClose")
			end
		end))
	end
	syncMusic()
	return function()
		if musicBus == music then
			musicBus = nil
		end
		if effectBus == effects then
			effectBus = nil
		end
		if emit == effect then emit = nil end
		for _, connection in connections do connection:Disconnect() end
		for _, track in tracks do
			if track.tween then track.tween:Cancel() end
		end
		container:Destroy()
	end
end

return SoundManager

-- Exercise the actual client state machine with a controlled timer and server replies.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local receive
local requests = {}
local timers = {}
local function noop() end
local remotes = {
    SettingsRequest = { FireServer = noop },
    TypingDevice = { FireServer = noop },
    SettingsState = { OnClientEvent = { Connect = function(_, callback) receive = callback end } },
    SettingsApply = { FireServer = function(_, ...) table.insert(requests, {...}) end },
}
local function pass(_, value) return value end
local modules = {
    Gloss = {}, Localization = { setPreferredLocale = noop }, SoundManager = { setVolumes = noop },
    TableData = { rows = function() return {} end },
    SettingsRules = { catalog = function() return {} end, shownUi = pass, shownGloss = pass,
        shownTyping = pass, shownVolume = function(value) return value end },
}
local storage = { Shared = modules, WaitForChild = function(_, key) return assert(remotes[key]) end }
local state = luau.load(fs.readFile("src/StarterPlayerScripts/SettingsState.luau"), {
    environment = {
        game = { GetService = function(_, key) return if key == "ReplicatedStorage" then storage else {TouchEnabled = false} end },
        script = {Parent = modules}, require = function(module) return module end,
        task = {
            delay = function(seconds, callback)
                assert(seconds == 0.5)
                local token = {run = callback}
                table.insert(timers, token)
                return token
            end,
            cancel = function(token) token.run = nil end,
        },
    },
})()
local function tick()
    local due = timers
    timers = {}
    for _, token in due do if token.run then token.run() end end
end
local function choice(volume)
    return { uiLocale = "en", gloss = "off", typing = "en", bgmVolume = volume, sfxVolume = 100 }
end
local function reply(status, volume)
    local message = choice(volume)
    message.saveState = status
    receive(message)
end
state.start()
reply("saved", 100)
state.queue(choice(100))
tick()
assert(#requests == 0, "unchanged settings must not save")
state.queue(choice(60))
state.queue(choice(40))
assert(#requests == 0)
tick()
assert(#requests == 1 and requests[1][4] == 40, "rapid edits should coalesce")
state.queue(choice(20))
state.flush()
reply("saving", 40)
assert(state.pending().bgmVolume == 20 and #requests == 1)
reply("saved", 40)
assert(#requests == 2 and requests[2][4] == 20 and state.saveState() == "saving", "close during save must preserve newer edit")
reply("failed", 40)
assert(state.pending().bgmVolume == 20)
state.retry()
assert(#requests == 3 and requests[3][4] == 20)
reply("saved", 20)
state.queue(choice(10))
state.flush()
tick()
assert(#requests == 4 and requests[4][4] == 10, "close before debounce sends exactly once")
reply("saved", 10)
assert(state.pending() == nil and state.applied().bgmVolume == 10)
print("PASS settings autosave transitions")

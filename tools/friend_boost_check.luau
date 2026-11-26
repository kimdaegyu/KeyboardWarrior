local fs = require("@lune/fs")
local luau = require("@lune/luau")
local config = require("../src/ReplicatedStorage/Shared/IngameConstants")
local function signal()
	return {Connect = function(self, fn) self.fire = fn end}
end
local players = {PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end}
local jobs = {}
local env = {
	game = {GetService = function(_, name)
		return if name == "Players" then players else {Shared = {IngameConstants = config}}
	end},
	require = function(value) return value end,
	task = {
		spawn = function(fn) table.insert(jobs, coroutine.create(fn)) end,
		wait = coroutine.yield,
	},
}
local service = luau.load(fs.readFile("src/ServerScriptService/Core/FriendBoostService.luau"), {
	environment = env, injectGlobals = true,
})()
service.start()
local function join(id, connected)
	local player = {UserId = id, SetAttribute = function(self, key, value) self[key] = value end,
		IsFriendsWithAsync = function() return connected end}
	players.PlayerAdded.fire(player)
	return player
end
local function run()
	for _, job in jobs do
		if coroutine.status(job) == "suspended" then assert(coroutine.resume(job)) end
	end
end
local me = join(1, true)
assert(me.FriendBoostPercent == 0)
local party = {}
for i = 1, 4 do
	party[i] = join(i + 1, true)
	run()
	assert(me.FriendBoostPercent == math.min(i, 3) * 10)
end
local stranger = join(6, false)
run()
assert(stranger.FriendBoostPercent == 0 and me.FriendBoostPercent == 30)
for i = 4, 1, -1 do
	players.PlayerRemoving.fire(party[i])
	assert(me.FriendBoostPercent == math.min(i - 1, 3) * 10)
end
local left = join(7, true)
players.PlayerRemoving.fire(left)
run()
assert(me.FriendBoostPercent == 0, "discard a lookup completed after leave")
print("PASS friend boost membership, cap and leave")

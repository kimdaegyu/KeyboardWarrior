-- Exercise the real snapshot builder with two servers sharing fake Roblox stores.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local rules = require("../src/ReplicatedStorage/Shared/RankRules")
local config = require("../src/ReplicatedStorage/Shared/IngameConstants")
local now, ownerId = 1000, 0
local function store()
	local values = {}
	return {
		values = values,
		GetAsync = function(_, key) return values[key] end,
		UpdateAsync = function(_, key, transform)
			local value = transform(values[key])
			if value ~= nil then values[key] = value end
			return value
		end,
	}
end
local shared, index = store(), store()
local services = {
	MemoryStoreService = {GetHashMap = function() return shared end},
	DataStoreService = {
		GetDataStore = function() return index end,
		GetRequestBudgetForRequestType = function() return 100 end,
	},
	HttpService = {GenerateGUID = function() ownerId += 1 return tostring(ownerId) end},
	ReplicatedStorage = {Shared = {IngameConstants = config, RankRules = rules}},
}
local module = luau.load(fs.readFile("src/ServerScriptService/Core/RankSnapshots.luau"), {
	environment = {
		game = {GetService = function(_, name) return services[name] end},
		require = function(value) return value end,
		os = {time = function() return now end, clock = function() return now end},
		DateTime = {now = function() return {UnixTimestampMillis = now * 1000} end},
		Enum = {DataStoreRequestType = {OrderedList = "list"}},
		Instance = {new = function() return {} end},
	},
	injectGlobals = true,
})()
local failPage = false
local scans = 0
local ordered = {GetSortedAsync = function(_, _, size)
	scans += 1
	local offset = 0
	return {
		IsFinished = false,
		GetCurrentPage = function()
			local page = {}
			for i = offset + 1, offset + size do
				local score = if i >= 9998 then 1 else 20000 - i
				table.insert(page, {key = tostring(i), value = score})
			end
			return page
		end,
		AdvanceToNextPageAsync = function()
			assert(not failPage, "injected page error")
			offset += size
		end,
	}
end}
local a = module.new(ordered, "test", "test")
local b = module.new(ordered, "test", "test")
assert(a.cutoff() == nil)
a.refreshIndex()
b.refreshIndex()
assert(scans == 1 and a.cutoff() == 1 and b.cutoff() == 1)
assert(b.personal(51, 19949) == 51)
assert(b.personal(9999, 1) == 9998)
assert(b.personal(10001, 1, 1) == 9998, "ties beyond scanned limit")
local pending, outside = b.personal(51, 25000)
assert(not pending and not outside, "new personal score awaits aggregation")
pending, outside = b.personal(10002, 0)
assert(not pending and outside)
local builds = 0
local function build()
	builds += 1
	return {{userId = 1, rank = 1, score = 19999, cpm = 100, language = "KO"}}
end
assert(a.top(build).rows[1].cpm == 100)
assert(b.top(build).rows[1].language == "KO" and builds == 1)
now += config.Rank.IndexSeconds + 1
failPage = true
assert(not pcall(a.refreshIndex))
assert(index.values.current.slot == 0 and a.personal(51, 19949) == 51)
failPage = false
local update = index.UpdateAsync
index.UpdateAsync = function(self, key, transform)
	if key == "1/2" then error("injected chunk failure") end
	return update(self, key, transform)
end
assert(not pcall(a.refreshIndex))
assert(index.values["1/1"] and index.values.current.slot == 0, "partial chunks stay unpublished")
assert(a.personal(501, 19499) == 501)
index.UpdateAsync = update
now += 1
a.refreshIndex()
assert(index.values.current.slot == 1)
print("PASS shared Top 50, personal Top 10000, boundary ties and failed refresh")

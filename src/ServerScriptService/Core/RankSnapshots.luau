--!strict
-- Versioned personal ranks live in DataStore. MemoryStore coordinates builders
-- and shares the fully decorated Top 50 between servers.
local DataStoreService = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local config = require(ReplicatedStorage.Shared.IngameConstants).Rank
local rules = require(ReplicatedStorage.Shared.RankRules)

local RankSnapshots = {}

function RankSnapshots.new(ordered: OrderedDataStore, storeName: string, scope: string)
	local shared = MemoryStoreService:GetHashMap(storeName .. "_cache_v1_" .. scope)
	local index = DataStoreService:GetDataStore(storeName .. "_places_v1", scope)
	local owner = HttpService:GenerateGUID(false)
	local manifest: any = nil
	local chunks: {[number]: any} = {}
	local leaseSeconds = 90

	local function lease(key: string): boolean
		local token = shared:UpdateAsync(key, function(current)
			if current == nil or current == owner then return owner end
			return nil
		end, leaseSeconds)
		return token == owner
	end

	local function adopt(value: any)
		if value and (not manifest or value.version > manifest.version) then
			manifest = value
			chunks = {}
		end
	end

	local function refreshIndex()
		if manifest and os.time() - manifest.at < config.IndexSeconds then return end
		adopt(index:GetAsync("current"))
		if manifest and os.time() - manifest.at < config.IndexSeconds then return end
		if not lease("indexLease") then return end
		-- Another builder may have published between our first read and the lease.
		local options = Instance.new("DataStoreGetOptions")
		options.UseCache = false
		adopt(index:GetAsync("current", options))
		if manifest and os.time() - manifest.at < config.IndexSeconds then return end

		local renewed = os.clock()
		local function keepLease()
			if os.clock() - renewed >= leaseSeconds / 3 then
				assert(lease("indexLease"), "rank index lease lost")
				renewed = os.clock()
			end
		end
		local function waitForPage()
			while DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.OrderedList) < 2 do
				keepLease()
				task.wait(2)
			end
			keepLease()
		end
		local version = DateTime.now().UnixTimestampMillis
		local startedAt = os.time()
		local slot = if manifest then 1 - manifest.slot else 0
		waitForPage()
		local pages = ordered:GetSortedAsync(false, 100)
		local records = {}
		local seen: {[number]: boolean} = {}
		local cutoff, cutoffRank = nil, nil
		local previous: number? = nil
		local place = 0
		while true do
			for _, item in pages:GetCurrentPage() do
				local id = tonumber(item.key)
				if not id or seen[id] then continue end
				seen[id] = true
				local score = item.value
				assert(previous == nil or score <= previous, "rank page order changed during scan")
				if previous ~= score then place = #records + 1 end
				previous = score
				table.insert(records, {id, score, place})
				if #records == config.PersonalLimit then
					cutoff, cutoffRank = score, place
					break
				end
			end
			if cutoff ~= nil or pages.IsFinished then break end
			waitForPage()
			pages:AdvanceToNextPageAsync()
		end

		table.sort(records, function(a, b) return a[1] < b[1] end)
		local ends = {}
		for first = 1, #records, 500 do
			keepLease()
			local last = math.min(first + 499, #records)
			local rows = {}
			for i = first, last do rows[tostring(records[i][1])] = {records[i][2], records[i][3]} end
			table.insert(ends, records[last][1])
			local written = index:UpdateAsync(`{slot}/{#ends}`, function(old)
				if old and old.version > version then return nil end
				return {version = version, rows = rows}
			end)
			assert(written and written.version == version, "rank chunk superseded")
		end
		-- Flip the directory only after every chunk is readable.
		assert(lease("indexLease"), "rank index lease lost before commit")
		adopt(index:UpdateAsync("current", function(old)
			if old and old.version >= version then return nil end
			return {version = version, at = os.time(), startedAt = startedAt, slot = slot,
				ends = ends, cutoff = cutoff, cutoffRank = cutoffRank}
		end))
	end

	local function personal(id: number, score: number, confirmed: number?, changedAt: number?): (number?, boolean)
		local view = manifest
		if not view then return nil, false end
		if view.cutoff and score < view.cutoff then return nil, true end
		if view.cutoff == score and confirmed and confirmed >= score and (not changedAt or changedAt < view.startedAt) then
			return view.cutoffRank, false
		end
		for i, lastId in view.ends do
			if id > lastId then continue end
			local chunk = chunks[i]
			if not chunk then
				local ok, value = pcall(function() return index:GetAsync(`{view.slot}/{i}`) end)
				if not ok or not value or value.version ~= view.version or manifest ~= view then return nil, false end
				chunk = value.rows
				chunks[i] = chunk
			end
			local row = chunk[tostring(id)]
			return if row and row[1] == score then row[2] else nil, false
		end
		return nil, false
	end

	local function top(build: ((() -> ())?) -> {rules.Placed}): any
		local cached: any = shared:GetAsync("top")
		if cached and os.time() - cached.at < config.CacheSeconds then return cached end
		if not lease("topLease") then return cached end
		cached = shared:GetAsync("top")
		if cached and os.time() - cached.at < config.CacheSeconds then return cached end
		local version = DateTime.now().UnixTimestampMillis
		local renewed = os.clock()
		local rows = build(function()
			if os.clock() - renewed >= leaseSeconds / 3 then
				assert(lease("topLease"), "Top 50 lease lost")
				renewed = os.clock()
			end
		end)
		local nextBoard = {version = version, at = os.time(), rows = rows}
		return shared:UpdateAsync("top", function(old)
			return if old and old.version > version then old else nextBoard
		end, config.IndexSeconds * 2)
	end

	return {
		top = top, refreshIndex = refreshIndex, personal = personal,
		cutoff = function(): number? return if manifest then manifest.cutoff else nil end,
	}
end

return RankSnapshots

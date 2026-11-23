--!strict
local function isCount(value: any): boolean
	return type(value) == "number" and value >= 0 and value < math.huge and value % 1 == 0
end

local function check(value: any)
	if type(value) ~= "table" or value.schemaVersion ~= 1 then
		return false, value
	end
	return isCount(value.gold) and isCount(value.exp) and isCount(value.bestScore), value
end

return {
	storeName = "KeyboardWarrior_Player_v1",
	studioScope = "studio",
	liveScope = "live",
	keyPrefix = "KW_Player_",
	default = { schemaVersion = 1, gold = 0, exp = 0, bestScore = 0 },
	check = check,
	migrations = {},
}

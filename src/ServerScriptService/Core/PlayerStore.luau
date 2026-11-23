--!strict
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local config = require(script.Parent.DataConfig)
local DocumentService = require(script.Parent.DocumentService)

local scope = if RunService:IsStudio() then config.studioScope else config.liveScope
local store = DocumentService.DocumentStore.new({
	dataStore = DataStoreService:GetDataStore(config.storeName, scope),
	default = config.default,
	check = config.check,
	migrations = config.migrations,
	lockSessions = true,
	bindToClose = true,
})

local PlayerStore = {}
function PlayerStore.getDocument(userId: number)
	local document = store:GetDocument(config.keyPrefix .. tostring(userId))
	return document
end

return PlayerStore

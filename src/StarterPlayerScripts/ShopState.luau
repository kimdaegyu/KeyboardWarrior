--!strict
-- Server-confirmed gold, ownership, and equipped slots for this client.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type Item = {
	id: string,
	category: string,
	price: number,
	release: string,
	color: string,
	preset: string,
	currency: string,
	score: number?,
	owned: boolean,
}

local ShopState = {}

local status = "loading"
local reason = "ok"
local level: number? = nil
local gold = 0
local body = ""
local rim = ""
local effect = ""
local items: {Item} = {}
local received = false
local pending = false
local started = false
local requestRemote: RemoteEvent? = nil
local listeners: {() -> ()} = {}

local function fire()
	for _, listener in table.clone(listeners) do
		listener()
	end
end

function ShopState.status(): string
	return status
end

function ShopState.reason(): string
	return reason
end

function ShopState.level(): number?
	return level
end

function ShopState.gold(): number
	return gold
end

function ShopState.body(): string
	return body
end

function ShopState.rim(): string
	return rim
end

function ShopState.effect(): string
	return effect
end

function ShopState.items(): {Item}
	return items
end

function ShopState.received(): boolean
	return received
end

function ShopState.pending(): boolean
	return pending
end

function ShopState.onChanged(listener: () -> ()): () -> ()
	table.insert(listeners, listener)
	return function()
		local index = table.find(listeners, listener)
		if index ~= nil then
			table.remove(listeners, index)
		end
	end
end

function ShopState.request()
	local remote = requestRemote
	if remote ~= nil then
		remote:FireServer("sync")
	end
end

local function send(action: string, itemId: string)
	local remote = requestRemote
	if remote == nil or pending or itemId == "" then
		return
	end
	pending = true
	fire()
	remote:FireServer(action, itemId)
end

function ShopState.buy(itemId: string)
	send("buy", itemId)
end

function ShopState.equip(itemId: string)
	send("equip", itemId)
end

local function onState(message: any)
	if type(message) ~= "table" or type(message.status) ~= "string" or type(message.items) ~= "table" then
		return
	end
	local nextItems: {Item} = {}
	for _, row in message.items do
		if type(row) == "table" and type(row.id) == "string" and type(row.category) == "string" and type(row.price) == "number" and type(row.color) == "string" then
			table.insert(nextItems, {
				id = row.id,
				category = row.category,
				price = row.price,
				release = if type(row.release) == "string" then row.release else "",
				color = row.color,
				preset = if type(row.preset) == "string" then row.preset else "",
				currency = if type(row.currency) == "string" then row.currency else "Gold",
				score = if type(row.score) == "number" then row.score else nil,
				owned = row.owned == true,
			})
		end
	end
	received = true
	status = message.status
	reason = if type(message.reason) == "string" then message.reason else "ok"
	level = if type(message.level) == "number" then message.level else nil
	gold = if type(message.gold) == "number" then message.gold else 0
	body = if type(message.body) == "string" then message.body else ""
	rim = if type(message.rim) == "string" then message.rim else ""
	effect = if type(message.effect) == "string" then message.effect else ""
	items = nextItems
	if reason ~= "ok" then
		pending = false
	end
	fire()
end

function ShopState.start()
	if started then
		return
	end
	started = true
	requestRemote = ReplicatedStorage:WaitForChild("ShopRequest") :: RemoteEvent
	local state = ReplicatedStorage:WaitForChild("ShopState") :: RemoteEvent
	state.OnClientEvent:Connect(onState)
end

return ShopState

--!strict
-- Tells gameplay input that the first-join loading cover is holding the keyboard, touch, and buttons.
-- Unlocking clears only this flag. It does not reset another screen's input state.

local LoadingInputLock = {}

type Listener = (boolean) -> ()

local locked = false
local listeners: { Listener } = {}

function LoadingInputLock.isLocked(): boolean
	return locked
end

function LoadingInputLock.setLocked(value: boolean)
	if locked == value then
		return
	end
	locked = value
	for _, listener in table.clone(listeners) do
		task.spawn(listener, value)
	end
end

function LoadingInputLock.onChanged(listener: Listener): () -> ()
	table.insert(listeners, listener)
	return function()
		local index = table.find(listeners, listener)
		if index ~= nil then
			table.remove(listeners, index)
		end
	end
end

return LoadingInputLock

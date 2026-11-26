--!strict
local Players = game:GetService("Players")
local config = require(game:GetService("ReplicatedStorage").Shared.IngameConstants).FriendBoost

local FriendBoostService = {}
local friends: {[Player]: {[Player]: boolean}} = {}
local started = false

local function publish(player: Player)
	local count = 0
	for _, connected in friends[player] do
		if connected then count += 1 end
	end
	player:SetAttribute("FriendBoostPercent", math.min(count, config.MaxFriends) * config.PercentPerFriend)
end

local function added(player: Player)
	if friends[player] then return end
	friends[player] = {}
	publish(player)
	for peer in friends do
		if peer == player or player.UserId <= 0 or peer.UserId <= 0 then continue end
		-- A single lookup serves both players. Discard in-flight results after a departure.
		task.spawn(function()
			while friends[player] and friends[peer] do
				local ok, connected = pcall(function() return player:IsFriendsWithAsync(peer.UserId) end)
				if not friends[player] or not friends[peer] then return end
				if ok then
					if friends[player][peer] ~= connected then
						friends[player][peer] = connected
						friends[peer][player] = connected
						publish(player)
						publish(peer)
					end
				end
				task.wait(if ok then 300 else 30)
			end
		end)
	end
end

function FriendBoostService.start()
	if started then return end
	started = true
	Players.PlayerAdded:Connect(added)
	Players.PlayerRemoving:Connect(function(player)
		friends[player] = nil
		for peer, connections in friends do
			local wasFriend = connections[player]
			connections[player] = nil
			if wasFriend then publish(peer) end
		end
	end)
	for _, player in Players:GetPlayers() do added(player) end
end

return FriendBoostService

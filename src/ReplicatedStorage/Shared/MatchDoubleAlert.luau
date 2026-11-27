--!strict
-- When the official-match multiplier appears. The decision uses the server
-- remaining time, not the rounded clock on the HUD.

local MatchDoubleAlert = {}

export type Role = "player" | "spectator" | "practice"

function MatchDoubleAlert.observe(heardMatch: number, matchId: number, role: Role, remain: number, doubleSeconds: number): (boolean, boolean, number)
	local show = role == "player" and matchId > 0 and remain > 0 and remain <= doubleSeconds
	local play = show and heardMatch ~= matchId
	return show, play, if play then matchId else heardMatch
end

function MatchDoubleAlert.selfCheck()
	local seconds = 30
	local function run(steps: {{any}}): {boolean}
		local heard = 0
		local played: {boolean} = {}
		for _, step in steps do
			local show, play, nextHeard = MatchDoubleAlert.observe(heard, step.matchId, step.role, step.remain, seconds)
			heard = nextHeard
			table.insert(played, play)
			if step.show ~= nil then
				assert(show == step.show, "double mark visibility")
			end
		end
		return played
	end

	local boundary = run({
		{ matchId = 4, role = "player", remain = 30.001, show = false },
		{ matchId = 4, role = "player", remain = 30, show = true },
		{ matchId = 4, role = "player", remain = 29, show = true },
		{ matchId = 4, role = "player", remain = 0, show = false },
		{ matchId = 5, role = "player", remain = 30, show = true },
	})
	assert(boundary[1] == false and boundary[2] == true and boundary[3] == false and boundary[4] == false and boundary[5] == true, "30.001, 30, 29, 0, then the next match play once each")

	local skipped = run({
		{ matchId = 7, role = "player", remain = 31, show = false },
		{ matchId = 7, role = "player", remain = 29, show = true },
		{ matchId = 7, role = "player", remain = 29, show = true },
	})
	assert(skipped[1] == false and skipped[2] == true and skipped[3] == false, "skipping from 31 to 29 still plays once")

	local watching = run({
		{ matchId = 7, role = "spectator", remain = 30, show = false },
		{ matchId = 7, role = "spectator", remain = 29, show = false },
		{ matchId = 7, role = "practice", remain = 30, show = false },
	})
	assert(watching[1] == false and watching[2] == false and watching[3] == false, "spectators and practice never play the double cue")
end

return MatchDoubleAlert

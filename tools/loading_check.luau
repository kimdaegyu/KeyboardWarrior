-- First-join loading decisions. No Roblox services.
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local policy = luau.load(fs.readFile("src/ReplicatedStorage/Shared/LoadingPolicy.luau"))()

local function eq(actual, expected, label)
	assert(actual == expected, label .. " got " .. tostring(actual))
end

eq(policy.profileOutcome(true, "ready"), "ready", "new player default profile")
eq(policy.profileOutcome(true, "saved"), "ready", "saved profile is still ready")
eq(policy.profileOutcome(false, "unavailable"), "failed", "read failure")
eq(policy.profileOutcome(false, "loading"), "pending", "still opening")
eq(policy.tutorialAction(true, true, false, "ready"), "hold", "cover blocks the tutorial")
eq(policy.tutorialAction(false, true, false, "ready"), "tutorial", "first join opens the tutorial")
eq(policy.tutorialAction(false, true, true, "ready"), "lobby", "seen player stays on the lobby")
eq(policy.tutorialAction(false, false, false, "unavailable"), "lobby", "read failure is not a new player")
eq(policy.isCurrent(2, 1), false, "stale attempt")
eq(policy.isCurrent(2, 2), true, "current attempt")
eq(policy.imageUrl(""), "", "empty image id")
eq(policy.imageUrl("123"), "rbxassetid://123", "numeric image id")
eq(policy.imageUrl("rbxassetid://9"), "rbxassetid://9", "full image url")
eq(policy.artMode("", "Success", true), "fallback", "empty art")
eq(policy.artMode("rbxassetid://1", "Failure", false), "fallback", "failed art")
eq(policy.artMode("rbxassetid://1", nil, false), "fallback", "timed out art")
eq(policy.artMode("rbxassetid://1", nil, true), "image", "visible art")
eq(policy.decorativeWait(false, 1, 4), "wait", "decorative still in time")
eq(policy.decorativeWait(true, 0.2, 4), "done", "decorative finished")
eq(policy.decorativeWait(false, 4, 4), "fallback", "decorative cap")

local urls = policy.collectPreload({ "", "rbxassetid://1", "rbxassetid://1", "rbxassetid://2" }, { "rbxassetid://2" })
assert(#urls == 1 and urls[1] == "rbxassetid://1", "shop and duplicate urls stay out of preload")

print("PASS loading policy")

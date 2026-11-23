--!strict
local rules = require("../src/ReplicatedStorage/Shared/MatchRules")
local constants = require("../src/ReplicatedStorage/Shared/IngameConstants")
rules.selfCheck(constants)
print("PASS m1 match rules")

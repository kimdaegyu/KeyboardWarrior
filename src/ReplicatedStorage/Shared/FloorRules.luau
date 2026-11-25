--!strict
-- Cumulative floors earned from a match score. No instances.

local constants = if script then require(script.Parent.IngameConstants) else require("./IngameConstants")

local FloorRules = {}

function FloorRules.floorsFor(score: number, perFloor: number?): number
	local step = if perFloor ~= nil then perFloor else constants.Floor.ScorePerFloor
	if step <= 0 or score <= 0 then
		return 0
	end
	return math.floor(score / step)
end

function FloorRules.acquired(previousScore: number, currentScore: number, perFloor: number?): number
	local step = if perFloor ~= nil then perFloor else constants.Floor.ScorePerFloor
	local previous = if previousScore > 0 then previousScore else 0
	local current = if currentScore > 0 then currentScore else 0
	return math.max(0, FloorRules.floorsFor(current, step) - FloorRules.floorsFor(previous, step))
end

function FloorRules.standOffset(character: Model, root: BasePart): number
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local offset = root.Size.Y / 2
	if humanoid == nil then return offset + 2 end
	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		local leg = character:FindFirstChild("Left Leg")
		offset += if leg and leg:IsA("BasePart") then leg.Size.Y else 2
	end
	return offset + humanoid.HipHeight
end

function FloorRules.quadOut(alpha: number): number
	local t = math.clamp(alpha, 0, 1)
	return 1 - (1 - t) * (1 - t)
end

function FloorRules.selfCheck()
	local floor = constants.Floor
	assert(floor.ScorePerFloor == 5, "five points earn one floor")
	assert(floor.FloorHeight == 1 and floor.FloorAnimationDuration == 0.2 and floor.CharacterRiseDuration == 0)
	assert(floor.CharacterRiseDuration < floor.FloorAnimationDuration, "the character is already at the next height while the floor step continues")
	assert(floor.FloorStartScale == 0.1 and floor.FloorEndScale == 1 and floor.RimRotationSpeed == 45)
	assert(FloorRules.acquired(0, 4) == 0, "four points do not earn a floor")
	assert(FloorRules.acquired(4, 5) == 1, "reaching five earns one floor")
	assert(FloorRules.acquired(5, 10) == 1, "the next five earn one floor")
	assert(FloorRules.acquired(0, 25) == 5, "twenty five points earn five floors")
	assert(FloorRules.acquired(3, 28) == 5, "the remainder is kept in the cumulative score")
	assert(FloorRules.acquired(28, 30) == 1, "two more points finish the next floor")
	assert(FloorRules.acquired(0, 25) * floor.FloorAnimationDuration == 1, "five floors take one second")
	assert(10 * floor.FloorHeight == 10, "ten floors raise the player ten studs")
	assert(FloorRules.quadOut(0) == 0 and FloorRules.quadOut(1) == 1)
end

return FloorRules

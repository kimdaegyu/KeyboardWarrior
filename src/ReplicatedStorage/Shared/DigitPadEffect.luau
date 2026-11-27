--!strict
-- Shared golden-digit rim effect. Upload assets/pad-effects/digits/digits_atlas.png
-- once and put that image id in ImageId. digit_1.png through digit_9.png stay as source art.

local DigitPadEffect = {}

DigitPadEffect.Id = "digits"
DigitPadEffect.Rate = 10
DigitPadEffect.Lifetime = 0.85
DigitPadEffect.Rise = 2.2
DigitPadEffect.PointCount = 3
DigitPadEffect.Count = 9
DigitPadEffect.Cell = 64
DigitPadEffect.ImageId = 120272152223283

function DigitPadEffect.image(): string
	if type(DigitPadEffect.ImageId) ~= "number" or DigitPadEffect.ImageId <= 0 then
		return ""
	end
	return "rbxassetid://" .. tostring(math.floor(DigitPadEffect.ImageId))
end

function DigitPadEffect.interval(): number
	return 1 / DigitPadEffect.Rate
end

function DigitPadEffect.pendingFiles(): {string}
	if DigitPadEffect.image() == "" then
		return { "assets/pad-effects/digits/digits_atlas.png" }
	end
	return {}
end

function DigitPadEffect.cellOrigin(n: number): (number, number)
	return ((n - 1) % 4) * 64, math.floor((n - 1) / 4) * 64
end

function DigitPadEffect.cell(n: number): (Vector2, Vector2)
	local x, y = DigitPadEffect.cellOrigin(n)
	return Vector2.new(x, y), Vector2.new(64, 64)
end

function DigitPadEffect.pointYZ(pointIndex: number): (number, number)
	local angle = (pointIndex - 1) * (2 * math.pi / DigitPadEffect.PointCount)
	return math.cos(angle), math.sin(angle)
end

function DigitPadEffect.localPoint(rimSize: Vector3, pointIndex: number): Vector3
	local y, z = DigitPadEffect.pointYZ(pointIndex)
	return Vector3.new(0, y * rimSize.Y * 0.5, z * rimSize.Z * 0.5)
end

function DigitPadEffect.project(worldPoint: Vector3, camera: CFrame, fieldOfView: number, viewport: Vector2): Vector2?
	if viewport.X < 1 or viewport.Y < 1 then
		return nil
	end
	local localPoint = camera:PointToObjectSpace(worldPoint)
	local ndcX, ndcY = DigitPadEffect.projectNdc(localPoint.X, localPoint.Y, localPoint.Z, fieldOfView, viewport.X / viewport.Y)
	if ndcX == nil or ndcY == nil then
		return nil
	end
	return Vector2.new((ndcX + 1) * 0.5 * viewport.X, (1 - ndcY) * 0.5 * viewport.Y)
end

function DigitPadEffect.projectNdc(x: number, y: number, z: number, fieldOfView: number, aspect: number): (number?, number?)
	local depth = -z
	if depth <= 0.05 or aspect <= 0 then
		return nil, nil
	end
	local tanHalf = math.tan(math.rad(fieldOfView) * 0.5)
	if tanHalf <= 0 then
		return nil, nil
	end
	return x / (depth * tanHalf * aspect), y / (depth * tanHalf)
end

function DigitPadEffect.selfCheck()
	assert(DigitPadEffect.Count == 9 and DigitPadEffect.Rate == 10 and DigitPadEffect.interval() * DigitPadEffect.Rate == 1 and DigitPadEffect.Lifetime == 0.85 and DigitPadEffect.Cell == 64, "digits share one rate, lifetime, and cell size")
	local pending = DigitPadEffect.pendingFiles()
	assert((DigitPadEffect.ImageId > 0 and #pending == 0) or pending[1] == "assets/pad-effects/digits/digits_atlas.png", "the atlas id is the only upload")
	local function origin(n: number): (number, number)
		return DigitPadEffect.cellOrigin(n)
	end
	local firstX, firstY = origin(1)
	local fourthX, fourthY = origin(4)
	local fifthX, fifthY = origin(5)
	local ninthX, ninthY = origin(9)
	assert(firstX == 0 and firstY == 0, "digit 1 is the top-left cell")
	assert(fourthX == 192 and fourthY == 0, "digit 4 is the end of the first row")
	assert(fifthX == 0 and fifthY == 64, "digit 5 starts the second row")
	assert(ninthX == 0 and ninthY == 128, "digit 9 starts the third row")
	local firstPointY, firstPointZ = DigitPadEffect.pointYZ(1)
	local secondPointY, secondPointZ = DigitPadEffect.pointYZ(2)
	local thirdPointY, thirdPointZ = DigitPadEffect.pointYZ(3)
	assert(math.abs(firstPointY - 1) < 1e-6 and math.abs(firstPointZ) < 1e-6, "the first launch point starts on the rim")
	local dot = firstPointY * secondPointY + firstPointZ * secondPointZ
	assert(math.abs(dot + 0.5) < 1e-4 and math.abs(secondPointY * thirdPointY + secondPointZ * thirdPointZ + 0.5) < 1e-4, "three launch points stay 120 degrees apart")
	local centerX, centerY = DigitPadEffect.projectNdc(0, 0, -10, 70, 2)
	assert(centerX ~= nil and centerY ~= nil and math.abs(centerX) < 1e-6 and math.abs(centerY) < 1e-6, "a point in front of the camera projects to the panel center")
	local behindX = DigitPadEffect.projectNdc(0, 0, 2, 70, 1)
	assert(behindX == nil, "a point behind the camera is not drawn")
end

return DigitPadEffect

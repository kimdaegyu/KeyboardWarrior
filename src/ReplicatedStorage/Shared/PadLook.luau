--!strict
-- Paints one pad from shop style tokens. The rim and effect never become the collision body.

export type Paint = {
	body: string,
	rim: string,
	effect: string,
}

local PadLook = {}

local STARTER_BODY = Color3.fromRGB(126, 84, 255)

function PadLook.parseColor(token: string): Color3?
	local red, green, blue = string.match(token, "^(%d+);(%d+);(%d+)$")
	if red == nil or green == nil or blue == nil then
		return nil
	end
	local r = tonumber(red)
	local g = tonumber(green)
	local b = tonumber(blue)
	if r == nil or g == nil or b == nil or r > 255 or g > 255 or b > 255 then
		return nil
	end
	return Color3.fromRGB(r, g, b)
end

function PadLook.forStack(paint: Paint): (Color3, Color3?, boolean, Color3?)
	local body = PadLook.parseColor(paint.body) or STARTER_BODY
	local rim = if paint.rim == "none" or paint.rim == "" then nil else PadLook.parseColor(paint.rim)
	local effect = if paint.effect == "none" or paint.effect == "" then nil else PadLook.parseColor(paint.effect)
	return body, rim, effect ~= nil, effect
end

function PadLook.starter(): Paint
	return {
		body = "126;84;255",
		rim = "none",
		effect = "none",
	}
end

local function clearNamed(pad: BasePart, name: string)
	local child = pad:FindFirstChild(name)
	if child ~= nil then
		child:Destroy()
	end
end

function PadLook.apply(pad: BasePart, paint: Paint)
	local body, rimColor, effectOn, effectColor = PadLook.forStack(paint)
	pad.Color = body
	pad.Material = Enum.Material.Asphalt
	clearNamed(pad, "PadRim")
	clearNamed(pad, "PadEffect")
	clearNamed(pad, "Spark")
	if rimColor ~= nil then
		local rim = Instance.new("Part")
		rim.Name = "PadRim"
		rim.Shape = Enum.PartType.Cylinder
		rim.Anchored = true
		rim.CanCollide = false
		rim.CanTouch = false
		rim.CanQuery = false
		rim.Material = Enum.Material.Neon
		rim.Color = rimColor
		rim.Size = Vector3.new(pad.Size.X + 0.3, pad.Size.Y + 1.6, pad.Size.Z + 1.6)
		rim.CFrame = pad.CFrame
		rim.Parent = pad
	end
	if effectOn and effectColor ~= nil then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "Spark"
		emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		emitter.Rate = 8
		emitter.Lifetime = NumberRange.new(0.5, 1)
		emitter.Speed = NumberRange.new(0.4, 1.4)
		emitter.LightEmission = 1
		emitter.Color = ColorSequence.new(effectColor)
		emitter.Size = NumberSequence.new(0.35)
		emitter.Parent = pad
		local folder = Instance.new("Folder")
		folder.Name = "PadEffect"
		folder.Parent = pad
		local up = pad.CFrame.XVector
		for index = 1, 3 do
			local mote = Instance.new("Part")
			mote.Name = "Mote"
			mote.Shape = Enum.PartType.Ball
			mote.Anchored = true
			mote.CanCollide = false
			mote.CanTouch = false
			mote.CanQuery = false
			mote.Material = Enum.Material.Neon
			mote.Color = effectColor
			mote.Size = Vector3.new(0.7, 0.7, 0.7)
			mote.CFrame = pad.CFrame + up * (1.1 + index * 0.65) + pad.CFrame.ZVector * ((index - 2) * 1.1)
			mote.Parent = folder
		end
	end
end

return PadLook

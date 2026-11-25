--!strict
-- Paints one pad from shop style tokens. The rim and effect never become the collision body.

export type Paint = {
	body: string,
	rim: string,
	effect: string,
}

local PadLook = {}

local BODY = {
	purple = Color3.fromRGB(126, 84, 255),
	cyan = Color3.fromRGB(70, 220, 255),
}
local RIM = {
	gold = Color3.fromRGB(255, 196, 64),
}
local SPARK = Color3.fromRGB(90, 230, 255)

function PadLook.forStack(paint: Paint): (Color3, Color3?, boolean)
	local body = BODY[paint.body] or BODY.purple
	local rim = RIM[paint.rim]
	local effect = paint.effect ~= nil and paint.effect ~= "" and paint.effect ~= "none"
	return body, rim, effect
end

function PadLook.starter(): Paint
	return {
		body = "purple",
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
	local body = BODY[paint.body] or BODY.purple
	pad.Color = body
	pad.Material = Enum.Material.Asphalt
	clearNamed(pad, "PadRim")
	clearNamed(pad, "PadEffect")
	clearNamed(pad, "Spark")
	if paint.rim == "gold" then
		local rim = Instance.new("Part")
		rim.Name = "PadRim"
		rim.Shape = Enum.PartType.Cylinder
		rim.Anchored = true
		rim.CanCollide = false
		rim.CanTouch = false
		rim.CanQuery = false
		rim.Material = Enum.Material.Neon
		rim.Color = RIM.gold
		rim.Size = Vector3.new(pad.Size.X + 0.3, pad.Size.Y + 1.6, pad.Size.Z + 1.6)
		rim.CFrame = pad.CFrame
		rim.Parent = pad
	end
	if paint.effect == "spark" then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "Spark"
		emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		emitter.Rate = 8
		emitter.Lifetime = NumberRange.new(0.5, 1)
		emitter.Speed = NumberRange.new(0.4, 1.4)
		emitter.LightEmission = 1
		emitter.Color = ColorSequence.new(SPARK)
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
			mote.Color = SPARK
			mote.Size = Vector3.new(0.7, 0.7, 0.7)
			mote.CFrame = pad.CFrame + up * (1.1 + index * 0.65) + pad.CFrame.ZVector * ((index - 2) * 1.1)
			mote.Parent = folder
		end
	end
end

return PadLook

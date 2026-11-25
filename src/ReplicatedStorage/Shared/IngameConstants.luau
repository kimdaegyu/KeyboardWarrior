--!strict
local maxParticipants = 12
local padDiameter = 12
local padGap = 4

return table.freeze({
	Match = table.freeze({
		MinParticipants = 1,
		MaxParticipants = maxParticipants,
		PlaySeconds = 120,
		ResultSeconds = 30,
		RestSeconds = 30,
		DoubleScoreSeconds = 30,
		EndScoreMultiplier = 2,
	}),
	Arena = table.freeze({
		Diameter = 100,
		PadDiameter = padDiameter,
		PadGap = padGap,
		-- Adjacent centres are one pad diameter plus the edge-to-edge gap apart.
		PadCenterRadius = (padDiameter + padGap) / (2 * math.sin(math.pi / maxParticipants)),
	}),
	Floor = table.freeze({
		ScorePerFloor = 5,
		FloorHeight = 1,
		FloorAnimationDuration = 0.2,
		CharacterRiseDuration = 0,
		FloorStartScale = 0.1,
		FloorEndScale = 1,
		RimRotationSpeed = 45,
	}),
	Rank = table.freeze({
		TopCount = 50,
		CacheSeconds = 60,
	}),
	-- Initial layout targets in Roblox UI pixels. Measure the safe root, not the device.
	UI = table.freeze({
		CompactHeight = 430,
		CompactWidth = 760,
		MaxContentWidth = 1440,
		TouchTarget = 44,
		CompactTouchTarget = 36,
	}),
})

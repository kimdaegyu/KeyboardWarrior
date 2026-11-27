--!strict
-- Tutorial figures keyed by TutorialDataSheet Id.
-- A zero means the PNG is not uploaded yet. Leave it blank. Do not invent an id.

local TutorialImages = {}

local ASSET_IDS: {[string]: number} = {
	join = 77782565087332, -- assets/tutorial/tutorial1.png
	typing = 108012452908864, -- assets/tutorial/tutorial2.png
	practice = 124250494533323, -- assets/tutorial/tutorial3.png
	shop = 107432146485035, -- assets/tutorial/tutorial4.png
}

function TutorialImages.image(stepId: string): string
	local assetId = ASSET_IDS[stepId]
	if type(assetId) ~= "number" or assetId <= 0 or assetId % 1 ~= 0 then
		return ""
	end
	return "rbxassetid://" .. tostring(assetId)
end

function TutorialImages.pending(): {string}
	local missing = {}
	for stepId, assetId in ASSET_IDS do
		if type(assetId) ~= "number" or assetId <= 0 then
			table.insert(missing, stepId)
		end
	end
	table.sort(missing)
	return missing
end

function TutorialImages.selfCheck()
	for _, stepId in { "join", "typing", "practice", "shop" } do
		local image = TutorialImages.image(stepId)
		assert(image == "" or string.match(image, "^rbxassetid://%d+$") ~= nil, "a tutorial figure uses an uploaded id or stays blank")
		assert(string.find(image, ".png", 1, true) == nil, "a local file name is not an image")
	end
	assert(TutorialImages.image("missing") == "", "an unknown step has no image")
end

return TutorialImages

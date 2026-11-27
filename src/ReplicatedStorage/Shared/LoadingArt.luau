--!strict
-- Loading background and transparent title. These two IDs are not part of an atlas.
-- Register the uploaded Roblox image asset IDs here:
--   BackgroundImage — full-screen loading background
--   TitleImage — transparent "Typing GOD" title
-- Leave either value "" until that asset is uploaded. The screen still runs.

local LoadingPolicy = require(script.Parent.LoadingPolicy)

local LoadingArt = {
	BackgroundImage = "99875663765859",
	TitleImage = "100485779226115",
}

function LoadingArt.backgroundUrl(): string
	return LoadingPolicy.imageUrl(LoadingArt.BackgroundImage)
end

function LoadingArt.titleUrl(): string
	return LoadingPolicy.imageUrl(LoadingArt.TitleImage)
end

return LoadingArt

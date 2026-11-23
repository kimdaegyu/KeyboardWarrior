--!strict
-- High-resolution companion to ItemIconUtil. Also accepts item IDs 10042..10049.
local Layout = require(script.Parent:WaitForChild("UIImageAtlasData"))
local AssetIds = require(script.Parent:WaitForChild("UIImageAssetIds")) :: { [string]: number }
type Entry = { Atlas: string, Offset: Vector2, Size: Vector2, SliceCenter: Rect? }
local Entries = Layout :: { [string]: Entry }
local UIImageUtil = {}
type ImageGui = ImageLabel | ImageButton

function UIImageUtil.get(key: string | number)
    local entry = Entries[tostring(key)]
    if entry == nil then return nil end
    local assetId = AssetIds[entry.Atlas] or 0
    return {
        Image = if assetId > 0 then `rbxassetid://{assetId}` else "",
        ImageRectOffset = entry.Offset,
        ImageRectSize = entry.Size,
        SliceCenter = entry.SliceCenter,
        HasAtlas = assetId > 0,
    }
end

function UIImageUtil.clear(image: ImageGui)
    image.Image = ""
    image.ImageRectOffset = Vector2.zero
    image.ImageRectSize = Vector2.zero
    image.ScaleType = Enum.ScaleType.Fit
    image.SliceCenter = Rect.new(0, 0, 0, 0)
    image.SliceScale = 1
end

function UIImageUtil.apply(image: ImageGui, key: string | number): boolean
    local info = UIImageUtil.get(key)
    if info == nil or not info.HasAtlas then
        UIImageUtil.clear(image)
        return false
    end
    image.Image = info.Image
    image.ImageRectOffset = info.ImageRectOffset
    image.ImageRectSize = info.ImageRectSize
    image.ImageColor3 = Color3.new(1, 1, 1)
    image.SliceScale = 1
    if info.SliceCenter then
        image.ScaleType = Enum.ScaleType.Slice
        image.SliceCenter = info.SliceCenter
    else
        image.ScaleType = Enum.ScaleType.Fit
        image.SliceCenter = Rect.new(0, 0, 0, 0)
    end
    return true
end

function UIImageUtil.setAtlasImageId(atlasName: string, assetId: number)
    assert(AssetIds[atlasName] ~= nil, "Unknown UI atlas")
    assert(assetId >= 0 and assetId % 1 == 0, "Expected nonnegative integer asset ID")
    AssetIds[atlasName] = assetId
end

return UIImageUtil

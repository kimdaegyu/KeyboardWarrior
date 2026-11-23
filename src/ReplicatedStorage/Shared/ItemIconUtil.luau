--!strict
--[[
	ItemIconUtil
	역할: ItemDataSheet.Id 로 1024x1024 아이콘 아틀라스에서 셀을 조회합니다.
	      셀은 64x64, 테두리 2px 패딩, 한 장에 16x16(256) 슬롯입니다.
	      슬롯은 정렬된 ItemDataSheet.Id 순서(0부터)로 자동 배정됩니다.

	사용 예:
	  local info = ItemIconUtil.get(1)
	  ItemIconUtil.apply(imageLabel, 1)
]]

local layout = require(script.Parent.ItemIconSlots)
local ATLAS_IMAGE_IDS = require(script.Parent.ItemIconPages)
local CELL_SIZE = layout.CellSize
local PADDING = layout.Padding
local GRID = layout.Grid
local ATLAS_SIZE = GRID * CELL_SIZE
local SLOTS_PER_ATLAS = GRID * GRID
local CONTENT_SIZE = CELL_SIZE - PADDING * 2

export type IconInfo = {
	Image: string,
	ImageRectOffset: Vector2,
	ImageRectSize: Vector2,
	AtlasIndex: number,
	SlotIndex: number,
	HasAtlas: boolean,
}

export type AtlasLayout = {
	CellSize: number,
	Padding: number,
	Grid: number,
	AtlasSize: number,
	SlotsPerAtlas: number,
	ContentSize: number,
}

type ImageGui = ImageLabel | ImageButton

local function setImageGui(
	image: ImageGui,
	imageUrl: string,
	rectOffset: Vector2,
	rectSize: Vector2,
	imageColor3: Color3?
)
	local gui = image :: ImageLabel
	gui.Image = imageUrl
	gui.ImageRectOffset = rectOffset
	gui.ImageRectSize = rectSize
	if imageColor3 ~= nil then
		gui.ImageColor3 = imageColor3
	end
end

local ItemIconUtil = {}

ItemIconUtil.CellSize = CELL_SIZE
ItemIconUtil.Padding = PADDING
ItemIconUtil.Grid = GRID
ItemIconUtil.AtlasSize = ATLAS_SIZE
ItemIconUtil.SlotsPerAtlas = SLOTS_PER_ATLAS
ItemIconUtil.ContentSize = CONTENT_SIZE

local slotByItemId = layout.Slots

local function toAssetUrl(assetId: number): string
	return `rbxassetid://{assetId}`
end

function ItemIconUtil.getLayout(): AtlasLayout
	return {
		CellSize = CELL_SIZE,
		Padding = PADDING,
		Grid = GRID,
		AtlasSize = ATLAS_SIZE,
		SlotsPerAtlas = SLOTS_PER_ATLAS,
		ContentSize = CONTENT_SIZE,
	}
end

function ItemIconUtil.getSlotIndex(itemId: number): number?
	return slotByItemId[itemId]
end

function ItemIconUtil.getAtlasCell(slotIndex: number): (number, number, number)
	local atlasIndex = math.floor(slotIndex / SLOTS_PER_ATLAS) + 1
	local localSlot = slotIndex % SLOTS_PER_ATLAS
	local column = localSlot % GRID
	local row = math.floor(localSlot / GRID)
	return atlasIndex, column, row
end

function ItemIconUtil.get(itemId: number): IconInfo?
	local slotIndex = slotByItemId[itemId]
	if slotIndex == nil then
		return nil
	end

	local atlasIndex, column, row = ItemIconUtil.getAtlasCell(slotIndex)
	local atlasAssetId = ATLAS_IMAGE_IDS[atlasIndex]
	local hasAtlas = typeof(atlasAssetId) == "number" and atlasAssetId > 0

	return {
		Image = if hasAtlas then toAssetUrl(atlasAssetId) else "",
		ImageRectOffset = Vector2.new(column * CELL_SIZE, row * CELL_SIZE),
		ImageRectSize = Vector2.new(CELL_SIZE, CELL_SIZE),
		AtlasIndex = atlasIndex,
		SlotIndex = slotIndex,
		HasAtlas = hasAtlas,
	}
end

function ItemIconUtil.clear(image: ImageGui)
	setImageGui(image, "", Vector2.zero, Vector2.zero, nil)
end

function ItemIconUtil.apply(image: ImageGui, itemId: number?): boolean
	if itemId == nil then
		ItemIconUtil.clear(image)
		return false
	end

	local info = ItemIconUtil.get(itemId)
	if info == nil or not info.HasAtlas then
		ItemIconUtil.clear(image)
		return false
	end

	setImageGui(image, info.Image, info.ImageRectOffset, info.ImageRectSize, Color3.new(1, 1, 1))
	return true
end

function ItemIconUtil.getAtlasAssetIds(): { number }
	local indexes: { number } = {}
	for index, assetId in ATLAS_IMAGE_IDS do
		if typeof(assetId) == "number" and assetId > 0 then
			table.insert(indexes, index)
		end
	end
	table.sort(indexes)
	local assetIds: { number } = {}
	for _, index in indexes do
		table.insert(assetIds, ATLAS_IMAGE_IDS[index])
	end
	return assetIds
end

function ItemIconUtil.setAtlasImageId(atlasIndex: number, assetId: number)
	ATLAS_IMAGE_IDS[atlasIndex] = assetId
end

return ItemIconUtil

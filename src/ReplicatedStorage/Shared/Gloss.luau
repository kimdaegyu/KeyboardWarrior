--!strict
-- Meaning text for one question id. The visible prompt is not used as a lookup key.

export type Row = {
	Id: string,
	ko: string?,
	en: string?,
}

local Gloss = {}

function Gloss.textFor(rows: {Row}, questionId: string, column: string): string?
	if questionId == "" or column == "" then
		return nil
	end
	for _, row in rows do
		if row.Id == questionId then
			local text = (row :: any)[column]
			if type(text) == "string" and text ~= "" then
				return text
			end
			return nil
		end
	end
	return nil
end

function Gloss.selfCheck(rows: {Row})
	assert(Gloss.textFor(rows, "", "ko") == nil, "an empty id has no meaning")
	assert(Gloss.textFor(rows, "missing-question", "ko") == nil, "an unknown id has no meaning")
	local sampleId: string? = nil
	local sampleText: string? = nil
	for _, row in rows do
		if row.Id ~= "" and type(row.ko) == "string" and row.ko ~= "" then
			sampleId = row.Id
			sampleText = row.ko
			break
		end
	end
	if sampleId ~= nil and sampleText ~= nil then
		assert(Gloss.textFor(rows, sampleId, "ko") == sampleText, "the meaning comes from that id")
		if sampleText ~= sampleId then
			assert(Gloss.textFor(rows, sampleText, "ko") == nil, "the meaning text is not an id")
		end
	end
	local blank: {Row} = { { Id = "9", ko = "", en = "placeholder" } }
	assert(Gloss.textFor(blank, "9", "ko") == nil, "a blank translation collapses")
	assert(Gloss.textFor(blank, "placeholder", "ko") == nil, "the prompt text is not a lookup key")
end

return Gloss

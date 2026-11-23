--!strict
local fs = require("@lune/fs")
local QuestionRules = require("../src/ReplicatedStorage/Shared/QuestionRules")
local TypingLayout = require("../src/ReplicatedStorage/Shared/TypingLayout")

local function readSheet(path: string): {QuestionRules.SheetRow}
	local content = string.gsub(fs.readFile(path), "\r\n", "\n")
	local lines = string.split(content, "\n")
	local headers = string.split(lines[1], ",")
	local rows: {QuestionRules.SheetRow} = {}
	for index = 2, #lines do
		local line = lines[index]
		if line ~= "" then
			local values = string.split(line, ",")
			local row: QuestionRules.SheetRow = {
				Id = "",
				Enabled = "",
				en = "",
			}
			for column, header in ipairs(headers) do
				if header == "Id" or header == "Enabled" or header == "en" then
					row[header] = values[column] or ""
				end
			end
			table.insert(rows, row)
		end
	end
	return rows
end

local rows = readSheet("src/ReplicatedStorage/Shared/Table/QuestionDataSheet.txt")
local enabled = {}
for _, row in ipairs(rows) do
	if row.Enabled == "1" then
		table.insert(enabled, row.en)
	end
end
assert(enabled[1] == "apple" and enabled[2] == "star" and enabled[3] == "we play together", "sample deck")
assert(#enabled == 3, "sample deck count")
QuestionRules.selfCheck(rows)
TypingLayout.selfCheck()
print("PASS m2 question rules")

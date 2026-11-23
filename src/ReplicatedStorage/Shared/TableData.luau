--!strict
-- Read CSV records, keeping quoted commas, doubled quotes and embedded newlines.
local TableData = {}
type Row = { [string]: string }
local folder = script.Parent:WaitForChild("Table")

function TableData.rows(name: string): { Row }
	local source = folder:WaitForChild(name, 10)
	assert(source and source:IsA("StringValue"), "Missing table: " .. name .. " (run sync_tables.py)")
	local content = source.Value
	local result: { Row } = {}
	local headers: { string }? = nil
	local fields: { string } = {}
	local parts: { string } = {}
	local quoted = false
	local start = 1
	local function endField()
		table.insert(fields, table.concat(parts))
		table.clear(parts)
	end
	local function endRow()
		endField()
		if headers then
			local row: Row = {}
			for i, key in headers do
				row[key] = fields[i] or ""
			end
			table.insert(result, row)
		else
			headers = table.clone(fields)
		end
		table.clear(fields)
	end

	while start <= #content do
		local pos = string.find(content, '[,"\r\n]', start)
		if not pos then
			table.insert(parts, string.sub(content, start))
			break
		end
		table.insert(parts, string.sub(content, start, pos - 1))
		local char = string.sub(content, pos, pos)
		start = pos + 1
		if char == '"' then
			if quoted and string.sub(content, start, start) == '"' then
				table.insert(parts, '"')
				start += 1
			else
				quoted = not quoted
			end
		elseif quoted then
			table.insert(parts, char)
		elseif char == "," then
			endField()
		else
			endRow()
			if char == "\r" and string.sub(content, start, start) == "\n" then
				start += 1
			end
		end
	end
	if #parts > 0 or #fields > 0 then
		endRow()
	end
	return result
end

return TableData

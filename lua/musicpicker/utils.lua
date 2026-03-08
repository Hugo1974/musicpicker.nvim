local config = require("musicpicker.config")
local M = {}

function M.write_file(path, content)
	local f = io.open(path, "w")
	if f then
		f:write(tostring(content))
		f:close()
	end
end

function M.read_file(path)
	local f = io.open(path, "r")
	if not f then
		return ""
	end
	local content = f:read("*all"):gsub("[%s\r\n]+", "")
	f:close()
	return content
end

function M.get_playlist_lines()
	local lines = {}
	local path = config.options.m3u_file
	if vim.fn.filereadable(path) == 1 then
		for line in io.lines(path) do
			local clean = line:gsub("[\r\n]+$", "")
			if clean ~= "" and not clean:match("^#") then
				table.insert(lines, clean)
			end
		end
	end
	return lines
end

function M.get_mpv_title()
	local cmd = string.format(
		'echo \'{"command": ["get_property", "media-title"]}\' | socat - UNIX-CONNECT:%s 2>/dev/null',
		config.options.socket_path
	)
	local handle = io.popen(cmd)
	local result = handle:read("*a")
	handle:close()
	if result and result ~= "" then
		return result:match('"data"%s*:%s*"([^"]+)"')
	end
	return nil
end

return M

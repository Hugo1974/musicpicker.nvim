local M = {}
local config = require("musicpicker.config")

local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values

local listener_job = nil

-- === UTILIDADES INTEGRADAS ===

local function write_file(path, content)
	local f = io.open(path, "w")
	if f then
		f:write(tostring(content))
		f:close()
	end
end

local function read_file(path)
	local f = io.open(path, "r")
	if not f then
		return ""
	end
	local content = f:read("*all"):gsub("[%s\r\n]+", "")
	f:close()
	return content
end

local function get_playlist_lines()
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

local function get_mpv_title()
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

-- === LÓGICA DEL PLUGIN ===

function M.setup(opts)
	config.setup(opts)
	vim.api.nvim_create_autocmd("VimLeave", {
		callback = function()
			os.execute("killall -9 mpv 2>/dev/null")
		end,
	})
end

local function update_window_title(track_path)
	local name = vim.fn.fnamemodify(track_path, ":t"):gsub("%.%w+$", "")
	local icon = config.options.icons.music or "🎶"
	vim.o.title = true
	vim.o.titlestring = icon .. " " .. name
	io.write(string.format("\27]2;%s %s\7", icon, name))
	io.flush()
	vim.schedule(function()
		vim.cmd([[redraw]])
	end)
end

local function get_progress_stats()
	local cmd = string.format(
		'echo \'{"command": ["get_property", "percent-pos"]}\' \'{"command": ["get_property", "time-pos"]}\' \'{"command": ["get_property", "duration"]}\' | socat - UNIX-CONNECT:%s 2>/dev/null',
		config.options.socket_path
	)
	local handle = io.popen(cmd)
	local result = handle:read("*a")
	handle:close()

	-- Extraer datos con regex
	local percent = result:match('"data"%s*:%s*(%d+%.?%d*)')
	local curr_sec = result:match('"data"%s*:%s*(%d+%.?%d*)', result:find("time%-pos") or 1)
	local total_sec = result:match('"data"%s*:%s*(%d+%.?%d*)', result:find("duration") or 1)

	if not percent then
		return ""
	end

	-- Formatear tiempo (MM:SS)
	local function format_time(seconds)
		if not seconds then
			return "00:00"
		end
		local s = tonumber(seconds)
		return string.format("%02d:%02d", math.floor(s / 60), math.floor(s % 60))
	end

	-- Dibujar barra
	local width = 20
	local done = math.floor(tonumber(percent) / 100 * width)
	local bar = ""
	for i = 1, width do
		bar = bar .. (i == done and "●" or (i < done and "─" or " "))
	end

	return string.format(
		"\n%s\n%s / %s (%d%%)",
		"[" .. bar .. "]",
		format_time(curr_sec),
		format_time(total_sec),
		math.floor(tonumber(percent))
	)
end

local function start_mpv_listener()
	if listener_job then
		vim.fn.jobstop(listener_job)
	end

	local socket = config.options.socket_path
	-- Usamos stdbuf -oL para forzar que socat escupa línea por línea sin retraso
	local cmd = string.format("stdbuf -oL socat - UNIX-CONNECT:%s", socket)

	listener_job = vim.fn.jobstart(cmd, {
		on_stdout = function(_, data)
			for _, line in ipairs(data) do
				-- Detectamos cuando MPV cambia de pista o actualiza metadata
				if line:find("metadata") or line:find("start%-file") then
					vim.defer_fn(function()
						local title = get_mpv_title()
						if title then
							local clean_title = title:gsub("%.%w+$", "")
							local icon = config.options.icons.music or "🎶"

							-- 1. Actualizar título de la terminal/ventana
							vim.o.titlestring = icon .. " " .. clean_title
							io.write(string.format("\27]2;%s %s\7", icon, clean_title))
							io.flush()

							-- 2. Mostrar notificación con la barra de progreso
							local stats = get_progress_stats() -- La función que hicimos antes
							vim.notify(clean_title .. stats, "info", {
								title = "Now Playing",
								icon = icon,
								replace = true,
							})

							-- Forzar redibujado de la UI
							vim.cmd([[redraw]])
						end
					end, 500)
				end
			end
		end,
		on_stderr = function() end,
		on_exit = function()
			listener_job = nil
		end,
	})
end

function M.play_at_index(idx)
	local lines = get_playlist_lines()
	if #lines == 0 then
		return
	end

	local n = tonumber(idx) or 1
	if n > #lines then
		n = 1
	elseif n < 1 then
		n = #lines
	end
	local track = lines[n]

	-- Notificación manual inmediata (funciona incluso si MPV tarda)
	local track_name = vim.fn.fnamemodify(track, ":t"):gsub("%.%w+$", "")
	vim.notify(track_name, "info", { title = "Music Player", icon = config.options.icons.music })

	update_window_title(track)
	os.execute("killall -9 mpv 2>/dev/null")
	write_file(config.options.current_idx_file, n)

	local cmd = string.format(
		"mpv --no-video --no-config --gapless-audio=yes --input-ipc-server=%s --playlist=%s --playlist-start=%d &",
		config.options.socket_path,
		config.options.m3u_file,
		n - 1
	)
	os.execute(cmd)

	vim.defer_fn(start_mpv_listener, 1000)
end

function M.show_controls()
	local current_title = get_mpv_title() or "Stopped"
	local icons = config.options.icons
	local items = {
		{ d = icons.play .. " Pause/Play", a = "pause" },
		{ d = icons.next .. " Next", a = "next" },
		{ d = icons.prev .. " Prev", a = "prev" },
		{ d = icons.stop .. " Stop", a = "stop" },
	}

	pickers
		.new(
			require("telescope.themes").get_dropdown({
				layout_config = { width = 0.4, height = 10 },
				prompt_title = icons.music .. " " .. current_title:gsub("%.%w+$", ""),
			}),
			{
				finder = finders.new_table({
					results = items,
					entry_maker = function(e)
						return { value = e.a, display = e.d, ordinal = e.d }
					end,
				}),
				sorter = conf.generic_sorter({}),
				attach_mappings = function(prompt_bufnr, map)
					local function exec()
						local sel = action_state.get_selected_entry()
						if not sel then
							return
						end
						if sel.value == "next" or sel.value == "prev" then
							local cmd = sel.value == "next" and "playlist-next" or "playlist-prev"
							os.execute(
								string.format(
									'echo \'{"command": ["%s"]}\' | socat - UNIX-CONNECT:%s',
									cmd,
									config.options.socket_path
								)
							)
							actions.close(prompt_bufnr)
							vim.defer_fn(M.show_controls, 150)
						elseif sel.value == "pause" then
							os.execute(
								string.format(
									'echo \'{"command": ["cycle", "pause"]}\' | socat - UNIX-CONNECT:%s',
									config.options.socket_path
								)
							)
						elseif sel.value == "stop" then
							os.execute("killall -9 mpv 2>/dev/null")
							actions.close(prompt_bufnr)
						end
					end
					map("i", "<CR>", exec)
					map("n", "<CR>", exec)
					return true
				end,
			}
		)
		:find()
end

function M.select_base_directory()
	local home = os.getenv("HOME")
	require("telescope.builtin").find_files({
		prompt_title = "Select Music Folder",
		cwd = home,
		find_command = { "fd", "--type", "d", "--max-depth", "4" },
		attach_mappings = function(prompt_bufnr, _)
			actions.select_default:replace(function()
				local selection = action_state.get_selected_entry()
				actions.close(prompt_bufnr)
				if selection then
					local full_path = (home .. "/" .. selection[1]):gsub("//+", "/")
					write_file(config.options.music_root_file, full_path)
					vim.notify("Library set to: " .. full_path)
				end
			end)
			return true
		end,
	})
end

function M.play_file_from_config()
	local path = read_file(config.options.music_root_file)
	if path == "" then
		return vim.notify("Set music library first!", "warn")
	end

	pickers
		.new({}, {
			prompt_title = "Songs (Top Level)",
			finder = finders.new_oneshot_job({
				"fd",
				"-t",
				"f",
				"-e",
				"mp3",
				"-e",
				"flac",
				"-e",
				"m4a",
				"--max-depth",
				"1",
				"--absolute-path",
				".",
				path,
			}, {}),
			sorter = conf.generic_sorter({}),
			attach_mappings = function(prompt_bufnr, _)
				actions.select_default:replace(function()
					local selection = action_state.get_selected_entry()
					local picker = action_state.get_current_picker(prompt_bufnr)
					local f = io.open(config.options.m3u_file, "w")
					if not f then
						return
					end
					local sel_idx, count = 1, 0
					for entry in picker.manager:iter() do
						count = count + 1
						f:write(entry[1] .. "\n")
						if selection[1] == entry[1] then
							sel_idx = count
						end
					end
					f:close()
					actions.close(prompt_bufnr)
					M.play_at_index(sel_idx)
				end)
				return true
			end,
		})
		:find()
end

function M.show_status()
	local title = get_mpv_title()
	if not title or title == "" then
		vim.notify("MPV is not playing", "warn", { title = "Music Player" })
		return
	end

	local stats = get_progress_stats()
	vim.notify(title:gsub("%.%w+$", "") .. stats, "info", {
		title = "Now Playing",
		icon = config.options.icons.music,
		replace = true, -- Esto evita que se amontonen las notificaciones
	})
end

return M

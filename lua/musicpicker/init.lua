local M = {}
local config = require("musicpicker.config")
local utils = require("musicpicker.utils")

local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values

-- Inicialización
function M.setup(opts)
	config.setup(opts)

	vim.api.nvim_create_autocmd("VimLeave", {
		callback = function()
			os.execute("killall -9 mpv 2>/dev/null")
		end,
	})
end

-- Función para escuchar eventos de MPV en segundo plano
local function start_mpv_listener()
	-- Este comando de shell escucha el socket y filtra cuando cambia el título
	-- Usamos vim.fn.jobstart para que no bloquee Neovim
	local socket = config.options.socket_path
	local cmd = string.format('socat - UNIX-CONNECT:%s | stdbuf -oL grep \'"property":"media-title"\'', socket)

	vim.fn.jobstart(cmd, {
		on_stdout = function(_, data)
			for _, line in ipairs(data) do
				if line ~= "" then
					-- Cuando MPV avisa que cambió el título, pedimos el nuevo nombre
					vim.defer_fn(function()
						local new_title = utils.get_mpv_title()
						if new_title then
							local icon = (config.options.icons and config.options.icons.music) or "🎶"
							vim.notify(icon .. " Now Playing: " .. new_title:gsub("%.%w+$", ""), "info", {
								title = "Music Player",
								replace = true, -- Reemplaza la notificación anterior para no llenar la pantalla
							})
						end
					end, 500) -- Pequeño delay para que MPV termine de cargar el archivo
				end
			end
		end,
	})
end

-- Actualiza el título de la ventana de Neovim
local function update_window_title(track_path)
	local name = vim.fn.fnamemodify(track_path, ":t"):gsub("%.%w+$", "")
	vim.o.title = true
	vim.o.titlestring = (config.options.icons and config.options.icons.music or "🎶") .. " " .. name

	-- Forzar actualización en terminales
	io.write(string.format("\27]2;🎶 %s\7", name))
	io.flush()

	vim.schedule(function()
		vim.cmd([[redraw]])
	end)
end

-- Reproducción
function M.play_at_index(idx)
	local lines = utils.get_playlist_lines()
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

	update_window_title(track)
	os.execute("killall -9 mpv 2>/dev/null")
	utils.write_file(config.options.current_idx_file, n)

	local cmd = string.format(
		"mpv --no-video --no-config --gapless-audio=yes --input-ipc-server=%s --playlist=%s --playlist-start=%d &",
		config.options.socket_path,
		config.options.m3u_file,
		n - 1
	)
	os.execute(cmd)
	-- Arrancamos el escuchador para captar cambios automáticos
	vim.defer_fn(function()
		start_mpv_listener()
	end, 500)
end

-- Navegación
function M.navigate(direction)
	local content = utils.read_file(config.options.current_idx_file)
	local current = tonumber(content) or 1
	M.play_at_index(current + direction)
end

-- Menú de Controles
function M.show_controls()
	local current_title = utils.get_mpv_title() or "MPV"
	local icons = config.options.icons or {}

	local items = {
		{ d = (icons.play or "▶") .. " Pause/Play", a = "pause" },
		{ d = (icons.next or "⏭") .. " Next", a = "next" },
		{ d = (icons.prev or "⏮") .. " Prev", a = "prev" },
		{ d = (icons.stop or "⏹") .. " Stop", a = "stop" },
	}

	pickers
		.new(
			require("telescope.themes").get_dropdown({
				layout_config = { width = 0.4, height = 10 },
				prompt_title = (icons.music or "🎶") .. " " .. current_title:gsub("%.%w+$", ""),
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
							vim.defer_fn(function()
								M.show_controls()
							end, 150)
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

-- Selección de base y búsqueda de archivos
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
					utils.write_file(config.options.music_root_file, full_path)
					vim.notify("Library set to: " .. full_path)
				end
			end)
			return true
		end,
	})
end

function M.play_file_from_config()
	local path = utils.read_file(config.options.music_root_file)
	if path == "" then
		vim.notify("Set music library first with select_base_directory", "warn")
		return
	end

	pickers
		.new({}, {
			prompt_title = "Songs (Current Directory Only)",
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
				"1", -- <--- ESTO limita la búsqueda a la carpeta raíz
				"--absolute-path",
				".",
				path,
			}, {}),
			sorter = conf.generic_sorter({}),
			attach_mappings = function(prompt_bufnr, _)
				actions.select_default:replace(function()
					local selection = action_state.get_selected_entry()
					local picker = action_state.get_current_picker(prompt_bufnr)

					-- Guardamos la lista de lo que vemos en el picker actual
					local playlist_path = config.options.m3u_file
					local f = io.open(playlist_path, "w")
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

return M

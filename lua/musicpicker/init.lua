local M = {}
local config = require("musicpicker.config")
local utils = require("musicpicker.utils")

-- Importaciones de Telescope
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values

require("lspconfig").lua_ls.setup({
	settings = {
		Lua = {
			diagnostics = {
				-- Reconoce 'vim' como una global para que no marque error
				globals = { "vim" },
			},
			workspace = {
				-- Haz que el LSP conozca todas las funciones integradas de Neovim
				library = vim.api.nvim_get_runtime_file("", true),
				checkThirdParty = false,
			},
		},
	},
})

-- Función para que el usuario inicialice el plugin
function M.setup(opts)
	config.setup(opts)

	-- Autocmd para cerrar MPV al salir
	vim.api.nvim_create_autocmd("VimLeave", {
		callback = function()
			os.execute("killall -9 mpv 2>/dev/null")
		end,
	})
end

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
	if vim.fn.filereadable(m3u_file) == 1 then
		for line in io.lines(m3u_file) do
			local clean = line:gsub("[\r\n]+$", "")
			if clean ~= "" and not clean:match("^#") then
				table.insert(lines, clean)
			end
		end
	end
	return lines
end

-- --- NAVEGACIÓN Y REPRODUCCIÓN ---
local function update_title(track_path)
	local name = vim.fn.fnamemodify(track_path, ":t"):gsub("%.%w+$", "")

	-- 1. Intentar el método oficial de Neovim
	vim.o.title = true
	vim.o.titlestring = "🎶 " .. name

	-- 2. MÉTODO AGRESIVO: Enviar secuencia de escape ANSI directamente a la terminal
	-- \27]2; es el código para "Set Window Title"
	-- \7 es el terminador (Bell)
	io.write(string.format("\27]2;🎶 %s\7", name))
	io.flush() -- Forzar el envío del buffer a la terminal

	-- 3. Redibujar para asegurar que Neovim no lo pise inmediatamente
	vim.schedule(function()
		vim.cmd([[redraw]])
	end)
end

-- --- FUNCIÓN DE REPRODUCCIÓN NÚCLEO ---
function M.play_at_index(idx)
	local lines = get_playlist_lines()
	if #lines == 0 then
		vim.notify("Playlist vacía", "warn")
		return
	end

	-- Ajustar el índice para que sea circular
	local n = tonumber(idx) or 1
	if n > #lines then
		n = 1
	elseif n < 1 then
		n = #lines
	end

	local track = lines[n]
	if not track then
		return
	end

	-- 1. Detener cualquier instancia previa
	os.execute("killall -9 mpv 2>/dev/null")

	-- 2. Guardar el índice actual para que los comandos de Prev/Next sepan dónde están
	write_file(current_idx_file, n)

	-- 3. Actualizar el título de la ventana
	update_title(track)

	-- 4. EJECUTAR MPV CON LA PLAYLIST COMPLETA
	-- --playlist-start: indica qué número de canción empezar (empieza en 0, por eso n-1)
	-- --playlist: indica el archivo con la lista de canciones
	local cmd = string.format(
		"mpv --no-video --no-config --gapless-audio=yes " .. "--input-ipc-server=%s --playlist=%s --playlist-start=%d &",
		socket_path,
		m3u_file,
		n - 1
	)

	os.execute(cmd)

	-- 5. Notificar al usuario
	local track_name = vim.fn.fnamemodify(track, ":t"):gsub("%.%w+$", "")
	vim.notify(string.format("[%d/%d] 🎶 %s", n, #lines, track_name), "info")
end

function M.navigate(direction)
	-- Leemos el índice actual guardado en el archivo
	local content = read_file(current_idx_file)
	local current = tonumber(content) or 1

	-- Calculamos el nuevo índice
	local next_idx = current + direction

	-- Llamamos a la reproducción (que ejecutará update_title internamente)
	M.play_at_index(next_idx)
end

-- --- VISTAS PREVIAS (Peek) ---
function M.peek_next()
	local lines = get_playlist_lines()
	if #lines == 0 then
		return
	end
	local current = tonumber(read_file(current_idx_file)) or 1
	local next_idx = (current % #lines) + 1
	local name = vim.fn.fnamemodify(lines[next_idx], ":t")
	vim.notify("Siguiente: " .. name, "info", { title = "Cola" })
end

function M.peek_prev()
	local lines = get_playlist_lines()
	if #lines == 0 then
		return
	end
	local current = tonumber(read_file(current_idx_file)) or 1
	local prev_idx = current - 1
	if prev_idx < 1 then
		prev_idx = #lines
	end
	local name = vim.fn.fnamemodify(lines[prev_idx], ":t")
	vim.notify("Anterior: " .. name, "info", { title = "Cola" })
end

-- Actualiza el título de la ventana de Neovim
local function update_window_title(track_path)
	local name = vim.fn.fnamemodify(track_path, ":t"):gsub("%.%w+$", "")
	vim.o.title = true
	vim.o.titlestring = config.options.icons.music .. " " .. name
	vim.cmd([[redraw]])
end

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

	update_window_title(lines[n])
	os.execute("killall -9 mpv 2>/dev/null")
	utils.write_file(config.options.current_idx_file, n)

	local cmd = string.format(
		"mpv --no-video --no-config --gapless-audio=yes --input-ipc-server=%s --playlist=%s --playlist-start=%d &",
		config.options.socket_path,
		config.options.m3u_file,
		n - 1
	)
	os.execute(cmd)
end

function M.show_controls()
	local current_title = utils.get_mpv_title() or "MPV"
	local items = {
		{ d = config.options.icons.play .. " Pausa/Play", a = "pause" },
		{ d = config.options.icons.next .. " Next", a = "next" },
		{ d = config.options.icons.prev .. " Prev", a = "prev" },
		{ d = config.options.icons.stop .. " Stop", a = "stop" },
	}

	pickers
		.new(
			require("telescope.themes").get_dropdown({
				layout_config = { width = 0.4, height = 10 },
				prompt_title = config.options.icons.music .. " " .. current_title:gsub("%.%w+$", ""),
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
					return true
				end,
			}
		)
		:find()
end

-- (Aquí incluirías M.play_file_from_config y M.select_base_directory de la misma forma)

return M

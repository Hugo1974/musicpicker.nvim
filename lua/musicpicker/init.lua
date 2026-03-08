local M = {}
local config = require("musicpicker.config")
local utils = require("musicpicker.utils")

-- Importaciones de Telescope
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values

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

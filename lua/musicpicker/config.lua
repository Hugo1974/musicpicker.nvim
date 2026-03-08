local M = {}

-- Valores por defecto
M.defaults = {
	m3u_file = "/tmp/playlist.m3u",
	current_idx_file = "/tmp/current_idx.txt",
	socket_path = "/tmp/mpv-socket",
	music_root_file = vim.fn.stdpath("config") .. "/music_path.txt",
	-- Puedes añadir opciones de estilo aquí
	icons = {
		music = "󰎆 ",
		play = "▶",
		next = "⏭",
		prev = "⏮",
		stop = "⏹",
	},
}

M.options = {}

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M

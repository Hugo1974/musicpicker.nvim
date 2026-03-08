# musicpicker.nvim

A lightweight, minimal music player for Neovim powered by **Telescope** and
**MPV**. Manage your local music library, control playback, and see what's
playing directly in your editor's window title.

## ✨ Features

- **Library Browser**: Search and play your music folder using Telescope.

- **Dynamic Controls**: A floating menu to Play/Pause, Skip, and Stop.

- **Automatic Playback**: Gapless transitions between tracks using MPV
  playlists.

- **Window Title Integration**: Updates your terminal/GUI title with the current
  track name.

- **Auto-Cleanup**: Automatically kills the music process when you exit Neovim.

## 📋 Dependencies

Before installing, ensure you have the following CLI tools available:

- [mpv](https://mpv.io/) - The core media player.

- [socat](http://www.dest-unreach.org/socat/) - Required for IPC communication
  between Neovim and MPV.

- [fd](https://github.com/sharkdp/fd) - Fast directory searching for your music
  library.

- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) - The UI
  framework.

## 📦 Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua

{
    "Hugo1974/telescope-musicpicker.nvim",

    dependencies = { "nvim-telescope/telescope.nvim" },

    opts = {
      -- Optional configuration
      icons = {
        music = "󰎆 ",
        play = "▶",
        next = "⏭",
        prev = "⏮",
        stop = "⏹",
      }
    },

config = function(_, opts)

local mp = require("musicpicker")

mp.setup(opts)

-- Default Keymaps

vim.keymap.set(
      "n", "<leader>mc",
      mp.select_base_directory,
      { desc = "Music: Select Library Folder" })

vim.keymap.set(
      "n", "<leader>ml",
      mp.play_file_from_config,
      { desc = "Music: List Songs" })

vim.keymap.set(
      "n",
      "<leader>mm",
      mp.show_controls,
      { desc = "Music: Control Menu" })

vim.keymap.set(
      'n',
      '<leader>ms',
      mp.show_status,
      { desc = "Show music progress" })
end

}

```

## 🚀 Usage

- Select Library: **\<leader\>mc** to pick the folder where your music is stored.

- Play Music: **\<leader\>ml** to search for a song. Selecting one will generate a
  playlist of all songs in that folder and start playing.

- Control: **\<leader\>mm** to open the control menu. The menu title updates in
  real-time by querying the MPV socket.

- Status: **\<leader\>ms** Show progress status of song
  real-time by querying the MPV socket.

## ⚙️ Configuration

Config file: **musicpicker.nvim/lua/musicpicker/config.lua**

```lua
-- The setup() function accepts the following table:

{
  m3u_file = "/tmp/playlist.m3u",
  current_idx_file = "/tmp/current_idx.txt",
  socket_path = "/tmp/mpv-socket",
  music_root_file = vim.fn.stdpath("config") .. "/music_path.txt",
  icons = { ... }
}
```

## 📜 License

This project is licensed under the **GPLv3 License**. See the [LICENSE](./LICENSE) file for details.

## ⚠️ Disclaimer

This plugin utilizes logic and code snippets derived from community discussions
and collaborative AI-assisted development. While the integration and specific
Telescope implementation are original to this project, some low-level MPV IPC
handling and Neovim utility functions are based on common open-source patterns.

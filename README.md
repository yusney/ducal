# ducal

An opinionated, keyboard-friendly Ubuntu desktop in one command.

ducal turns a fresh Ubuntu install into a cohesive, themed workspace inspired by
[Omarchy](https://omarchy.org): tiling windows, a slim top bar, a fast launcher, and
one color palette shared by the desktop, the terminal, the editor and the tools you
use every day. Switch the whole desktop to another palette with a single command.

> **Status: work in progress.** The apps and configuration modules and the
> `ducal theme` command work today. The remaining modules are listed in the [roadmap](#roadmap).

## What you get

| Area | Setup |
| --- | --- |
| Desktop | GNOME with Tokyo Night GTK and shell themes, tiling via Forge, hidden dock, slim top bar |
| Launcher | Search Light on `Super+Space` |
| Terminal | kitty + fish + Starship, JetBrainsMono Nerd Font |
| Editor | Neovim with LazyVim, VS Code themed to match |
| Tools | btop, lazygit, yazi, git, gh, ripgrep, fd |
| Themes | Tokyo Night and Gruvbox, switched everywhere with `ducal theme` |
| System | Themed login screen (GDM) and boot splash (Plymouth), optional |

## Requirements

- Ubuntu 24.04 LTS with GNOME on x86_64 (other versions are untested)
- A user with `sudo` access
- An internet connection (packages and third-party assets are downloaded at install time)

## Install

```bash
git clone https://github.com/<user>/ducal.git ~/.local/share/ducal
cd ~/.local/share/ducal
./install.sh
```

Log out and back in when it finishes.

The installer is **idempotent**: running it again is safe. Any file of yours that
ducal replaces is kept next to it as `<file>.ducal-backup-<timestamp>`.

The installer asks which optional extras to add: Chrome, VS Code, Docker, Go,
Rust, Steam and Discord. Skip the questions with an environment variable:

```bash
DUCAL_EXTRAS=chrome,code,docker ./install.sh   # or DUCAL_EXTRAS=all / none
```

Installing Docker adds your user to the `docker` group, which grants root-equivalent
access through the Docker daemon.

Run or inspect single modules:

```bash
./install.sh --list           # list modules in run order
./install.sh --only config    # run one module
```

## Usage

```bash
ducal theme                # list themes, current one marked with *
ducal theme gruvbox        # switch the whole desktop to Gruvbox
ducal theme tokyo-night    # back to Tokyo Night
```

A theme switch updates kitty (live), fish, Starship, Neovim, yazi, btop, lazygit, VS Code,
the launcher, notifications, the lock screen, the top bar and the wallpaper.
Open a new terminal and reopen Neovim to see every change.

## Project layout

```
install.sh        entry point, runs install/NN-*.sh in order
install/          one idempotent module per concern
lib/common.sh     shared helpers (logging, safe linking, colors)
bin/ducal         the ducal command
config/           configuration files linked or copied into ~/.config
themes/<name>/    palette and per-tool color files for each theme
templates/        files generated from a palette (GNOME Shell overlay)
tests/run.sh      test suite (sandboxed HOME, no changes to your system)
```

## Adding a theme

Create `themes/<name>/` with the same files as `themes/tokyo-night/`:
`palette.env`, `kitty.conf`, `fish.fish`, `starship.toml` and `lazygit.yml`.
Then run `ducal theme <name>`.

## Roadmap

- [x] Configuration module and `ducal theme`
- [x] Applications: base tools plus optional extras
- [ ] GNOME setup (extensions, dock, top bar, Forge, launcher, shortcuts)
- [ ] Theme assets (GTK theme, cursors, icons, wallpapers)
- [ ] Login screen and boot splash, with one-command restore
- [ ] Optional cleanup of preinstalled software you do not need
- [ ] Screenshots

## Development

```bash
tests/run.sh
```

Tests run against a temporary `HOME` with stubbed desktop commands, so they never
touch your real configuration.

## Credits

ducal stands on the shoulders of these projects:

- [Omarchy](https://github.com/omacom/omarchy) by DHH and contributors: inspiration and wallpapers (MIT)
- [Tokyonight GTK Theme](https://github.com/Fausto-Korpsvart/Tokyonight-GTK-Theme) by Fausto-Korpsvart (GPL-3.0)
- [tokyonight.nvim](https://github.com/folke/tokyonight.nvim) by folke (Apache-2.0), also the source of the fish and lazygit palettes
- [tokyo-night.yazi](https://github.com/BennyOe/tokyo-night.yazi) and [gruvbox-dark.yazi](https://github.com/bennyyip/gruvbox-dark.yazi) flavors
- [gruvbox.nvim](https://github.com/ellisonleao/gruvbox.nvim) by ellisonleao (MIT)
- [Starship](https://starship.rs) presets (ISC)
- [Forge](https://github.com/forge-ext/forge), [Search Light](https://github.com/icedman/search-light) and other GNOME extensions by their authors

Third-party themes and wallpapers are downloaded at install time and are not
redistributed in this repository.

## License

[MIT](LICENSE)

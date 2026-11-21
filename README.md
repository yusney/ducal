# ducal

An opinionated, keyboard-friendly Ubuntu desktop in one command.

ducal turns a fresh Ubuntu install into a cohesive, themed workspace inspired by
[Omarchy](https://omarchy.org): tiling windows, a slim top bar, a fast launcher, and
one color palette shared by the desktop, the terminal, the editor and the tools you
use every day. Switch the whole desktop to another palette with a single command.

> **Status: work in progress.** Every module works today; screenshots are coming. The remaining modules are listed in the [roadmap](#roadmap).

## What you get

| Area | Setup |
| --- | --- |
| Desktop | GNOME with matching GTK and shell themes, Tela icons, Vimix cursors, tiling via Forge, hidden dock, slim top bar with numbered workspaces |
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
git clone https://github.com/yusney/ducal.git ~/.local/share/ducal
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

The system module themes the login screen and the boot splash. It changes system
files, so it asks first (or set `DUCAL_SYSTEM=yes` / `no`). Add your own logo next
to the distribution name with `DUCAL_LOGO=/path/to/logo.svg`. Undo it at any time:

```bash
ducal system restore
```

Restore switches back to the distribution's login theme and boot splash, and puts
back the logo line that `/etc/gdm3/greeter.dconf-defaults` had before ducal changed it.
Everything is built before any system file is touched, so a bad logo or a missing
theme stops the module without changing your system.

Run or inspect single modules:

```bash
./install.sh --list           # list modules in run order
./install.sh --only config    # run one module
```

## Optional cleanup

The last module can slim Ubuntu down. Nothing is removed unless you choose it: the
installer asks for each group, or answer in advance with
`DUCAL_CLEANUP=apps,office,telemetry,services` (or `all` / `none`).

| Group | What it does |
| --- | --- |
| `apps` | Removes Rhythmbox, Totem, Shotwell, Camera, Transmission, Remmina, Clocks, Characters, Help, USB Creator, Document Scanner, Déjà Dup, Calendar, gedit and Text Editor |
| `office` | Removes LibreOffice and Thunderbird (both the deb and the snap) |
| `telemetry` | Removes ubuntu-report, apport, whoopsie and kerneloops |
| `services` | Disables (does not uninstall) file indexing, printing, 3G/4G modems and network discovery |

Packages are removed with `apt-get remove`, so your documents and settings stay in your
home folder and `sudo apt install <package>` brings any of them back. Removing default
apps also removes the `ubuntu-desktop` metapackages, so ducal first marks the rest of
the desktop as manually installed: a later `apt autoremove` will not touch it.
Turn the services back on with `ducal cleanup restore-services`.

## Usage

```bash
ducal theme                # list themes, current one marked with *
ducal theme gruvbox        # switch the whole desktop to Gruvbox
ducal theme tokyo-night    # back to Tokyo Night
ducal wallpaper ~/me.png   # your own wallpaper, kept across theme switches
ducal wallpaper reset      # back to each theme's wallpaper
ducal search tokyo night   # web search in the default browser (Super+B opens a search box)
ducal system restore       # back to the distribution login screen and boot splash
ducal cleanup restore-services   # enable the services the cleanup disabled
```

A theme switch updates kitty (live), fish, Starship, Neovim, yazi, btop, lazygit, VS Code,
the launcher, notifications, the lock screen, the top bar and the wallpaper.
Open a new terminal and reopen Neovim to see every change.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| `Super+Space` | Launcher |
| `Super+B` | Search the web (or open an address) in your default browser |
| `Super+H/J/K/L` | Focus window left / down / up / right (Forge) |
| `Ctrl+Super+H/J/K/L` | Swap window |
| `Shift+Super+H/J/K/L` | Move window |
| `Super+C` | Toggle floating window |
| `Super+1…4` | Go to workspace 1–4 |
| `Super+Shift+1…4` | Send the window to workspace 1–4 |
| `Ctrl+Alt+L` | Lock screen |
| `Shift+Super+Space` | Switch keyboard layout |

ducal moves the lock screen to `Ctrl+Alt+L` and frees `Super+H` because Forge uses
`Super+H/J/K/L` for focus. It also disables Ubuntu Dock, Tiling Assistant and the
desktop icons, which clash with this setup. There are four fixed workspaces, shown
as numbers in the top bar (Space Bar extension) with the active one highlighted.

## Web search

`Super+B` opens a small search box. Press Enter to search in your default browser;
type an address such as `github.com` or `localhost:3000` to open it directly.
Google is the default engine. Use another one by writing its URL, with `%s` where
the query goes, to `~/.config/ducal/search-url`:

```bash
echo 'https://duckduckgo.com/?q=%s' > ~/.config/ducal/search-url
```

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
- [x] GNOME setup (extensions, dock, top bar, Forge, launcher, shortcuts)
- [x] Theme assets (GTK themes, cursors, icons, wallpapers)
- [x] Login screen and boot splash, with one-command restore
- [x] Optional cleanup of preinstalled software you do not need
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
- [Tokyonight](https://github.com/Fausto-Korpsvart/Tokyonight-GTK-Theme) and [Gruvbox](https://github.com/Fausto-Korpsvart/Gruvbox-GTK-Theme) GTK themes by Fausto-Korpsvart (GPL-3.0)
- [Tela circle icons](https://github.com/vinceliuice/Tela-circle-icon-theme) and [Vimix cursors](https://github.com/vinceliuice/Vimix-cursors) by vinceliuice (GPL-3.0)
- [tokyonight.nvim](https://github.com/folke/tokyonight.nvim) by folke (Apache-2.0), also the source of the fish and lazygit palettes
- [tokyo-night.yazi](https://github.com/BennyOe/tokyo-night.yazi) and [gruvbox-dark.yazi](https://github.com/bennyyip/gruvbox-dark.yazi) flavors
- [gruvbox.nvim](https://github.com/ellisonleao/gruvbox.nvim) by ellisonleao (MIT)
- [Starship](https://starship.rs) presets (ISC)
- [Forge](https://github.com/forge-ext/forge), [Search Light](https://github.com/icedman/search-light), [Space Bar](https://github.com/christopher-l/space-bar) and other GNOME extensions by their authors

Third-party themes and wallpapers are downloaded at install time and are not
redistributed in this repository.

## License

[MIT](LICENSE)

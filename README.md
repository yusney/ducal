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
| Launcher | [Ulauncher](https://ulauncher.io) on `Super+Space`, in the theme colors, with web search |
| Clipboard | History of the last 50 copies, text and images, on `Super+Shift+V` (Clipboard Indicator) |
| Terminal | kitty + fish + Starship, JetBrainsMono Nerd Font |
| Editor | Neovim with LazyVim, VS Code themed to match |
| Tools | btop, lazygit, yazi, git, gh, ripgrep, fd, [Claude Code CLI](https://docs.claude.com/en/docs/claude-code), [opencode](https://opencode.ai) |
| Themes | Tokyo Night and Gruvbox, switched everywhere with `ducal theme` |
| System | Themed login screen (GDM) and boot splash (Plymouth), optional |

## Requirements

- Ubuntu 24.04 LTS or newer with GNOME on x86_64 (tested on 24.04; the terminal tools
  also on 25.10 and 26.04). Only the
  terminal tools? Ubuntu on WSL or a server works too (see [Choose what to install](#choose-what-to-install)).
- A user with `sudo` access
- An internet connection (packages and third-party assets are downloaded at install time)

The installer checks all of this before it installs anything. It also installs what it
needs to start (curl, git, python3, CA certificates and whiptail) and stops with the
reason when something is missing: no apt, a CPU other than x86_64, running as root, no
sudo, no internet, a clock more than 5 minutes off (apt rejects package lists with a
wrong date: fix it with `sudo timedatectl set-ntp true`), or the `gnome` / `system`
groups chosen without a GNOME desktop.
The GNOME check runs right after the menu, once those prerequisites are in place and
before any group is installed. An Ubuntu older than 24.04, another distribution or less
than 5 GB free only shows a warning.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/yusney/ducal/main/boot.sh | bash
```

That one line installs git if needed, clones ducal into `~/.local/share/ducal`
(or updates it) and runs the installer. Pass options after `bash -s --`, for example
`curl -fsSL https://raw.githubusercontent.com/yusney/ducal/main/boot.sh | bash -s -- --profile dev`.
Prefer to read it first? Clone and run it yourself:

```bash
git clone https://github.com/yusney/ducal.git ~/.local/share/ducal
cd ~/.local/share/ducal
./install.sh
```

Log out and back in when it finishes. To update ducal later, run the same `curl`
line again: it pulls the latest version and reruns the installer, which keeps your files.
Lazygit downloads use the public GitHub releases page and do not require a GitHub API token.

### Choose what to install

The installer opens a checklist of groups (Space ticks, Enter confirms), then asks
which items you want from the groups that have them:

| Group | What it installs |
| --- | --- |
| `terminal` | fish, Neovim, Starship, git, gh, lazygit, yazi, btop, ripgrep, fd, Claude Code CLI with its status line, plugins and MCP servers, gentle-ai, engram, opencode, their configuration and colors |
| `languages` | Your pick of Node.js (fnm), Go, Rust and Docker |
| `desktop-apps` | kitty and JetBrainsMono Nerd Font, plus your pick of Chrome, VS Code, Steam and Discord |
| `gnome` | Extensions, tiling, top bar, launcher, clipboard history, GTK and shell themes, icons, cursors, wallpapers, shortcuts |
| `system` | Login screen and boot splash with the ducal mark |
| `cleanup` | Removes preinstalled software you do not need (see [Optional cleanup](#optional-cleanup)) |

On **WSL** the installer detects it and only offers `terminal` and `languages`, since
there is no graphical desktop. Skip the checklist with a profile or a list of groups:

```bash
./install.sh --profile desktop                 # terminal, desktop-apps, gnome
./install.sh --profile dev                     # terminal, languages (the WSL default)
DUCAL_GROUPS=terminal,languages ./install.sh   # or DUCAL_GROUPS=all
```

Without a terminal and no answer, the installer uses `desktop` (`dev` on WSL).

The same answers work with the one-line install:

```bash
curl -fsSL https://raw.githubusercontent.com/yusney/ducal/main/boot.sh | bash -s -- --profile dev
curl -fsSL https://raw.githubusercontent.com/yusney/ducal/main/boot.sh | DUCAL_GROUPS=terminal,languages bash
```

The installer is **idempotent**: running it again is safe. Any file of yours that
ducal replaces is kept next to it as `<file>.ducal-backup-<timestamp>`.

Pick the items of `languages` and `desktop-apps` in advance with an environment variable:

```bash
DUCAL_EXTRAS=chrome,code,docker ./install.sh   # or DUCAL_EXTRAS=all / none
```

The `node` extra installs [fnm](https://github.com/Schniz/fnm) and the latest
Node.js LTS, and adds the default version to the session `PATH`
(`~/.config/environment.d/60-ducal-node.conf`), so programs started outside a
terminal, such as editors and AI agents, find `node`, `npx` and global npm tools.
Log out and back in to apply it. Switch versions with `fnm default <version>`.

It also installs [ccstatusline](https://github.com/sirmalloc/ccstatusline), and the
`config` module gives Claude Code a Tokyo Night status line: model, context used,
folder, git branch and changes, session time and cost, 5-hour usage and time to reset.
The layout lives in `~/.config/ccstatusline/settings.json` (run `ccstatusline` to
edit it). When you already have another status line or ccstatusline style, the
installer asks whether to replace it (Enter means yes). Replacing it keeps your
previous style as `settings.json.ducal-backup-<date>`. Answer in advance with
`DUCAL_CLAUDE_STATUSLINE=replace` or `keep`. Without a terminal, yours is kept.

The `terminal` group always installs the `node` extra, because Claude Code's
status line and MCP servers need it. It then sets up Claude Code:

- [engram](https://github.com/Gentleman-Programming/engram) and
  [gentle-ai](https://github.com/Gentleman-Programming/gentle-ai) in `~/.local/bin`
  (latest release), and [codegraph](https://www.npmjs.com/package/@colbymchenry/codegraph)
  with npm. Run `gentle-ai` once afterwards to configure your agents.
- The plugins `engram@engram` and `warp@claude-code-warp` (user scope).
- The MCP servers `codegraph`, `context7`, `engram` and
  [Stitch](https://stitch.withgoogle.com) (user scope). Stitch needs your own Google
  API key: pass it with `STITCH_API_KEY=... ./install.sh`, or replace the
  placeholder `YOUR_STITCH_API_KEY` in `~/.claude.json` later. A Stitch server you
  already configured is kept.

Anything already installed or configured is left as it is. A step that fails only
shows a warning, and the rest of the install goes on.

Installing Docker adds your user to the `docker` group, which grants root-equivalent
access through the Docker daemon.

The system module themes the login screen and the boot splash. It is **not part of
any profile and not ticked in the checklist**: tick `system` yourself, or answer in
advance with the one-line install:

```bash
curl -fsSL https://raw.githubusercontent.com/yusney/ducal/main/boot.sh | DUCAL_SYSTEM=yes bash
```

It changes system files, so it asks first (or set `DUCAL_SYSTEM=yes` / `no`).
It is tested on Ubuntu 24.04 only: newer releases changed the Ubuntu theme files it
reads, so it may stop there with an error. Both show the ducal mark,
a D under a ducal coronet painted in the theme accent, next to the distribution name.
Use your own logo instead with `DUCAL_LOGO=/path/to/logo.svg`. Undo it at any time:

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
| `apps` | Removes Rhythmbox, Totem, Showtime, Shotwell, Camera, Transmission, Remmina, Clocks, Characters, Help, USB Creator, Document Scanner, Déjà Dup, Calendar, gedit and Text Editor |
| `office` | Removes LibreOffice and Thunderbird (both the deb and the snap) |
| `telemetry` | Removes ubuntu-report, ubuntu-insights, apport, whoopsie and kerneloops |
| `services` | Disables (does not uninstall) file indexing, printing, 3G/4G modems and network discovery |

Packages are removed with `apt-get remove`, so your documents and settings stay in your
home folder and `sudo apt install <package>` brings any of them back. Removing default
apps also removes the `ubuntu-desktop` metapackages, so ducal first marks the rest of
the desktop as manually installed: a later `apt autoremove` will not touch it.
Turn the services back on with `ducal cleanup restore-services`.

## Troubleshooting

### `Super+Space` does not open the launcher

1. **Check that Ulauncher is running**: `systemctl --user status ulauncher`. Start
   it with `systemctl --user enable --now ulauncher`. If the installer warned
   `Super+Space opens the app grid (Ulauncher could not be installed)`, run it
   again once its PPA (`ppa:agornostal/ulauncher`) is reachable.
2. **Check the shortcut**: Settings → Keyboard → Custom Shortcuts should list
   `Launcher` on `Super+Space` running `ulauncher-toggle`.
3. **Desktops installed before Ulauncher** had Search Light on `Super+Space`. Run
   the installer again: it turns Search Light off and sets up Ulauncher.
4. **In a virtual machine**, the host often keeps the `Super` key for itself. Capture
   the keyboard in the virtual machine (VirtualBox, VMware and GNOME Boxes each have a
   key or menu for it).

### No themed login screen or boot splash

- The `system` group is not installed unless you choose it (see
  [Choose what to install](#choose-what-to-install)). Run the installer again with
  `DUCAL_SYSTEM=yes`.
- In a virtual machine the boot splash often does not show even when it is installed,
  because of how the virtual display starts. The login screen should still change.
- On releases newer than 24.04 the `system` group is untested. If it stops with an
  error, `ducal system restore` puts the distribution's theme back.

### The Claude Code status line does not show

- If you already had another status line, the installer asks whether to replace it.
  Answer in advance with `DUCAL_CLAUDE_STATUSLINE=replace`.
- Open a new terminal before starting `claude`, so it finds Node and ccstatusline.
- **On WSL**, arrows and icons in the status line need a Nerd Font in **Windows
  Terminal**, installed in Windows (for example JetBrainsMono Nerd Font) and picked in
  the Ubuntu profile. Without it they show as boxes or question marks.

## Usage

```bash
ducal theme                # list themes, current one marked with *
ducal theme gruvbox        # switch the whole desktop to Gruvbox
ducal theme tokyo-night    # back to Tokyo Night
ducal wallpaper ~/me.png   # your own wallpaper, kept across theme switches
ducal wallpaper reset      # back to the theme's generated wallpaper
ducal system restore       # back to the distribution login screen and boot splash
ducal cleanup restore-services   # enable the services the cleanup disabled
```

A theme switch updates kitty (live), fish, Starship, Neovim, yazi, btop, lazygit, VS Code,
the launcher, notifications, the lock screen, the top bar and the wallpaper.
Each theme's wallpaper is generated from its palette, with the ducal mark as a watermark.
Open a new terminal and reopen Neovim to see every change.

## Keyboard shortcuts

The essentials. See the [full guide](docs/keybindings.md), or run `ducal keys`.

| Shortcut | Action |
| --- | --- |
| `Super+Space` | Launcher: apps, and web search with `g`, `yt` or `gh` |
| `Super+Shift+V` | Clipboard history (text and images) |
| `Ctrl+Alt+T` | Terminal (kitty) |
| `Super+Q` | Close the window (`Alt+F4` also works) |
| `Super+1…4` | Go to workspace 1–4 |
| `Super+Shift+1…4` | Send the window to workspace 1–4 |
| `Super+H/J/K/L` | Focus window left / down / up / right (Forge) |
| `Ctrl+Super+H/J/K/L` | Swap window |
| `Super+C` | Toggle floating window |
| `Ctrl+Alt+L` | Lock screen |

ducal moves the lock screen to `Ctrl+Alt+L` and frees `Super+H` because Forge uses
`Super+H/J/K/L` for focus. It also disables Ubuntu Dock, Tiling Assistant and the
desktop icons, which clash with this setup. There are four fixed workspaces, shown
as numbers in the top bar (Space Bar extension) with the active one highlighted.

## Launcher and web search

`Super+Space` opens [Ulauncher](https://ulauncher.io): type to find an app. It also
searches the web: type a keyword, a space and your query, then Enter.

| Keyword | Searches |
| --- | --- |
| `g` | Google (`g pizza`) |
| `yt` | YouTube (`yt lofi`) |
| `gh` | GitHub (`gh ducal`) |
| `so` | Stack Overflow (`so bash arrays`) |
| `wiki` | Wikipedia (`wiki Rome`) |

Ulauncher is a separate app, so it works on every GNOME version. It comes from its
PPA (`ppa:agornostal/ulauncher`), starts at every login and follows the ducal theme
colors (`ducal theme` updates them). Add or change keywords in its preferences
(the gear in the search box): ducal adds `yt` and `gh` and keeps every shortcut
you set up there.

## Project layout

```
boot.sh           one-line install: clones or updates ducal, then runs install.sh
install.sh        entry point, runs install/NN-*.sh in order
install/          one idempotent module per concern
lib/common.sh     shared helpers (logging, safe linking, colors)
bin/ducal         the ducal command
config/           configuration files linked or copied into ~/.config
themes/<name>/    palette and per-tool color files for each theme
templates/        files generated from a palette (GNOME Shell overlay)
tests/run.sh      test suite (sandboxed HOME, no changes to your system)
tests/containers.sh  real install of the terminal group in Ubuntu containers
```

## Adding a theme

Create `themes/<name>/` with the same files as `themes/tokyo-night/`:
`palette.env`, `kitty.conf`, `fish.fish`, `starship.toml` and `lazygit.yml`.
Then run `ducal theme <name>`.

## Roadmap

- [x] Configuration module and `ducal theme`
- [x] Applications: base tools plus optional extras
- [x] GNOME setup (extensions, dock, top bar, Forge, launcher, shortcuts)
- [x] Theme assets (GTK themes, cursors, icons) and generated wallpapers
- [x] Login screen and boot splash, with one-command restore
- [x] Optional cleanup of preinstalled software you do not need
- [ ] Screenshots

## Development

```bash
tests/run.sh
```

Tests run against a temporary `HOME` with stubbed desktop commands, so they never
touch your real configuration.

To check a real install on several Ubuntu releases, run `tests/containers.sh`
(Docker and internet needed, a few minutes per release). It installs the
`terminal` group as a sudo user in fresh `ubuntu:24.04`, `ubuntu:25.10` and
`ubuntu:26.04` containers and checks that every tool runs. Pass releases to pick
them: `tests/containers.sh 26.04`.

## Credits

ducal stands on the shoulders of these projects:

- [Omarchy](https://github.com/omacom/omarchy) by DHH and contributors: inspiration (MIT)
- [Tokyonight](https://github.com/Fausto-Korpsvart/Tokyonight-GTK-Theme) and [Gruvbox](https://github.com/Fausto-Korpsvart/Gruvbox-GTK-Theme) GTK themes by Fausto-Korpsvart (GPL-3.0)
- [Tela circle icons](https://github.com/vinceliuice/Tela-circle-icon-theme) and [Vimix cursors](https://github.com/vinceliuice/Vimix-cursors) by vinceliuice (GPL-3.0)
- [tokyonight.nvim](https://github.com/folke/tokyonight.nvim) by folke (Apache-2.0), also the source of the fish and lazygit palettes
- [tokyo-night.yazi](https://github.com/BennyOe/tokyo-night.yazi) and [gruvbox-dark.yazi](https://github.com/bennyyip/gruvbox-dark.yazi) flavors
- [gruvbox.nvim](https://github.com/ellisonleao/gruvbox.nvim) by ellisonleao (MIT)
- [Starship](https://starship.rs) presets (ISC)
- [Forge](https://github.com/forge-ext/forge), [Ulauncher](https://ulauncher.io), [Space Bar](https://github.com/christopher-l/space-bar) and other GNOME extensions by their authors

Third-party themes are downloaded at install time and are not
redistributed in this repository.

## License

[MIT](LICENSE)

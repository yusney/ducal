# ducal keyboard shortcuts

`Super` is the Windows key. Run `ducal keys` to see this guide in the terminal.

## Essentials

| Shortcut | Action |
| --- | --- |
| `Super+Space` | Open the launcher (apps, files, settings); `Ctrl+Space` also works |
| `Super+B` | Search the web, or open an address, in the default browser |
| `Super+Shift+V` | Clipboard history: the last 50 copies, text and images (`Super+V` is Forge's vertical split) |
| `Ctrl+Alt+T` | Open a terminal (kitty) |
| `Super+Q` | Close the focused window (`Alt+F4` also works) |
| `Ctrl+Alt+L` | Lock the screen |
| `Super` | Overview: every window and workspace |
| `Super+M` | Notifications and calendar |
| `Super+D` | Show the desktop |
| `Shift+Super+Space` | Switch keyboard layout |
| `Print` or `Shift+Super+S` | Screenshot or screen recording (the screenshot key of keyboards like the Logitech K950 sends `Shift+Super+S`) |

## Workspaces

There are four fixed workspaces, shown as numbers in the top bar: the active one is
filled with the accent color, workspaces with windows have a grey chip, and empty
ones are plain.

| Shortcut | Action |
| --- | --- |
| `Super+1` … `Super+4` | Go to workspace 1–4 |
| `Super+Shift+1` … `Super+Shift+4` | Send the focused window to workspace 1–4 |
| `Ctrl+Alt+←` / `Ctrl+Alt+→` | Previous / next workspace |
| `Ctrl+Shift+Alt+←` / `→` | Send the window to the previous / next workspace |

Clicking a number in the top bar also switches workspace.

## Tiling windows (Forge)

Windows are placed side by side automatically. `H J K L` are left, down, up, right,
as in Vim.

### Focus and arrange

| Shortcut | Action |
| --- | --- |
| `Super+H` / `J` / `K` / `L` | Focus the window to the left / below / above / right |
| `Ctrl+Super+H` / `J` / `K` / `L` | Swap the window with its neighbour in that direction |
| `Shift+Super+H` / `J` / `K` / `L` | Move the window in that direction |
| `Super+Enter` | Swap with the last focused window |

### Layout

| Shortcut | Action |
| --- | --- |
| `Super+G` | Toggle the split between side by side and stacked vertically |
| `Super+Z` | Open the next window to the side |
| `Super+V` | Open the next window below |
| `Ctrl+Super+S` | Stacked layout |
| `Shift+Super+T` | Tabbed layout |
| `Ctrl+Alt+Y` | Show or hide the tab bar |

### Floating windows

| Shortcut | Action |
| --- | --- |
| `Super+C` | Float the window, or tile it again |
| `Shift+Super+C` | Always float windows of this app |

### Resize

| Shortcut | Action |
| --- | --- |
| `Ctrl+Super+Y` / `U` / `I` / `O` | Grow towards the left / bottom / top / right |
| `Ctrl+Shift+Super+O` / `I` / `U` / `Y` | Shrink from the left / bottom / top / right |

### Thirds (the window becomes floating)

| Shortcut | Action |
| --- | --- |
| `Ctrl+Alt+D` / `Ctrl+Alt+E` | Left third / left two-thirds |
| `Ctrl+Alt+G` / `Ctrl+Alt+R` | Right third / right two-thirds |
| `Ctrl+Alt+C` | Center |

### Tiling options

| Shortcut | Action |
| --- | --- |
| `Ctrl+Super++` / `Ctrl+Super+-` | More / less space between windows |
| `Super+X` | Show or hide the border of the focused window |
| `Super+W` | Turn tiling on or off everywhere |
| `Shift+Super+W` | Turn tiling on or off on this workspace |
| `Super+.` | Forge settings |

## Terminal (kitty)

| Shortcut | Action |
| --- | --- |
| `Ctrl+Shift+T` | New tab |
| `Ctrl+Shift+W` | Close tab |
| `Ctrl+Shift+←` / `→` | Previous / next tab |
| `Ctrl+Shift+Enter` | Split: new window inside kitty |
| `Ctrl+Shift+A` / `Ctrl+Shift+D` | Focus the split to the left / right |
| `Ctrl+Shift+Tab` | Go back to the previous split |
| `Ctrl+Shift+L` | Next split layout |
| `Ctrl+Shift+Q` | Close the split |
| `Ctrl+Shift++` / `-` / `0` | Bigger / smaller / reset font size |

## Changes from stock Ubuntu

ducal reassigns a few GNOME shortcuts so that they do not clash:

| Shortcut | Stock Ubuntu | ducal |
| --- | --- | --- |
| `Super+1…9` | Open dock apps | Workspaces (`Super+5…9` do nothing) |
| `Super+L` | Lock the screen | Forge: focus right (lock is `Ctrl+Alt+L`) |
| `Super+H` | Minimize | Forge: focus left |
| `Super+Q` | Show the dock | Close the window |
| `Super+V` | Notifications | Forge: next window below (notifications: `Super+M`) |
| `Super+Space` | Switch keyboard layout | Launcher (layout: `Shift+Super+Space`) |
| `Ctrl+Alt+D` | Show the desktop | Forge: left third (desktop: `Super+D`) |
| `Ctrl+Alt+T` | GNOME Terminal | kitty |

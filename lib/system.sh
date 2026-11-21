#!/usr/bin/env bash
# Login screen (GDM) and boot splash (Plymouth) for ducal. Source after lib/common.sh.
# Every system path goes through $SYSROOT so tests can run against a fake root.

SYSROOT=${DUCAL_SYSROOT:-}
GS_THEMES="$SYSROOT/usr/share/gnome-shell/theme"
GDM_RESOURCE="$GS_THEMES/ducal/gnome-shell-theme.gresource"
YARU_RESOURCE="$GS_THEMES/Yaru/gnome-shell-theme.gresource"
GREETER="$SYSROOT/etc/gdm3/greeter.dconf-defaults"
# The distribution's original logo line, saved once so restore can put it back
GREETER_SAVED_LINE="$GREETER.ducal-logo-line"
LOGO_DEST="$SYSROOT/usr/share/pixmaps/ducal-logo.svg"
PLY_THEMES="$SYSROOT/usr/share/plymouth/themes"
PLY_THEME="$PLY_THEMES/ducal/ducal.plymouth"
PLY_DEFAULT="$PLY_THEMES/bgrt/bgrt.plymouth"

# compose_logo LOGO_SVG OUT_SVG — the logo, a divider and the distribution
# name and version (for example "Ubuntu" / "24.04.5 LTS") side by side.
compose_logo() {
  local name version
  name=$(. "$SYSROOT/etc/os-release" && echo "$NAME")
  version=$(. "$SYSROOT/etc/os-release" && echo "${VERSION%% (*}")
  python3 - "$1" "$2" "$name" "$version" "$FG_DIM" "$MUTED" "$BORDER" <<'EOF'
import re, sys
from xml.dom import minidom
from xml.sax.saxutils import escape
src, out, name, version, fg, muted, border = sys.argv[1:]
svg = open(src).read()
root = re.search(r"<svg\b([^>]*)>(.*)</svg>", svg, re.S)
view_box = root and re.search(r'viewBox="([^"]+)"', root.group(1))
if not view_box:
    sys.exit(f"{src}: not an SVG with a viewBox attribute")
# Keep namespace declarations (xlink, inkscape, ...) used inside the logo
namespaces = " ".join(re.findall(r'xmlns:[\w.-]+="[^"]*"', root.group(1)))
_, _, w, h = (float(v) for v in view_box.group(1).split())
H = 250.0                      # canvas height; the logo is scaled to fit it
lw = w * H / h
x = lw + 20
total = x + 480
result = f'''<?xml version="1.0" encoding="UTF-8"?>
<svg viewBox="0 0 {total:.0f} {H:.0f}" width="{total:.0f}" height="{H:.0f}" xmlns="http://www.w3.org/2000/svg" {namespaces}>
  <svg x="0" y="0" width="{lw:.0f}" height="{H:.0f}" viewBox="{view_box.group(1)}">{root.group(2)}</svg>
  <line x1="{x:.0f}" y1="65" x2="{x:.0f}" y2="185" stroke="{border}" stroke-width="4" stroke-linecap="round"/>
  <text x="{x + 40:.0f}" y="122" font-family="Ubuntu Sans, Ubuntu, sans-serif" font-size="66" font-weight="700" fill="{fg}">{escape(name)}</text>
  <text x="{x + 40:.0f}" y="190" font-family="Ubuntu Sans, Ubuntu, sans-serif" font-size="50" fill="{muted}">{escape(version)}</text>
</svg>
'''
try:
    minidom.parseString(result.encode())
except Exception as error:
    sys.exit(f"{src}: the composed logo is not valid SVG ({error})")
open(out, "w").write(result)
EOF
}

# svg_to_png SVG PNG WIDTH
svg_to_png() {
  python3 - "$@" <<'EOF'
import sys, gi
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import GdkPixbuf
GdkPixbuf.Pixbuf.new_from_file_at_scale(sys.argv[1], int(sys.argv[3]), -1, True).savev(sys.argv[2], "png", [], [])
EOF
}

# greeter_edit MODE FILE [VALUE] — prints FILE edited inside [org/gnome/login-screen]:
#   get            print the current logo line (commented or not), or nothing
#   set LOGO       set logo='LOGO', replacing the logo line or adding one
#   unset LOGO     replace logo='LOGO' with the line saved in $SAVED_LINE (or drop it)
greeter_edit() {
  SAVED_LINE=$(cat "$GREETER_SAVED_LINE" 2>/dev/null) python3 - "$@" <<'EOF'
import os, re, sys
mode, path = sys.argv[1], sys.argv[2]
value = sys.argv[3] if len(sys.argv) > 3 else ""
lines = open(path).read().splitlines()
logo_re = re.compile(r"^\s*#?\s*logo\s*=")
start = next((i for i, l in enumerate(lines) if l.strip() == "[org/gnome/login-screen]"), None)
end = len(lines)
if start is not None:
    end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("[")), len(lines))
logo_at = None if start is None else next((i for i in range(start + 1, end) if logo_re.match(lines[i])), None)

if mode == "get":
    print(lines[logo_at] if logo_at is not None else "")
    sys.exit(0)
if mode == "set":
    line = f"logo='{value}'"
    if logo_at is not None:
        lines[logo_at] = line
    elif start is not None:
        lines.insert(start + 1, line)
    else:
        lines += ["", "[org/gnome/login-screen]", line]
elif mode == "unset":
    ours = f"logo='{value}'"
    at = next((i for i in range(len(lines)) if lines[i].strip() == ours), None)
    if at is not None:
        saved = os.environ.get("SAVED_LINE", "")
        if saved:
            lines[at] = saved
        else:
            del lines[at]
print("\n".join(lines))
EOF
}

# greeter_apply NEW_CONTENT_FILE — installs the edited greeter and recompiles it.
greeter_apply() {
  as_root install -m 644 "$1" "$GREETER"
  as_root dpkg-reconfigure gdm3
}

# greeter_remove_logo WORK_DIR — puts back the distribution logo line, if ducal set one.
greeter_remove_logo() {
  if grep -qxF "logo='$LOGO_DEST'" "$GREETER" 2>/dev/null; then
    greeter_edit unset "$GREETER" "$LOGO_DEST" >"$1/greeter"
    greeter_apply "$1/greeter"
  fi
  # Also after an install that stopped before editing the greeter: the original
  # line is then still in place, so the saved copy is no longer needed.
  as_root rm -f "$LOGO_DEST" "$GREETER_SAVED_LINE"
}

# build_gdm_resource OUT — GTK theme shell stylesheet + ducal login rules,
# with every image the stylesheet references.
build_gdm_resource() {
  local out=$1 gtk shell src
  gtk=$GTK_THEME
  [[ -d $HOME/.themes/$gtk/gnome-shell ]] || gtk=Tokyonight-Dark
  shell="$HOME/.themes/$gtk/gnome-shell"
  [[ -f $shell/gnome-shell.css ]] || die "GNOME Shell theme not found in $shell (run ./install.sh --only assets)"
  src=$(mktemp -d)
  cp -rL "$shell/assets" "$src/assets"
  [[ -f $shell/pad-osd.css ]] && cp "$shell/pad-osd.css" "$src/"
  gresource extract "$YARU_RESOURCE" /org/gnome/shell/theme/gnome-shell-start.svg >"$src/gnome-shell-start.svg"
  { cat "$shell/gnome-shell.css"; render_template "$DUCAL_ROOT/templates/gdm.css"; } >"$src/gdm.css"
  {
    echo '<?xml version="1.0" encoding="UTF-8"?><gresources><gresource prefix="/org/gnome/shell/theme">'
    (cd "$src" && find . -type f | sed 's|^\./||' | sort | sed 's|.*|<file>&</file>|')
    echo '</gresource></gresources>'
  } >"$src/resources.xml"
  glib-compile-resources --sourcedir="$src" --target="$out" "$src/resources.xml"
  rm -rf "$src"
}

# build_plymouth_theme DIR [WATERMARK_PNG] — spinner theme on the palette background.
build_plymouth_theme() {
  local dir=$1 watermark=${2:-} hex=${BG#\#}
  mkdir -p "$dir"
  cp "$PLY_THEMES"/spinner/*.png "$dir/"
  rm -f "$dir/watermark.png" "$dir/bgrt-fallback.png"
  [[ -n $watermark ]] && cp "$watermark" "$dir/watermark.png"
  cat >"$dir/ducal.plymouth" <<EOF
[Plymouth Theme]
Name=ducal
Description=Spinner boot splash on the ducal theme background.
ModuleName=two-step

[two-step]
Font=Ubuntu 12
TitleFont=Ubuntu Light 30
ImageDir=/usr/share/plymouth/themes/ducal
DialogHorizontalAlignment=.5
DialogVerticalAlignment=.7
TitleHorizontalAlignment=.5
TitleVerticalAlignment=.382
HorizontalAlignment=.5
VerticalAlignment=.7
WatermarkHorizontalAlignment=.5
WatermarkVerticalAlignment=.45
Transition=none
TransitionDuration=0.0
BackgroundStartColor=0x$hex
BackgroundEndColor=0x$hex
ProgressBarBackgroundColor=0x${BORDER#\#}
ProgressBarForegroundColor=0x${ACCENT#\#}
MessageBelowAnimation=true

[boot-up]
UseEndAnimation=false

[shutdown]
UseEndAnimation=false

[reboot]
UseEndAnimation=false
EOF
}

# install_plymouth_dir SRC — swaps the theme directory in with a rename, so the
# active theme is never left missing if the run is interrupted.
install_plymouth_dir() {
  as_root rm -rf "$PLY_THEMES/ducal.new" "$PLY_THEMES/ducal.old"
  as_root install -d "$PLY_THEMES/ducal.new"
  as_root install -m 644 "$1"/* "$PLY_THEMES/ducal.new/"
  if [[ -d $PLY_THEMES/ducal ]]; then as_root mv "$PLY_THEMES/ducal" "$PLY_THEMES/ducal.old"; fi
  as_root mv "$PLY_THEMES/ducal.new" "$PLY_THEMES/ducal"
  as_root rm -rf "$PLY_THEMES/ducal.old"
}

# system_install [LOGO_SVG] — needs a theme palette loaded in the environment.
# Without LOGO_SVG the ducal mark is used, painted with the theme accent.
# Everything is built first; the system is only changed once every piece is ready.
system_install() {
  local logo=${1:-} work
  work=$(mktemp -d)

  log_step "Building the login screen and boot splash"
  build_gdm_resource "$work/gnome-shell-theme.gresource"
  if [[ -z $logo ]]; then
    logo="$work/ducal-mark.svg"
    render_template "$DUCAL_ROOT/templates/logo.svg" >"$logo"
  fi
  [[ -f $logo ]] || die "Logo not found: $logo"
  compose_logo "$logo" "$work/logo.svg"
  svg_to_png "$work/logo.svg" "$work/watermark.png" 640
  build_plymouth_theme "$work/plymouth" "$work/watermark.png"

  log_step "Login screen"
  as_root install -D -m 644 "$work/gnome-shell-theme.gresource" "$GDM_RESOURCE"
  as_root update-alternatives --install "$SYSROOT/usr/share/gnome-shell/gdm-theme.gresource" gdm-theme.gresource "$GDM_RESOURCE" 20
  as_root update-alternatives --set gdm-theme.gresource "$GDM_RESOURCE"
  if [[ ! -f $GREETER_SAVED_LINE ]]; then
    greeter_edit get "$GREETER" >"$work/saved-line"
    as_root install -m 644 "$work/saved-line" "$GREETER_SAVED_LINE"
  fi
  as_root install -D -m 644 "$work/logo.svg" "$LOGO_DEST"
  greeter_edit set "$GREETER" "$LOGO_DEST" >"$work/greeter"
  grep -qxF "logo='$LOGO_DEST'" "$work/greeter" || die "Could not set the logo in $GREETER"
  greeter_apply "$work/greeter"
  log_ok "Login screen themed (log out to see it)"

  log_step "Boot splash"
  install_plymouth_dir "$work/plymouth"
  as_root update-alternatives --install "$PLY_THEMES/default.plymouth" default.plymouth "$PLY_THEME" 100
  as_root update-alternatives --set default.plymouth "$PLY_THEME"
  log_step "Rebuilding the initramfs (this can take a minute)"
  as_root update-initramfs -u
  log_ok "Boot splash themed (reboot to see it)"

  rm -rf "$work"
}

# system_restore — back to the distribution's login screen and boot splash.
# Run it with errexit on (bin/ducal does) so a failed step is reported.
system_restore() {
  local work
  work=$(mktemp -d)
  log_step "Restoring the login screen"
  as_root update-alternatives --set gdm-theme.gresource "$YARU_RESOURCE"
  as_root update-alternatives --remove gdm-theme.gresource "$GDM_RESOURCE" 2>/dev/null || true
  greeter_remove_logo "$work"
  log_step "Restoring the boot splash"
  as_root update-alternatives --set default.plymouth "$PLY_DEFAULT"
  as_root update-alternatives --remove default.plymouth "$PLY_THEME" 2>/dev/null || true
  as_root update-initramfs -u
  rm -rf "$work"
  log_ok "Restored. Log out to see the login screen, reboot to see the boot splash."
}

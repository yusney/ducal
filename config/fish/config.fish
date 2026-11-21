# ducal fish configuration
# Theme colors are loaded from conf.d/ducal-theme.fish (managed by `ducal theme`).

fish_add_path --global "$HOME/.local/bin"
# Toolchains installed by the optional extras (paths that do not exist are ignored)
fish_add_path --global /usr/local/go/bin "$HOME/go/bin" "$HOME/.cargo/bin"

if status is-interactive
    set -g fish_greeting
    starship init fish | source
end

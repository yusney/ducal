# ducal fish configuration
# Theme colors are loaded from conf.d/ducal-theme.fish (managed by `ducal theme`).

fish_add_path --global "$HOME/.local/bin"

if status is-interactive
    set -g fish_greeting
    starship init fish | source
end

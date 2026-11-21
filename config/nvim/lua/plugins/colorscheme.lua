-- Colorscheme follows the desktop theme chosen with `ducal theme`
-- (~/.config/ducal/current). Falls back to Tokyo Night.
local function current_colorscheme()
  local schemes = {
    ["tokyo-night"] = "tokyonight-night",
    ["gruvbox"] = "gruvbox",
  }
  local file = io.open(vim.fn.expand("~/.config/ducal/current"), "r")
  if not file then
    return "tokyonight-night"
  end
  local name = vim.trim(file:read("*l") or "")
  file:close()
  return schemes[name] or "tokyonight-night"
end

return {
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      style = "night",
      transparent = true, -- let the kitty background show through
      styles = {
        sidebars = "transparent",
        floats = "transparent",
      },
    },
  },
  {
    "ellisonleao/gruvbox.nvim",
    lazy = false,
    priority = 1000,
    opts = { transparent_mode = true },
  },
  {
    "LazyVim/LazyVim",
    opts = { colorscheme = current_colorscheme() },
  },
}

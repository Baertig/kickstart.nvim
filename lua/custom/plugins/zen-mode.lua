return {
  'folke/zen-mode.nvim',
  config = function()
    local zen_mode = require 'zen-mode'
    zen_mode.setup {
      window = {
        width = 130,
      },
      plugins = {
        neovide = {
          enabled = true,
        },
      },
    }

    vim.keymap.set('n', '<c-a-s-z>', zen_mode.toggle, { desc = 'toggle [Z]en Mode' })
  end,
}

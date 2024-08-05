return {
  'Wansmer/treesj',
  dependencies = { 'nvim-treesitter/nvim-treesitter' }, -- if you install parsers with `nvim-treesitter`
  config = function()
    local treesj = require 'treesj'
    treesj.setup {
      use_default_keymaps = false,
    }

    vim.keymap.set('n', '<leader>j', treesj.join, { desc = '[J]oin node under cursor' })
    vim.keymap.set('n', '<leader>p', treesj.split, { desc = 's[P]lit node under cursor' })
  end,
}

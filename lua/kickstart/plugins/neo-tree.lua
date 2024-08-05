-- Neo-tree is a Neovim plugin to browse the file system
-- https://github.com/nvim-neo-tree/neo-tree.nvim

return {
  'nvim-neo-tree/neo-tree.nvim',
  version = '*',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'nvim-tree/nvim-web-devicons', -- not strictly required, but recommended
    'MunifTanjim/nui.nvim',
  },
  cmd = 'Neotree',
  keys = {
    { '<c-b>', ':Neotree reveal toggle left<CR>', desc = 'NeoTree reveal' },
  },
  config = function()
    require('neo-tree').setup {
      close_if_last_window = true,
      window = {
        mappings = {
          ['a'] = { 'add', config = { show_path = 'relative' } },
          ['c'] = { 'copy', config = { show_path = 'relative' } },
          ['m'] = { 'move', config = { show_path = 'relative' } },
          ['<c-b>'] = 'close_window',
        },
      },
      filesystem = {
        filtered_items = {
          hide_dotfiles = false,
        },
      },
    }
  end,
  opts = {
    filesystem = {
      window = {
        mappings = {
          ['<c-b>'] = 'close_window',
        },
      },
    },
  },
}

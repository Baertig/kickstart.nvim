return {
  'nvimdev/dashboard-nvim',
  event = 'VimEnter',
  config = function()
    require('dashboard').setup {
      change_to_vcs_root = true,
      config = {
        week_header = {
          enable = true,
        },
        shortcut = {
          {
            desc = ' Playground',
            group = 'Number',
            action = 'Neotree toggle float filesystem dir=~/play',
            key = 'y',
          },
          {
            desc = '  Projects',
            group = 'Conditional',
            action = 'Neotree toggle float filesystem dir=~/projects',
            key = 'p',
          },
          {
            desc = ' Files',
            group = 'Label',
            action = 'Telescope find_files',
            key = 'f',
          },
          {
            desc = '󰊳 Update',
            group = '@property',
            action = 'Lazy update',
            key = 'u',
          },
        },
        project = {
          enable = true,
          limit = 15,
          action = function(path)
            vim.cmd('cd ' .. path)
            vim.cmd 'Telescope find_files'
          end,
        },
        mru = {
          limit = 4,
        },
      },
    }
  end,
  dependencies = { { 'nvim-tree/nvim-web-devicons' } },
}

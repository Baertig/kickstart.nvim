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
            desc = 'open play',
            group = 'Conditional',
            action = 'Neotree toggle float filesystem dir=~/play',
            key = 'y',
          },
          {
            desc = 'open projects',
            group = 'Conditional',
            action = 'Neotree toggle float filesystem dir=~/projects',
            key = 'p',
          },
          {
            desc = '󰊳 Update',
            group = '@property',
            action = 'Lazy update',
            key = 'u',
          },
          {
            icon = ' ',
            icon_hl = '@variable',
            desc = 'Files',
            group = 'Label',
            action = 'Telescope find_files',
            key = 'f',
          },
          {
            desc = ' Apps',
            group = 'DiagnosticHint',
            action = 'Telescope app',
            key = 'a',
          },
          {
            desc = ' dotfiles',
            group = 'Number',
            action = 'Telescope dotfiles',
            key = 'd',
          },
        },
      },
      -- config
    }
  end,
  dependencies = { { 'nvim-tree/nvim-web-devicons' } },
}

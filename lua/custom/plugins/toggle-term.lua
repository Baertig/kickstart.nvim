return {
  'akinsho/toggleterm.nvim',
  config = function()
    require('toggleterm').setup {
      direction = 'vertical',
      size = 100,
    }

    local Terminal = require('toggleterm.terminal').Terminal
    local lazygit = Terminal:new { cmd = 'lazygit', hidden = true, direction = 'float', display_name = 'git' }

    local bash = Terminal:new {
      display_name = 'bash',
      on_open = function(term)
        vim.cmd 'set winblend=20'
      end,
      on_close = function()
        vim.cmd 'set winblend=0'
      end,
    }

    vim.keymap.set('n', '<c-j>', function()
      bash:toggle(100, 'vertical')
    end)

    vim.keymap.set('n', '<c-s-j>', function()
      bash:toggle(100, 'float')
    end)

    vim.keymap.set('t', '<c-j>', function()
      bash:toggle()
    end)

    vim.keymap.set('t', '<c-s-j>', function()
      bash:toggle()
    end)

    vim.keymap.set('n', '<leader>lg', function()
      lazygit:toggle()
    end, { desc = '[L]azy [G]it', nowait = true, silent = true })
  end,
}

return {
  'akinsho/toggleterm.nvim',
  config = function()
    require('toggleterm').setup {
      direction = 'vertical',
      size = 100,
    }

    local Terminal = require('toggleterm.terminal').Terminal
    local lazygit = Terminal:new { cmd = 'lazygit', hidden = true, direction = 'float', display_name = 'git' }

    vim.keymap.set('n', '<c-j>', ':ToggleTerm direction=vertical<cr>')
    vim.keymap.set('n', '<c-s-j>', ':ToggleTerm direction=float<cr>')
    vim.keymap.set('t', '<c-j>', '<C-\\><C-n>:ToggleTerm<cr>')
    vim.keymap.set('t', '<c-s-j>', '<C-\\><C-n>:ToggleTerm<cr>')

    vim.keymap.set('n', '<leader>gs', function()
      lazygit:toggle()
    end, { desc = '[G]it [S]tatus (lazygit)', nowait = true, silent = true })
  end,
}

return {
  'gbprod/substitute.nvim',
  config = function()
    require('substitute').setup {}
    -- replace gr<motion> with currently yanked
    vim.keymap.set('n', 'gr', require('substitute').operator, { noremap = true })
    -- Remove built-in Neovim 0.10+ gr* LSP keymaps that shadow the gr operator above.
    -- (Those LSP actions are already mapped elsewhere: gI, <leader>rn, gR, <leader>ca)
    for _, lhs in ipairs { 'gri', 'grn', 'grr', 'gra', 'grt', 'grx' } do
      pcall(vim.keymap.del, 'n', lhs)
    end
  end,
}

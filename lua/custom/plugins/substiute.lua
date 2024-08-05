return {
  'gbprod/substitute.nvim',
  config = function()
    require('substitute').setup {}
    -- replace gr<motion> with currently yanked
    vim.keymap.set('n', 'gr', require('substitute').operator, { noremap = true })
  end,
}

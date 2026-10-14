-- AI assistant powered by the opencode CLI.
-- Repo: https://github.com/NickvanDyke/opencode.nvim
--
-- Prerequisite: install the opencode CLI separately:
--   brew install sst/tap/opencode    (or `npm i -g opencode-ai`)
return {
  'NickvanDyke/opencode.nvim',
  dependencies = {
    -- Provides the input prompt and picker UI used by ask() and select().
    { 'folke/snacks.nvim', opts = { input = { enabled = true } } },
  },
  config = function()
    -- Required so buffers reload when opencode edits files on disk.
    vim.o.autoread = true

    -- OpenCode V2's shared background service is discovered automatically.
    vim.g.opencode_opts = {}

    local opencode = require 'opencode'

    -- Ask a question with editor context in the current OpenCode session.
    vim.keymap.set({ 'n', 'v' }, '<leader>aa', function()
      opencode.ask '@this: '
    end, { desc = '[A]I ask about context' })

    vim.keymap.set('n', '<leader>aA', function()
      opencode.ask '@buffer: '
    end, { desc = '[A]I ask about buffer' })
  end,
}

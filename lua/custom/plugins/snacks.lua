-- Shared UI helpers, independent of the plugins that use them.
return {
  'folke/snacks.nvim',
  priority = 1000,
  lazy = false, -- Capture notifications from startup onward.
  opts = {
    input = { enabled = true },
    notifier = {
      enabled = true,
      timeout = 4000,
      style = 'fancy',
    },
  },
}

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

    local opencode_cmd = 'opencode'
    local terminal_opts = {
      win = {
        position = 'right',
        width = 0.35,
        enter = false,
      },
    }

    -- OpenCode V2's shared background service is discovered automatically.
    vim.g.opencode_opts = {
      server = {
        start = function()
          Snacks.terminal.open(opencode_cmd, terminal_opts)
        end,
      },
      events = {
        -- Permission requests are handled in the OpenCode TUI.
        permissions = {
          enabled = false,
        },
      },
    }

    local opencode = require 'opencode'

    vim.api.nvim_create_autocmd('VimEnter', {
      group = vim.api.nvim_create_augroup('opencode-terminal', { clear = true }),
      once = true,
      callback = function()
        vim.schedule(function()
          local current_win = vim.api.nvim_get_current_win()
          Snacks.terminal.open(opencode_cmd, terminal_opts)
          if vim.api.nvim_win_is_valid(current_win) then
            vim.api.nvim_set_current_win(current_win)
          end
        end)
      end,
    })

    vim.keymap.set({ 'n', 't' }, '<leader>ao', function()
      Snacks.terminal.toggle(opencode_cmd, terminal_opts)
    end, { desc = '[A]I toggle [O]penCode' })

    local prompt_ns = vim.api.nvim_create_namespace 'opencode_multiline_prompt'

    ---Open an editable prompt while preserving the buffer/selection used by
    ---OpenCode's context placeholders. Writing the buffer submits it, so `:wq`
    ---works like it does for a temporary commit-message buffer.
    ---@param default string
    local function ask_multiline(default)
      require('opencode.server.discovery')
        .get()
        :next(function(server)
          -- This must be created before opening the float: Context.new captures
          -- the current buffer, cursor, and visual selection for @this.
          local context = require('opencode.context').new(server)
          local submitted = false
          local submitting = false
          local cancelled = false
          local group = vim.api.nvim_create_augroup('opencode-multiline-prompt', { clear = false })

          local function highlight(buf)
            if not vim.api.nvim_buf_is_valid(buf) then
              return
            end

            vim.api.nvim_buf_clear_namespace(buf, prompt_ns, 0, -1)
            local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
            for _, mark in ipairs(context:render(text).input:extmarks()) do
              vim.api.nvim_buf_set_extmark(buf, prompt_ns, mark.row - 1, mark.col or 0, {
                end_col = mark.end_col,
                hl_group = mark.hl_group,
              })
            end
          end

          local win
          local function submit()
            if submitted or submitting or not win or not vim.api.nvim_buf_is_valid(win.buf) then
              return
            end

            local prompt = table.concat(vim.api.nvim_buf_get_lines(win.buf, 0, -1, false), '\n')
            if vim.trim(prompt) == '' then
              vim.notify('OpenCode prompt is empty', vim.log.levels.WARN)
              return
            end

            submitting = true
            vim.bo[win.buf].modified = false
            vim.schedule(function()
              if win and win:valid() then
                win:close()
              end
              submitted = true
              submitting = false
              require('opencode.api.prompt').prompt(prompt, context):catch(function(err)
                vim.notify(err, vim.log.levels.ERROR, { title = 'opencode' })
              end)
            end)
          end

          win = Snacks.win {
            title = ' Ask OpenCode — :wq to submit ',
            title_pos = 'left',
            width = 0.7,
            height = 0.3,
            border = 'rounded',
            enter = true,
            minimal = false,
            footer = ' <C-Space> complete · :q cancel ',
            footer_pos = 'right',
            text = vim.split(default or '', '\n', { plain = true }),
            bo = {
              buftype = 'acwrite',
              bufhidden = 'wipe',
              swapfile = false,
              filetype = 'opencode_ask',
            },
            wo = {
              wrap = true,
              linebreak = true,
            },
            keys = {
              submit = { '<C-s>', submit, mode = { 'n', 'i' }, desc = 'Submit prompt' },
              cancel = {
                '<Esc>',
                function(self)
                  cancelled = true
                  vim.bo[self.buf].modified = false
                  context:resume()
                  self:close()
                end,
                mode = 'n',
                desc = 'Cancel prompt',
              },
            },
            on_buf = function(self)
              vim.api.nvim_buf_set_name(self.buf, 'opencode://prompt/' .. self.buf)

              vim.api.nvim_create_autocmd('BufWriteCmd', {
                group = group,
                buffer = self.buf,
                callback = submit,
              })
              vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
                group = group,
                buffer = self.buf,
                callback = function()
                  highlight(self.buf)
                end,
              })

              -- Reuse opencode.nvim's in-process LSP. blink.cmp is already
              -- configured for the opencode_ask filetype in init.lua.
              vim.lsp.start(require 'opencode.ui.ask.cmp', { bufnr = self.buf })
              highlight(self.buf)
            end,
            on_close = function()
              if not submitted and not submitting and not cancelled then
                context:resume()
              end
            end,
          }

          vim.schedule(function()
            if win:valid() then
              vim.api.nvim_win_set_cursor(win.win, { vim.api.nvim_buf_line_count(win.buf), #(vim.api.nvim_buf_get_lines(win.buf, -2, -1, false)[1] or '') })
              vim.cmd.startinsert()
            end
          end)
        end)
        :catch(function(err)
          vim.notify(err, vim.log.levels.ERROR, { title = 'opencode' })
        end)
    end

    -- Ask a question with editor context in the current OpenCode session.
    vim.keymap.set({ 'n', 'v' }, '<leader>aa', function()
      ask_multiline '@this: '
    end, { desc = '[A]I ask about context' })

    vim.keymap.set('n', '<leader>aA', function()
      ask_multiline '@buffer: '
    end, { desc = '[A]I ask about buffer' })
  end,
}

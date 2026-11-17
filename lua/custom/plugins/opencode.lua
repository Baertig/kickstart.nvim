-- AI assistant powered by the opencode CLI.
-- Repo: https://github.com/NickvanDyke/opencode.nvim
--
-- Prerequisite: install the opencode CLI separately:
--   brew install sst/tap/opencode    (or `npm i -g opencode-ai`)
return {
  'NickvanDyke/opencode.nvim',
  dependencies = {
    -- Provides the multiline window and the input UI used by ask().
    'folke/snacks.nvim',
    {
      'saghen/blink.cmp',
      opts = function(_, opts)
        local path_opts = vim.tbl_get(opts, 'sources', 'providers', 'path', 'opts') or {}
        local get_cwd = path_opts.get_cwd or function(ctx)
          return vim.fn.expand(('#%d:p:h'):format(ctx.bufnr))
        end
        local auto_show = vim.tbl_get(opts, 'completion', 'menu', 'auto_show')

        -- Extend Blink's general setup here so prompt completion stays with
        -- the OpenCode integration rather than in init.lua.
        return vim.tbl_deep_extend('force', opts, {
          completion = {
            menu = {
              auto_show = function(ctx, items)
                -- Avoid distracting popups while composing a prompt. Blink's
                -- <C-Space> show command still opens the menu explicitly.
                if not vim.api.nvim_buf_is_valid(ctx.bufnr) or vim.bo[ctx.bufnr].filetype == 'opencode_ask' then
                  return false
                end
                if type(auto_show) == 'function' then
                  return auto_show(ctx, items)
                end
                return auto_show ~= false
              end,
            },
          },
          sources = {
            per_filetype = {
              opencode_ask = { 'lsp', 'path', 'opencode_buffer' },
            },
            providers = {
              path = {
                opts = {
                  get_cwd = function(ctx)
                    -- Prompt buffers have a URI, not a filesystem path.
                    return vim.b[ctx.bufnr].opencode_cwd or get_cwd(ctx)
                  end,
                },
              },
              opencode_buffer = {
                name = 'Current file',
                module = 'blink.cmp.sources.buffer',
                opts = {
                  get_bufnrs = function()
                    local buf = vim.b.opencode_source_buf
                    return buf and vim.api.nvim_buf_is_loaded(buf) and { buf } or {}
                  end,
                },
              },
            },
          },
        })
      end,
    },
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
        -- External-editor launches opt out via EDITOR/VISUAL.
        if vim.env.NVIM_NO_OPENCODE == '1' then
          return
        end

        vim.schedule(function()
          local current_win = vim.api.nvim_get_current_win()
          Snacks.terminal.open(opencode_cmd, terminal_opts)
          if vim.api.nvim_win_is_valid(current_win) then
            vim.api.nvim_set_current_win(current_win)
          end
        end)
      end,
    })

    vim.keymap.set('n', '<leader>ao', function()
      Snacks.terminal.toggle(opencode_cmd, terminal_opts)
    end, { desc = '[A]I toggle [O]penCode' })

    local prompt_ns = vim.api.nvim_create_namespace 'opencode_multiline_prompt'
    -- These live only for this Neovim instance; no prompts are written to disk.
    -- Context/selection and whole-buffer prompts have separate drafts per file.
    local drafts = { ['@this: '] = {}, ['@buffer: '] = {} }
    local prompt_windows = { ['@this: '] = {}, ['@buffer: '] = {} }
    local recent_models = {}

    local function model_key(model)
      return model and (model.providerID .. '/' .. model.id .. (model.variant and '#' .. model.variant or '')) or 'session model'
    end

    local function remember_model(model)
      if not model then
        return
      end
      recent_models = vim.tbl_filter(function(item)
        return model_key(item) ~= model_key(model)
      end, recent_models)
      table.insert(recent_models, 1, vim.deepcopy(model))
      recent_models[4] = nil
    end

    local function draft_key(buf)
      local name = vim.api.nvim_buf_get_name(buf)
      return name ~= '' and not name:match '^%a[%w+.-]*://' and vim.fn.fnamemodify(name, ':p') or 'buffer:' .. buf
    end

    local function save_draft(draft)
      if draft.delivered then
        return
      end
      -- An untouched context placeholder isn't an unfinished question.
      local text = vim.trim(draft.text)
      drafts[draft.default][draft.key] = text ~= '' and text ~= vim.trim(draft.default) and draft or nil
    end

    local function prompt_title(draft)
      local context = draft.context
      local file = draft.key:match '^buffer:' and ('Untitled #' .. context.buf) or vim.fn.fnamemodify(draft.key, ':~:.')
      local scope = ' (whole buffer)'
      if draft.default ~= '@buffer: ' then
        scope = context.range and (':' .. context.range.from[1] .. '–' .. context.range.to[1]) or (':' .. context.cursor[1])
      end
      return ' Ask OpenCode · ' .. file .. scope .. ' · ' .. (draft.agent or 'session agent') .. ' · ' .. model_key(draft.model) .. ' '
    end

    local function clear_context(context)
      if vim.api.nvim_buf_is_valid(context.buf) then
        context:clear()
      end
    end

    local function resume_context(context)
      clear_context(context)
      if not context.range or not vim.api.nvim_win_is_valid(context.win) or vim.api.nvim_win_get_buf(context.win) ~= context.buf then
        return
      end
      -- gv otherwise uses the latest selection, not necessarily this draft's.
      pcall(vim.api.nvim_win_call, context.win, function()
        vim.api.nvim_buf_set_mark(context.buf, '<', context.range.from[1], context.range.from[2], {})
        vim.api.nvim_buf_set_mark(context.buf, '>', context.range.to[1], context.range.to[2], {})
        context:resume()
        local mode = ({ char = 'v', line = 'V', block = '\22' })[context.range.kind]
        if vim.fn.mode() ~= mode then
          vim.cmd.normal { args = { mode }, bang = true }
        end
      end)
    end

    ---Ask this workspace's OpenCode TUI to navigate to a session.
    ---
    ---Depends on the `nvim-nav` OpenCode plugin (see
    ---`~/.config/opencode/plugins/nvim-nav`). Scoping to this workspace relies on
    ---the `x-opencode-directory` header that every `server` request already
    ---sends (Neovim's cwd); the plugin only navigates the TUI whose own location
    ---matches. Avoid a `location[directory]` query here: `curl` treats `[`/`]` as
    ---glob characters and would reject the URL. This is best-effort: if the
    ---plugin isn't loaded the request simply fails and is ignored.
    ---@param server opencode.server.Server
    ---@param session_id string
    local function navigate_tui(server, session_id)
      server
        :request('/api/rpc/nvim-nav/open', 'POST', {
          input = { sessionID = session_id },
        })
        :catch(function() end)
    end

    ---Pick a session, apply explicit agent/model choices, then durably deliver the draft.
    ---@param server opencode.server.Server
    ---@param draft table
    ---@param reopen fun(server: opencode.server.Server)
    local function pick_session_and_prompt(server, draft, reopen)
      local Promise = require 'opencode.promise'
      local new_session = { new = true, title = 'New session' }

      -- Rediscover on each attempt so a service restart doesn't strand a draft
      -- on the old connection. This never retries a delivery automatically.
      require('opencode.server.discovery')
        .get()
        :next(function(active_server)
          server = active_server
          draft.context.server = server
          return server:request('/api/session?directory=' .. vim.uri_encode(draft.cwd) .. '&order=desc&parentID=null', 'GET')
        end)
        :next(function(response)
          local choices = { new_session }
          for _, session in ipairs(response and response.data or {}) do
            if not (session.time and session.time.archived) then
              table.insert(choices, session)
            end
          end

          return require('opencode.promise.ui').select(choices, {
            prompt = 'Send OpenCode prompt to:',
            format_item = function(choice)
              if choice.new then
                return '＋ New session'
              end

              return choice.title or choice.id
            end,
          })
        end)
        :next(function(choice)
          if not choice.new then
            return Promise.resolve(choice)
          end

          return server
            :request('/api/session', 'POST', {
              location = { directory = draft.cwd },
            })
            :next(function(response)
              local session = response and response.data
              if not session then
                return Promise.reject 'OpenCode did not return the new session'
              end
              return Promise.resolve(session)
            end)
        end)
        :next(function(session)
          -- V2 stores the primary agent on the session, not on individual prompts.
          local agent = draft.agent and server:request('/api/session/' .. session.id .. '/agent', 'POST', { agent = draft.agent }) or Promise.resolve()
          return agent
            :next(function()
              return draft.model and server:request('/api/session/' .. session.id .. '/model', 'POST', { model = draft.model }) or Promise.resolve()
            end)
            :next(function()
              local plaintext = draft.context:render(draft.text).output:plaintext()
              return server:prompt(session.id, plaintext):next(function(response)
                if not (response and response.data) then
                  return Promise.reject 'OpenCode did not confirm prompt delivery'
                end
                -- Only an accepted prompt clears the draft, not closing the editor
                -- or choosing an agent/model. Later UI errors must not offer a resend.
                draft.delivered = true
                draft.sending = false
                drafts[draft.default][draft.key] = nil
                remember_model(draft.model or session.model)
                clear_context(draft.context)
                vim.notify(('Sent prompt to %s'):format(session.title or session.id), vim.log.levels.INFO, { title = 'opencode' })
                navigate_tui(server, session.id)
                return Promise.resolve(session)
              end)
            end)
        end)
        :catch(function(err)
          draft.sending = false
          if draft.delivered then
            if err then
              vim.notify(tostring(err), vim.log.levels.ERROR, { title = 'opencode' })
            end
            return
          end
          save_draft(draft)
          if err then
            vim.notify(
              tostring(err) .. '\nDraft retained. Check the session before retrying if delivery is uncertain.',
              vim.log.levels.ERROR,
              { title = 'opencode' }
            )
          end
          vim.schedule(function()
            reopen(server)
          end)
        end)
    end

    ---Open a draft without recapturing its source selection when a picker is cancelled.
    local function open_draft(server, draft)
      local context = draft.context
      local windows = prompt_windows[draft.default]
      if not vim.api.nvim_buf_is_valid(context.buf) then
        save_draft(draft)
        vim.notify('Source buffer is gone. Draft retained; reopen its file to continue.', vim.log.levels.WARN, { title = 'opencode' })
        return
      end
      context.server = server
      require('opencode.context').current = context
      local group = vim.api.nvim_create_augroup('opencode-multiline-prompt', { clear = false })
      local win

      local function snapshot(buf)
        if not buf or not vim.api.nvim_buf_is_valid(buf) then
          return
        end
        draft.text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
        if win and win:valid() then
          draft.cursor = vim.api.nvim_win_get_cursor(win.win)
        end
        save_draft(draft)
      end

      local function highlight(buf)
        vim.api.nvim_buf_clear_namespace(buf, prompt_ns, 0, -1)
        local ok, rendered = pcall(context.render, context, draft.text)
        if not ok then
          return
        end
        for _, mark in ipairs(rendered.input:extmarks()) do
          vim.api.nvim_buf_set_extmark(buf, prompt_ns, mark.row - 1, mark.col or 0, {
            end_col = mark.end_col,
            hl_group = mark.hl_group,
          })
        end
      end

      -- The catalog is project-scoped and fetched only on demand. Encode the
      -- brackets so curl doesn't interpret the location query as a glob.
      local models, loading_models
      local function with_models(callback)
        if draft.sending or not win:valid() then
          return
        end
        if models then
          callback(models)
          return
        end
        if loading_models then
          return
        end
        loading_models = true
        server
          :request('/api/model?location%5Bdirectory%5D=' .. vim.uri_encode(draft.cwd), 'GET')
          :next(function(response)
            loading_models = false
            if draft.sending or not win:valid() then
              return
            end
            models = {}
            for _, model in ipairs(response and response.data or {}) do
              if model.enabled then
                local function add(variant)
                  local ref = { providerID = model.providerID, id = model.id, variant = variant }
                  table.insert(models, { model = ref, label = (model.name or model.id) .. ' · ' .. model_key(ref) })
                end
                add()
                for _, variant in ipairs(model.variants or {}) do
                  add(variant.id)
                end
              end
            end
            callback(models)
          end)
          :catch(function(err)
            loading_models = false
            vim.notify(tostring(err), vim.log.levels.ERROR, { title = 'opencode' })
          end)
      end

      local function pick_model()
        local was_insert = vim.api.nvim_get_mode().mode:sub(1, 1) == 'i'
        with_models(function(available)
          local ranks = {}
          for index, model in ipairs(recent_models) do
            ranks[model_key(model)] = index
          end
          local choices = vim.deepcopy(available)
          table.sort(choices, function(a, b)
            local first, second = ranks[model_key(a.model)] or math.huge, ranks[model_key(b.model)] or math.huge
            return first ~= second and first < second or first == second and a.label < b.label
          end)
          table.insert(choices, 1, { label = 'Use session model (no override)' })
          require('opencode.promise.ui')
            .select(choices, {
              prompt = 'Model for this prompt:',
              format_item = function(choice)
                return choice.label
              end,
            })
            :next(function(choice)
              if win:valid() then
                draft.model = choice.model
                win:set_title(prompt_title(draft), 'left')
              end
            end)
            :catch(function(err)
              if err then
                vim.notify(tostring(err), vim.log.levels.ERROR, { title = 'opencode' })
              end
            end)
            :finally(function()
              if win:valid() then
                vim.api.nvim_set_current_win(win.win)
                if was_insert then
                  vim.cmd.startinsert()
                end
              end
            end)
        end)
      end

      local loading_agents = false
      local function pick_agent()
        if draft.sending or loading_agents or not win:valid() then
          return
        end
        local was_insert = vim.api.nvim_get_mode().mode:sub(1, 1) == 'i'
        loading_agents = true
        server
          :request('/api/agent?location%5Bdirectory%5D=' .. vim.uri_encode(draft.cwd), 'GET')
          :next(function(response)
            if draft.sending or not win:valid() then
              return
            end
            local choices = {}
            for _, agent in ipairs(response and response.data or {}) do
              if not agent.hidden and (agent.mode == 'primary' or agent.mode == 'all') then
                local name = agent.name or agent.id
                table.insert(choices, { agent = agent.id, label = name == agent.id and name or (name .. ' · ' .. agent.id) })
              end
            end
            local ranks = { build = 1, plan = 2 }
            table.sort(choices, function(a, b)
              local first, second = ranks[a.agent] or math.huge, ranks[b.agent] or math.huge
              return first ~= second and first < second or first == second and a.label < b.label
            end)
            table.insert(choices, 1, { label = 'Use session agent (no override)' })
            return require('opencode.promise.ui').select(choices, {
              prompt = 'Agent for this session:',
              format_item = function(choice)
                return choice.label
              end,
            })
          end)
          :next(function(choice)
            if choice and not draft.sending and win:valid() then
              draft.agent = choice.agent
              win:set_title(prompt_title(draft), 'left')
            end
          end)
          :catch(function(err)
            if err then
              vim.notify(tostring(err), vim.log.levels.ERROR, { title = 'opencode' })
            end
          end)
          :finally(function()
            loading_agents = false
            if not draft.sending and win:valid() then
              vim.api.nvim_set_current_win(win.win)
              if was_insert then
                vim.cmd.startinsert()
              end
            end
          end)
      end

      local function submit()
        if draft.sending or not win or not win:valid() then
          return
        end
        snapshot(win.buf)
        if vim.trim(draft.text) == '' or vim.trim(draft.text) == vim.trim(draft.default) then
          vim.notify('OpenCode prompt is empty', vim.log.levels.WARN)
          return
        end
        draft.sending = true
        vim.bo[win.buf].modified = false
        vim.schedule(function()
          win:close()
          pick_session_and_prompt(server, draft, function(active_server)
            open_draft(active_server, draft)
          end)
        end)
      end

      win = Snacks.win {
        title = prompt_title(draft),
        title_pos = 'left',
        width = 0.7,
        max_width = 120, -- Keep prompts readable on wide screens.
        height = 0.3,
        border = 'rounded',
        -- Telescope's ui-select windows use 50. Equal stacking levels can
        -- hide its candidates and borders behind this prompt in Neovide.
        zindex = 40,
        enter = true,
        minimal = false,
        footer = ' <C-s> send · <C-Space> complete · <C-g>m model · <C-g>a agent · :q save draft ',
        footer_pos = 'right',
        text = vim.split(draft.text, '\n', { plain = true }),
        -- Highlight Markdown without changing the completion filetype.
        ft = 'markdown',
        b = {
          opencode_source_buf = context.buf,
          opencode_cwd = draft.cwd,
          opencode_draft_key = draft.key,
          opencode_draft_mode = draft.default,
        },
        bo = {
          buftype = 'acwrite',
          bufhidden = 'wipe',
          swapfile = false,
          undofile = false,
          filetype = 'opencode_ask',
        },
        wo = {
          wrap = true,
          linebreak = true,
        },
        keys = {
          submit = { '<C-s>', submit, mode = { 'n', 'i' }, desc = 'Submit prompt' },
          model = { '<C-g>m', pick_model, mode = { 'n', 'i' }, desc = 'Pick prompt model' },
          agent = { '<C-g>a', pick_agent, mode = { 'n', 'i' }, desc = 'Pick session agent' },
          cancel = {
            '<Esc>',
            function(self)
              vim.bo[self.buf].modified = false
              self:close()
            end,
            mode = 'n',
            desc = 'Close and keep draft',
          },
        },
        on_buf = function(self)
          local buf = self.buf
          vim.api.nvim_buf_set_name(buf, 'opencode://prompt/' .. buf)
          vim.api.nvim_create_autocmd('BufWriteCmd', { group = group, buffer = buf, callback = submit })
          vim.api.nvim_create_autocmd('QuitPre', {
            group = group,
            buffer = buf,
            callback = function()
              snapshot(buf)
              vim.bo[buf].modified = false
            end,
          })
          vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'BufLeave', 'BufWipeout' }, {
            group = group,
            buffer = buf,
            callback = function()
              snapshot(buf)
              if vim.api.nvim_buf_is_valid(buf) then
                highlight(buf)
              end
            end,
          })
          vim.api.nvim_create_autocmd('BufEnter', {
            group = group,
            buffer = buf,
            callback = function()
              require('opencode.context').current = context
            end,
          })
          -- Reuse opencode.nvim's in-process LSP. The Blink dependency above
          -- configures completion for the opencode_ask filetype.
          vim.lsp.start(require 'opencode.ui.ask.cmp', { bufnr = buf })
          highlight(buf)
        end,
        on_close = function(self)
          snapshot(self.buf)
          if windows[draft.key] == self then
            windows[draft.key] = nil
          end
          if not draft.sending then
            vim.schedule(function()
              if not prompt_windows['@this: '][draft.key] and not prompt_windows['@buffer: '][draft.key] then
                resume_context(context)
              end
            end)
          end
        end,
      }
      win.meta.opencode_draft = draft
      windows[draft.key] = win

      vim.schedule(function()
        if win:valid() then
          local lines = vim.api.nvim_buf_get_lines(win.buf, 0, -1, false)
          local cursor = draft.cursor or { #lines, #(lines[#lines] or '') }
          local row = math.min(cursor[1], #lines)
          vim.api.nvim_win_set_cursor(win.win, { row, math.min(cursor[2], #(lines[row] or '')) })
          vim.cmd.startinsert()
        end
      end)
    end

    ---Resume this file's draft for the requested flow, or capture new context.
    local function ask_multiline(default)
      local buf = vim.b.opencode_source_buf or vim.api.nvim_get_current_buf()
      local key = vim.b.opencode_draft_key or draft_key(buf)
      local saved = drafts[default]
      local existing = prompt_windows[default][key]
      if existing and existing:valid() then
        vim.api.nvim_set_current_win(existing.win)
        vim.cmd.startinsert()
        return
      end
      if saved[key] and saved[key].sending then
        vim.notify('This prompt is still being delivered.', vim.log.levels.INFO, { title = 'opencode' })
        return
      end
      local source_win = vim.api.nvim_get_current_win()
      if vim.b.opencode_draft_mode then
        -- Switching flows from inside the ask editor must capture the real file,
        -- not the other prompt's text or selection.
        local current = prompt_windows[vim.b.opencode_draft_mode][key]
        source_win = current and current.meta.opencode_draft.context.win
        if not source_win or not vim.api.nvim_win_is_valid(source_win) or vim.api.nvim_win_get_buf(source_win) ~= buf then
          vim.notify('Source window is unavailable. Reopen the file to start the other prompt.', vim.log.levels.WARN, { title = 'opencode' })
          return
        end
        vim.api.nvim_set_current_win(source_win)
      end
      require('opencode.server.discovery')
        .get()
        :next(function(server)
          if not vim.api.nvim_win_is_valid(source_win) or vim.api.nvim_get_current_win() ~= source_win or vim.api.nvim_win_get_buf(source_win) ~= buf then
            vim.notify('Source window changed while discovering OpenCode. Please ask again.', vim.log.levels.WARN, { title = 'opencode' })
            return
          end
          local context = require('opencode.context').new(server)
          local draft = saved[key]
          if draft then
            clear_context(context)
            -- Bind a reopened file to its current buffer/window, but retain the
            -- original cursor and selection instead of silently retargeting it.
            draft.context.buf = buf
            draft.context.win = source_win
          else
            draft = { key = key, default = default, text = default, context = context, cwd = vim.fn.getcwd() }
          end
          open_draft(server, draft)
        end)
        :catch(function(err)
          vim.notify(tostring(err), vim.log.levels.ERROR, { title = 'opencode' })
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

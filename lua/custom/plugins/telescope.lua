return {
  'nvim-telescope/telescope.nvim',
  event = 'VimEnter',
  branch = 'master',
  dependencies = {
    'nvim-lua/plenary.nvim',
    {
      'nvim-telescope/telescope-fzf-native.nvim',
      build = 'make',
      cond = function()
        return vim.fn.executable 'make' == 1
      end,
    },
    'nvim-telescope/telescope-ui-select.nvim',
    { 'nvim-tree/nvim-web-devicons', enabled = vim.g.have_nerd_font },
    'xiyaowong/telescope-emoji.nvim',
  },
  config = function()
    local telescope = require 'telescope'
    local actions = require 'telescope.actions'
    local state = require 'telescope.actions.state'

    local function find_files_command()
      return { 'rg', '--files', '--hidden', '--glob', '!**/.git/**', '--glob', '!**/node_modules/**', '--glob', '!**/vendor/**' }
    end

    local function copy_relative_path()
      local entry = state.get_selected_entry()
      if not entry then
        return
      end

      local path = entry.value
      vim.fn.setreg('+', path)
      vim.notify(('Copied relative path: %s'):format(path), vim.log.levels.INFO)
    end

    local function prioritize_filename(sorter)
      -- Wrap the picker's active sorter, retaining native fzf's lifecycle and highlighting.
      -- Resuming a picker reattaches mappings, so don't wrap the same sorter twice.
      if sorter._filename_priority then
        return
      end
      sorter._filename_priority = true

      local score = sorter.scoring_function
      sorter.scoring_function = function(self, prompt, line, entry)
        -- Explicit path queries and empty prompts keep the original ordering.
        if prompt == '' or prompt:find('/', 1, true) then
          return score(self, prompt, line, entry)
        end

        local path = entry and entry.value or line
        local path_score = score(self, prompt, path, entry)
        if path_score < 0 then
          return path_score
        end

        local filename = path:match '[^/]+$' or path
        local filename_score = score(self, prompt, filename, entry)
        -- Telescope prefers lower scores. Separate the two tiers while preserving
        -- fuzzy ordering within each: filenames [0, 1), directory-only matches [1, 2).
        if filename_score >= 0 then
          return filename_score / (1 + filename_score)
        end
        return 1 + path_score / (1 + path_score)
      end
    end

    local function configure_file_picker(prompt_bufnr, map)
      local picker = state.get_current_picker(prompt_bufnr)
      prioritize_filename(picker.sorter)
      map({ 'i', 'n' }, '<C-y>', copy_relative_path, { desc = 'Copy relative file path' })
      return picker
    end

    telescope.setup {
      defaults = {
        mappings = {
          i = {
            ['<C-?>'] = 'which_key',
            ['<C-h>'] = 'select_horizontal',
          },
        },
      },
      pickers = {
        find_files = {
          find_command = find_files_command,
          path_display = { 'filename_first', 'truncate' },
          prompt_title = false,
          results_title = 'Find Files',
          attach_mappings = function(prompt_bufnr, map)
            local picker = configure_file_picker(prompt_bufnr, map)

            map({ 'i', 'n' }, '<C-g>', function()
              picker.show_gitignored = not picker.show_gitignored
              local command = find_files_command()
              if picker.show_gitignored then
                table.insert(command, '--no-ignore-vcs')
              end
              local finder = require('telescope.finders').new_oneshot_job(command, {
                cwd = picker.cwd,
                entry_maker = picker.finder.entry_maker,
              })
              picker:refresh(finder, { reset_prompt = false })
            end, { desc = 'Toggle Git-ignored files' })

            picker.layout.prompt.border:change_title(' <C-g> toggle ignored · <C-y> copy path ', 'S')
            return true
          end,
        },
        git_status = {
          path_display = { 'filename_first', 'truncate' },
          attach_mappings = function(prompt_bufnr, map)
            local picker = configure_file_picker(prompt_bufnr, map)
            map({ 'i', 'n' }, '<Tab>', actions.toggle_selection + actions.move_selection_next)
            map({ 'i', 'n' }, '<S-Tab>', actions.toggle_selection + actions.move_selection_previous)
            picker.layout.prompt.border:change_title(' <Tab> select · <C-y> copy path ', 'S')
            return true
          end,
        },
        buffers = {
          mappings = {
            i = {
              ['<c-x>'] = actions.delete_buffer + actions.move_to_top,
            },
          },
        },
      },
      extensions = {
        ['ui-select'] = {
          require('telescope.themes').get_dropdown(),
        },
        emoji = {
          action = function(emoji)
            vim.api.nvim_put({ emoji.value }, 'c', false, true)
          end,
        },
      },
    }

    pcall(telescope.load_extension, 'fzf')
    pcall(telescope.load_extension, 'ui-select')
    pcall(telescope.load_extension, 'emoji')

    local builtin = require 'telescope.builtin'
    vim.keymap.set('n', '<leader>sh', builtin.help_tags, { desc = '[S]earch [H]elp' })
    vim.keymap.set('n', '<leader>sk', builtin.keymaps, { desc = '[S]earch [K]eymaps' })
    vim.keymap.set('n', '<c-p>', builtin.find_files, { desc = 'Search Files' })
    vim.keymap.set('n', '<leader>ss', builtin.builtin, { desc = '[S]earch [S]elect Telescope' })
    vim.keymap.set('n', '<leader>sg', builtin.git_status, { desc = '[S]earch [G]it status' })
    vim.keymap.set('n', '<leader>sw', builtin.grep_string, { desc = '[S]earch current [W]ord' })
    vim.keymap.set('x', '<leader>sw', function()
      local selection = table.concat(vim.fn.getregion(vim.fn.getpos '.', vim.fn.getpos 'v'), '\n')
      builtin.grep_string { search = selection }
    end, { desc = '[S]earch visual selection' })
    vim.keymap.set('n', '<c-s-f>', builtin.live_grep, { desc = '[S]earch by [G]rep' })
    vim.keymap.set('n', '<leader>sd', builtin.diagnostics, { desc = '[S]earch [D]iagnostics' })
    vim.keymap.set('n', '<leader>sr', builtin.resume, { desc = '[S]earch [R]esume' })
    vim.keymap.set('n', '<leader>s.', builtin.oldfiles, { desc = '[S]earch Recent Files ("." for repeat)' })
    vim.keymap.set('n', '<leader><leader>', builtin.buffers, { desc = '[ ] Find existing buffers' })

    vim.keymap.set('n', '<leader>s/', function()
      builtin.live_grep {
        grep_open_files = true,
        prompt_title = 'Live Grep in Open Files',
      }
    end, { desc = '[S]earch [/] in Open Files' })

    vim.keymap.set('n', '<leader>sn', function()
      builtin.find_files { cwd = vim.fn.stdpath 'config' }
    end, { desc = '[S]earch [N]eovim files' })

    vim.keymap.set('i', '<C-.>', '<Esc>:Telescope emoji<CR>', { desc = 'get them emojies' })
  end,
}

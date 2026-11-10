return {
  'nvim-treesitter/nvim-treesitter',
  branch = 'main',
  lazy = false,
  build = ':TSUpdate',
  dependencies = {
    {
      'nvim-treesitter/nvim-treesitter-textobjects',
      branch = 'main',
      config = function()
        require('nvim-treesitter-textobjects').setup {
          select = { lookahead = true },
        }

        local textobjects = {
          af = { '@function.outer', 'Select around function' },
          ['if'] = { '@function.inner', 'Select inner part of function' },
          ac = { '@class.outer', 'Select around class' },
          ic = { '@class.inner', 'Select inner part of a class' },
        }
        for keys, object in pairs(textobjects) do
          vim.keymap.set({ 'x', 'o' }, keys, function()
            require('nvim-treesitter-textobjects.select').select_textobject(object[1], 'textobjects')
          end, { desc = object[2] })
        end
      end,
    },
  },
  config = function()
    local treesitter = require 'nvim-treesitter'
    treesitter.setup {}

    local languages = {
      'bash',
      'c',
      'diff',
      'html',
      'lua',
      'luadoc',
      'markdown',
      'markdown_inline',
      'query',
      'vim',
      'vimdoc',
      'javascript',
      'typescript',
      'python',
    }

    local function start(buf)
      if not vim.api.nvim_buf_is_loaded(buf) or vim.bo[buf].buftype ~= '' then
        return
      end
      local lang = vim.treesitter.language.get_lang(vim.bo[buf].filetype)
      if not lang or not vim.treesitter.get_parser(buf, lang) then
        return
      end

      vim.treesitter.start(buf, lang)
      if lang == 'ruby' then
        -- Ruby's indentation relies on regex syntax highlighting.
        vim.bo[buf].syntax = 'ruby'
      elseif vim.treesitter.query.get(lang, 'indents') then
        vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
      end
    end

    local available = {}
    for _, lang in ipairs(treesitter.get_available()) do
      available[lang] = true
    end
    local installing = {}

    local function install(requested)
      local installed = treesitter.get_installed()
      local pending = {}
      for _, lang in ipairs(requested) do
        if available[lang] and not installing[lang] and not vim.list_contains(installed, lang) then
          installing[lang] = true
          pending[#pending + 1] = lang
        end
      end
      if #pending == 0 then
        return
      end

      -- Keep startup responsive and attach open buffers once their parsers are ready.
      treesitter.install(pending):await(vim.schedule_wrap(function(err)
        for _, lang in ipairs(pending) do
          installing[lang] = nil
        end
        if err then
          vim.notify('Tree-sitter installation failed: ' .. tostring(err), vim.log.levels.ERROR)
        end
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
          start(buf)
        end
      end))
    end

    vim.api.nvim_create_autocmd('FileType', {
      desc = 'Enable Tree-sitter and install missing supported parsers',
      group = vim.api.nvim_create_augroup('custom-treesitter', { clear = true }),
      callback = function(event)
        if vim.bo[event.buf].buftype ~= '' then
          return
        end
        start(event.buf)
        local lang = vim.treesitter.language.get_lang(vim.bo[event.buf].filetype)
        if lang then
          install { lang }
        end
      end,
    })

    install(languages)
  end,
}

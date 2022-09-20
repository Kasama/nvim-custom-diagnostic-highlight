---@brief [[
---A simple plugin to add custom diagnostic highlights
---@brief ]]

---@tag nvim-custom-diagnostic-highlight

local nvim_custom_diagnostic_highlight = {}
local augroup = vim.api.nvim_create_augroup('NvimCustomDiagnosticHighlight', { clear = true })

local any = function(fun, param)
    local r = false
    for _, v in ipairs(param) do
      r = r or fun(v)
      if r then break end
    end
    return r
end

-- Excerpt from neovim code
local function get_bufnr(bufnr)
  if not bufnr or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

-- Each diagnostic namespace stores user data, we store our data under user_data[diagnostic_handler_namespace]
local function get_user_data(diagnostic_ns, handler_ns)
  local data = diagnostic_ns.user_data[handler_ns]
  if not data then
    data = {
      -- Anonymous namespace used for highlights
      hl_namespace = vim.api.nvim_create_namespace(''),
      -- Autocommands used for deferring highlights, stored to remove them in hide() handler
      -- Just clearing augroup wouldn't work because we need to do this on per-namespace-per-buffer basis
      -- It is a map of sets: { buf1 = { id1 = true, id2 = true, ... } }
      autocmds = {},
    }
    diagnostic_ns.user_data[handler_ns] = data
  end
  return data
end

-- Generate a function that, when called, will check if cursor is currently outside
-- of the n-lines range around the diagnostic at (lnum, end_lnum).
local function is_n_lines_away(bufnr, n_lines, lnum, end_lnum)
  end_lnum = end_lnum or lnum
  return function()
    -- When we are in a different buffer, then this means we are not at that diagnostic
    if vim.api.nvim_get_current_buf() ~= bufnr then
      return true
    end
    -- Else check cursor position in current window. We don't care for other windows
    -- because user most likely cares only about the current editing position.
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    return row <= (lnum + 1) - n_lines or row >= (end_lnum + 1) + n_lines
  end
end

nvim_custom_diagnostic_highlight.setup = function(plugin_opts)

  local final_opts = {
    register_handler = true,
    handler_name = 'kasama/nvim-custom-diagnostic-highlight',
    highlight_group = 'Conceal',
    patterns_override = {'%sunused', '^unused', 'not used', 'never used', 'not read', 'never read', 'empty block'},
    extra_patterns = {},
    diagnostic_handler_namespace = 'unused_hl_ns',
    defer_until_n_lines_away = false,
    defer_highlight_update_events = { 'CursorHold', 'CursorHoldI' },
  }

  for k, v in pairs(plugin_opts) do
    final_opts[k] = v
  end

  local handler = {
    show = function(namespace, bufnr, diagnostics, opts)
      bufnr = get_bufnr(bufnr)
      opts = opts or {}

      for _, diagnostic in ipairs(diagnostics) do
        local higroup = final_opts.highlight_group

        local patterns = {}

        for _, p in ipairs(final_opts.patterns_override) do
          table.insert(patterns, p)
        end
        for _, p in ipairs(final_opts.extra_patterns) do
          table.insert(patterns, p)
        end

        local should_highlight_diagnostic = any(
          function(pattern)
            return string.match(string.lower(diagnostic.message), pattern) ~= nil
          end,
          patterns
        )

        local diagnostic_namespace = vim.diagnostic.get_namespace(namespace)
        local user_data = get_user_data(diagnostic_namespace, final_opts.diagnostic_handler_namespace)

        if should_highlight_diagnostic then
          local set_highlight = function()
            vim.highlight.range(
              bufnr,
              user_data.hl_namespace,
              higroup,
              { diagnostic.lnum, diagnostic.col },
              { diagnostic.end_lnum, diagnostic.end_col },
              { priority = vim.highlight.priorities.diagnostics }
            )
          end
          local should_highlight = final_opts.defer_until_n_lines_away and
            is_n_lines_away(bufnr, final_opts.defer_until_n_lines_away, diagnostic.lnum, diagnostic.end_lnum)

          -- Defer if deferred highlighting is enabled and highlighting cannot be done now
          -- Even here it's better to only check the current window, because user most likely
          -- cares only for the position they are currently editing.
          local defer = should_highlight and not should_highlight()

          if not defer then
            set_highlight()
          else
            -- Store creates autocmds in user data to later delete those that didn't delete themselves
            if not user_data.autocmds[bufnr] then
              user_data.autocmds[bufnr] = {}
            end
            local autocmds_set = user_data.autocmds[bufnr]

            local id
            id = vim.api.nvim_create_autocmd(final_opts.defer_highlight_update_events, {
              group = augroup,
              -- Do not set buffer=bufnr, because we want this to activate when user jumps out of
              -- the current buf and if this autocmd was created on CursorHold, then it wouldn't fire.
              -- Note that for deletion we still want to store autocmd ID in user_data.autocmds[bufnr].
              desc = 'Deferred custom diagnostic highlight',
              callback = function()
                -- No need to check other windows because cursor moves only in the current window
                -- (or at least, user moves their cursor _explicitly_ only in the current window).
                if should_highlight() then
                  set_highlight()
                  -- Delete this autocmd by returning true and remove it from our set
                  autocmds_set[id] = nil
                  return true
                end
              end
            })
            autocmds_set[id] = true
          end
        end
      end
    end,
    hide = function(namespace, bufnr)
      local ns = vim.diagnostic.get_namespace(namespace)
      local user_data = get_user_data(ns, final_opts.diagnostic_handler_namespace)

      vim.api.nvim_buf_clear_namespace(bufnr, user_data.hl_namespace, 0, -1)

      for id, _ in pairs(user_data.autocmds[bufnr] or {}) do
        pcall(vim.api.nvim_del_autocmd, id)
      end
      user_data.autocmds[bufnr] = {}
    end,
  }

  nvim_custom_diagnostic_highlight.handler = handler

  if final_opts.register_handler then
    vim.diagnostic.handlers[final_opts.handler_name] = handler;
  end

  return handler
end


return nvim_custom_diagnostic_highlight

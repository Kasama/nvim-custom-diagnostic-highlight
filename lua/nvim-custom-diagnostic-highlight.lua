---@brief [[
---A simple plugin to add custom diagnostic highlights
---@brief ]]

---@tag nvim-custom-diagnostic-highlight

local nvim_custom_diagnostic_highlight = {}

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

nvim_custom_diagnostic_highlight.setup = function(plugin_opts)

  local final_opts = {
    register_handler = true,
    handler_name = 'kasama/nvim-custom-diagnostic-highlight',
    highlight_group = 'Conceal',
    patterns_override = {'%sunused', '^unused', 'not used', 'never used', 'not read', 'never read', 'empty block'},
    extra_patterns = {},
    diagnostic_handler_namespace = 'unused_hl_ns',
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
        if not diagnostic_namespace.user_data[final_opts.diagnostic_handler_namespace] then
          diagnostic_namespace.user_data[final_opts.diagnostic_handler_namespace] = vim.api.nvim_create_namespace("")
        end

        if should_highlight_diagnostic then
          vim.highlight.range(
            bufnr,
            diagnostic_namespace.user_data[final_opts.diagnostic_handler_namespace],
            higroup,
            { diagnostic.lnum, diagnostic.col },
            { diagnostic.end_lnum, diagnostic.end_col },
            { priority = vim.highlight.priorities.diagnostics }
          )
        end
      end
    end,
    hide = function(namespace, bufnr)
      local ns = vim.diagnostic.get_namespace(namespace)
      if ns.user_data[final_opts.diagnostic_handler_namespace] then
        vim.api.nvim_buf_clear_namespace(bufnr, ns.user_data[final_opts.diagnostic_handler_namespace], 0, -1)
      end
    end,
  }

  nvim_custom_diagnostic_highlight.handler = handler

  if final_opts.register_handler then
    vim.diagnostic.handlers[final_opts.handler_name] = handler;
  end

  return handler
end


return nvim_custom_diagnostic_highlight

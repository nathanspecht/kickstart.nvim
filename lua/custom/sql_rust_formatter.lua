local embedded_sql = vim.treesitter.query.parse(
  'rust',
  [[
    (macro_invocation
	    (scoped_identifier
		    path: (identifier) @path (#eq? @path "sqlx")
		    name: (identifier) @name (#eq? @path "query_as"))
	    (token_tree
		    (raw_string_literal) @sql)
		    (#offset! @sql 1 0 -1 0))
	    ]]
)

local get_root = function(bufnr)
  local parser = vim.treesitter.get_parser(bufnr, 'rust', {})
  local tree = parser:parse()[1]
  return tree:root()
end

local run_formatter = function(sql_string)
  local formatted = {}

  local read_lines = function(callback)
    return function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= '' then
            callback(line)
          end
        end
      end
    end
  end

  local job_id = vim.fn.jobstart({ 'sql-formatter', '-l', 'postgresql' }, {
    stdin = 'pipe',
    on_stdout = read_lines(function(line)
      table.insert(formatted, line)
    end),
    on_stderr = read_lines(function(line)
      print(line)
    end),
    stdout_buffered = true,
    stderr_buffered = true,
  })

  local trimmed = sql_string:gsub('\n', ' ')

  vim.fn.chansend(job_id, { trimmed })
  vim.fn.chanclose(job_id, 'stdin')
  vim.fn.jobwait({ job_id }, 5000)

  return formatted
end

local format_dat_sql = function(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if vim.bo[bufnr].filetype ~= 'rust' then
    vim.notify 'can only be used in rust'
    return
  end

  local root = get_root(bufnr)
  local changes = {}

  for id, node in embedded_sql:iter_captures(root, bufnr, 0, -1) do
    local name = embedded_sql.captures[id]

    if name == 'sql' then
      local range = { node:range() }
      local indentation = string.rep(' ', range[2])

      local formatted = run_formatter(vim.treesitter.get_node_text(node, bufnr))

      for idx, line in ipairs(formatted) do
        formatted[idx] = indentation .. line
      end

      table.insert(changes, 1, { start = range[1] + 1, final = range[3], formatted = formatted })
    end
  end

  for _, change in ipairs(changes) do
    vim.api.nvim_buf_set_lines(bufnr, change.start, change.final, false, change.formatted)
  end
end

vim.api.nvim_create_user_command('SQLFormat', function()
  format_dat_sql()
end, {})

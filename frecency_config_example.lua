-- Example configuration showing how to port mini.visits functionality to Snacks frecency

-- Replace your mini.visits keybinding with this:
{
  "<leader>tr",
  function()
    -- Get recent files from Snacks frecency
    local recent_files = Snacks.frecency.get_recent_files()
    
    if not recent_files or #recent_files == 0 then
      vim.notify("No recent files found", vim.log.levels.WARN)
      return
    end
    
    -- Convert to picker items format
    local items = {}
    for _, path in ipairs(recent_files) do
      table.insert(items, { 
        text = path, 
        file = path, 
        path = path 
      })
    end
    
    -- Create the picker
    Snacks.picker.pick({
      title = "Recent files (frecency)",
      items = items,
      preview = false,
      format = "text",
      actions = {
        confirm = function(picker, item)
          picker:close()
          local f = item and (item.file or item.path)
          if f and f ~= "" then
            vim.cmd("edit " .. vim.fn.fnameescape(f))
          end
        end,
      },
    })
  end,
  desc = "Recent files (Snacks frecency)",
}

-- Optional: Auto-remember files when you open them
-- Add this to your config to automatically track file visits
vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
  callback = function(ev)
    local file = vim.api.nvim_buf_get_name(ev.buf)
    if file and file ~= "" and vim.bo[ev.buf].buftype == "" then
      -- Remember this file in frecency
      Snacks.frecency.remember(file)
    end
  end,
})

-- You can also remember non-file items in pickers
-- For example, in a custom search picker:
{
  "<leader>ts",
  function()
    -- Example: Remember search queries
    vim.ui.input({ prompt = "Search: " }, function(query)
      if query and query ~= "" then
        -- Remember the search query
        Snacks.frecency.remember(query)
        
        -- Your search logic here...
        print("Searching for:", query)
      end
    end)
  end,
  desc = "Search with frecency tracking",
}

-- Advanced example: Custom picker that shows both files and search queries
{
  "<leader>ta",
  function()
    -- Get all recent items (both files and non-files)
    local recent_items = Snacks.frecency.get_recent_items()
    
    if not recent_items or #recent_items == 0 then
      vim.notify("No recent items found", vim.log.levels.WARN)
      return
    end
    
    local items = {}
    for _, entry in ipairs(recent_items) do
      local icon = entry.is_path and "📁" or "🔍"
      table.insert(items, {
        text = icon .. " " .. entry.item,
        file = entry.is_path and entry.item or nil,
        path = entry.is_path and entry.item or nil,
        item = entry.item,
        is_path = entry.is_path,
      })
    end
    
    Snacks.picker.pick({
      title = "All Recent Items (frecency)",
      items = items,
      preview = false,
      format = "text",
      actions = {
        confirm = function(picker, item)
          picker:close()
          if item.is_path then
            -- Open file
            local f = item.file or item.path
            if f and f ~= "" then
              vim.cmd("edit " .. vim.fn.fnameescape(f))
            end
          else
            -- Handle non-file item (e.g., search query)
            vim.notify("Selected: " .. item.item, vim.log.levels.INFO)
            -- You could trigger a search or other action here
          end
        end,
      },
    })
  end,
  desc = "All recent items (files and searches)",
}

-- MRU-based frecency implementation
-- Maintains a Most Recently Used list of files with constant max size
---@class snacks.picker.Frecency
---@field mru_list snacks.picker.frecency.Entry[]
---@field path_index table<string, number>
local M = {}
M.__index = M

local uv = vim.uv or vim.loop
local store_file = vim.fn.stdpath("data") .. "/snacks/picker-frecency-mru.json"

local MAX_ENTRIES = 3000
local LOCK_TIMEOUT_MS = 1000
local LOCK_RETRY_MS = 50

---@class snacks.picker.frecency.Entry
---@field path string
---@field timestamp number

---@class snacks.picker.frecency.Store
---@field mru_list snacks.picker.frecency.Entry[]
---@field path_index table<string, number>
---@field file_path string
---@field lock_file string
local Store = {}
Store.__index = Store

-- Global store instance
---@type snacks.picker.frecency.Store?
M.store = nil

-- Store implementation
function Store.new(file_path)
  local self = setmetatable({}, Store)
  self.file_path = file_path
  self.lock_file = file_path .. ".lock"
  self.mru_list = {}
  self.path_index = {}
  self:load()
  return self
end

function Store:acquire_lock()
  local start_time = uv.hrtime()
  while (uv.hrtime() - start_time) / 1000000 < LOCK_TIMEOUT_MS do
    local fd = uv.fs_open(self.lock_file, "wx", 438) -- 0666 in octal
    if fd then
      -- Write our process ID to the lock file for debugging
      local pid = tostring(vim.fn.getpid())
      uv.fs_write(fd, pid, 0)
      uv.fs_close(fd)
      return true
    end
    -- Check if lock file is stale (older than 5 seconds)
    local stat = uv.fs_stat(self.lock_file)
    if stat and (os.time() - stat.mtime.sec) > 5 then
      -- Try to read the PID and check if process is still running
      local lock_fd = uv.fs_open(self.lock_file, "r", 438)
      if lock_fd then
        local pid_data = uv.fs_read(lock_fd, 32, 0)
        uv.fs_close(lock_fd)
        local pid = tonumber(pid_data)
        -- On Unix systems, we can check if process exists
        if pid and vim.fn.has("unix") == 1 then
          local result = vim.fn.system("kill -0 " .. pid .. " 2>/dev/null")
          if vim.v.shell_error ~= 0 then
            -- Process doesn't exist, remove stale lock
            uv.fs_unlink(self.lock_file)
          end
        else
          -- Fallback: remove old lock files
          uv.fs_unlink(self.lock_file)
        end
      end
    end
    vim.wait(LOCK_RETRY_MS)
  end
  return false
end

function Store:release_lock()
  pcall(uv.fs_unlink, self.lock_file)
end

function Store:load()
  if not self:acquire_lock() then
    -- If we can't acquire lock, try to load without it (read-only)
    local fd = uv.fs_open(self.file_path, "r", 438)
    if fd then
      local stat = uv.fs_fstat(fd)
      if stat and stat.size > 0 then
        local data = uv.fs_read(fd, stat.size, 0)
        uv.fs_close(fd)

        local ok, parsed = pcall(vim.json.decode, data)
        if ok and type(parsed) == "table" and parsed.entries then
          self.mru_list = parsed.entries or {}
          self:rebuild_index()
        end
      else
        uv.fs_close(fd)
      end
    end
    return false
  end

  local fd = uv.fs_open(self.file_path, "r", 438)
  if fd then
    local stat = uv.fs_fstat(fd)
    if stat and stat.size > 0 then
      local data = uv.fs_read(fd, stat.size, 0)
      uv.fs_close(fd)

      local ok, parsed = pcall(vim.json.decode, data)
      if ok and type(parsed) == "table" and parsed.entries then
        self.mru_list = parsed.entries or {}
        self:rebuild_index()
      end
    else
      uv.fs_close(fd)
    end
  end

  self:release_lock()
  return true
end

function Store:save()
  if not self:acquire_lock() then
    return false
  end

  -- Ensure directory exists
  vim.fn.mkdir(vim.fn.fnamemodify(self.file_path, ":h"), "p")

  local data = vim.json.encode({
    version = 1,
    entries = self.mru_list
  })

  local fd = uv.fs_open(self.file_path, "w", 438)
  if fd then
    uv.fs_write(fd, data, 0)
    uv.fs_close(fd)
    self:release_lock()
    return true
  end

  self:release_lock()
  return false
end

function Store:rebuild_index()
  self.path_index = {}
  for i, entry in ipairs(self.mru_list) do
    self.path_index[entry.path] = i
  end
end

function Store:visit(path)
  -- Normalize the path to ensure consistency - use same logic as picker
  path = self:normalize_path(path)

  local now = os.time()
  local existing_idx = self.path_index[path]

  if existing_idx then
    -- Remove existing entry
    table.remove(self.mru_list, existing_idx)
  end

  -- Add to front
  table.insert(self.mru_list, 1, {
    path = path,
    timestamp = now
  })

  -- Trim to max size
  if #self.mru_list > MAX_ENTRIES then
    for i = MAX_ENTRIES + 1, #self.mru_list do
      self.mru_list[i] = nil
    end
  end

  self:rebuild_index()
  return self:save()
end

function Store:normalize_path(path)
  -- Use the same normalization as the picker system
  if not path then return nil end

  -- First normalize with vim.fs.normalize to handle ~ expansion and clean up
  local normalized = vim.fs.normalize(path)

  -- For consistency, always store absolute paths
  if not vim.startswith(normalized, "/") then
    normalized = vim.fn.fnamemodify(normalized, ":p")
  end

  return normalized
end

function Store:get_score(path)
  -- Normalize path for lookup using same logic
  path = self:normalize_path(path)
  local idx = self.path_index[path]
  if not idx then
    return 0
  end
  -- Score decreases with position in MRU list
  -- Top item gets score close to MAX_ENTRIES, bottom gets score close to 1
  return MAX_ENTRIES - idx + 1
end

function Store:close()
  self:save()
end

function M.setup()
  M.store = Store.new(store_file)

  local group = vim.api.nvim_create_augroup("snacks_picker_frecency", {})
  vim.api.nvim_create_autocmd("ExitPre", {
    group = group,
    callback = function()
      if M.store then
        M.store:close()
        M.store = nil
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "BufWinEnter" }, {
    group = group,
    callback = function(ev)
      local current_win = vim.api.nvim_get_current_win()
      if vim.api.nvim_win_get_config(current_win).relative ~= "" then
        return
      end
      M.visit_buf(ev.buf)
    end,
  })
  -- Visit existing buffers (only if vim.api is available)
  if vim.api and vim.api.nvim_list_bufs then
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      M.visit_buf(buf)
    end
  end
end

function M.new()
  local self = setmetatable({}, M)
  if not M.store then
    M.setup()
  end
  -- Cache the MRU list for this instance
  self.mru_list = vim.deepcopy(M.store.mru_list)
  self.path_index = vim.deepcopy(M.store.path_index)
  return self
end

--- Get the current frecency score for an item.
---@param item snacks.picker.Item
---@param opts? {seed?: boolean}
function M:get(item, opts)
  opts = opts or {}
  local path = Snacks.picker.util.path(item)
  if not path then
    return 0
  end

  -- Normalize path for consistent lookup
  if M.store then
    path = M.store:normalize_path(path)
  else
    path = vim.fs.normalize(path)
    if not vim.startswith(path, "/") then
      path = vim.fn.fnamemodify(path, ":p")
    end
  end

  if item.dir then
    -- frecency of a directory is the sum of frecencies of all files in it
    local score = 0
    local prefix = path .. "/"
    for _, entry in ipairs(self.mru_list) do
      if entry.path:find(prefix, 1, true) == 1 then
        local idx = self.path_index[entry.path]
        if idx then
          score = score + (MAX_ENTRIES - idx + 1)
        end
      end
    end
    return score
  end

  local idx = self.path_index[path]
  if not idx then
    return opts.seed ~= false and self:seed(item) or 0
  end

  -- Score decreases with position in MRU list
  return MAX_ENTRIES - idx + 1
end

---@param item snacks.picker.Item
---@param value? number
function M:seed(item, value)
  -- For MRU system, seeding just means the item isn't in the list yet
  -- We don't add it automatically - only when explicitly visited
  return 0
end

--- Add a "visit" to the item.
--- Moves the item to the top of the MRU list.
---@param item snacks.picker.Item
---@param value? number @ignored in MRU system
function M:visit(item, value)
  local path = Snacks.picker.util.path(item)
  if not path then
    return
  end

  -- Update the global store
  if M.store then
    M.store:visit(path)
    -- Update our local cache
    self.mru_list = vim.deepcopy(M.store.mru_list)
    self.path_index = vim.deepcopy(M.store.path_index)
  end
end

---@param buf number
---@param value? number
function M.visit_buf(buf, value)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" or not vim.bo[buf].buflisted then
    return
  end
  local file = vim.api.nvim_buf_get_name(buf)
  if file == "" or not vim.uv.fs_stat(file) then
    return
  end

  -- Update the global store directly for buffer visits
  if M.store then
    M.store:visit(file)
  end
  return true
end

-- Expose Store class for testing
M.Store = Store

return M

---@class snacks.frecency
local M = {}

M.meta = {
  desc = "Frecency tracking for paths and arbitrary text",
}

local uv = vim.uv or vim.loop
local store_file = vim.fn.stdpath("data") .. "/snacks/frecency.json"

local MAX_ENTRIES = 3000
local LOCK_TIMEOUT_MS = 1000
local LOCK_RETRY_MS = 50

---@class snacks.frecency.Entry
---@field item string # path or arbitrary text
---@field timestamp number
---@field is_path boolean # whether this entry represents a file path

---@class snacks.frecency.Store
---@field mru_list snacks.frecency.Entry[]
---@field item_index table<string, number>
---@field file_path string
---@field lock_file string
local Store = {}
Store.__index = Store

-- Global store instance
---@type snacks.frecency.Store?
M.store = nil

-- Store implementation
function Store.new(file_path)
  local self = setmetatable({}, Store)
  self.file_path = file_path
  self.lock_file = file_path .. ".lock"
  self.mru_list = {}
  self.item_index = {}
  self:load()
  return self
end

function Store:acquire_lock()
  -- Simplified locking - just try once and proceed
  local fd = uv.fs_open(self.lock_file, "wx", 438) -- 0666 in octal
  if fd then
    -- Write our process ID to the lock file for debugging
    local pid = tostring(vim.fn.getpid())
    uv.fs_write(fd, pid, 0)
    uv.fs_close(fd)
    return true
  end

  -- If lock exists, check if it's stale (older than 5 seconds)
  local stat = uv.fs_stat(self.lock_file)
  if stat and (os.time() - stat.mtime.sec) > 5 then
    -- Remove stale lock and try again
    uv.fs_unlink(self.lock_file)
    fd = uv.fs_open(self.lock_file, "wx", 438)
    if fd then
      local pid = tostring(vim.fn.getpid())
      uv.fs_write(fd, pid, 0)
      uv.fs_close(fd)
      return true
    end
  end

  -- If we can't get the lock, proceed anyway (best effort)
  return true
end

function Store:release_lock()
  pcall(uv.fs_unlink, self.lock_file)
end

function Store:load()
  -- Simplified loading without locking for now
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
  return true
end

function Store:save()
  -- Simplified saving without locking for now
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
    return true
  end

  return false
end

function Store:rebuild_index()
  self.item_index = {}
  for i, entry in ipairs(self.mru_list) do
    self.item_index[entry.item] = i
  end
end

--- Check if an item is a file path
---@param item string
---@return boolean
function Store:is_path(item)
  -- Simple heuristic: if it contains path separators and doesn't contain spaces at the beginning/end
  -- or if it's an absolute path, treat it as a path
  if vim.startswith(item, "/") or vim.startswith(item, "~") then
    return true
  end
  if item:match("^%s") or item:match("%s$") then
    return false
  end
  return item:find("[/\\]") ~= nil
end

--- Normalize a path for consistent storage
---@param path string
---@return string
function Store:normalize_path(path)
  if not self:is_path(path) then
    return path
  end
  
  -- Use the same normalization as the picker system
  local normalized = vim.fs.normalize(path)
  
  -- For consistency, always store absolute paths for actual file paths
  if not vim.startswith(normalized, "/") then
    normalized = vim.fn.fnamemodify(normalized, ":p")
  end
  
  return normalized
end

--- Add an item to the frecency list
---@param item string # path or arbitrary text
function Store:remember(item)
  if not item or item == "" then
    return false
  end

  -- Normalize the item
  local normalized_item = self:normalize_path(item)
  local is_path = self:is_path(item)
  
  local now = os.time()
  local existing_idx = self.item_index[normalized_item]

  if existing_idx then
    -- Remove existing entry
    table.remove(self.mru_list, existing_idx)
  end

  -- Add to front
  table.insert(self.mru_list, 1, {
    item = normalized_item,
    timestamp = now,
    is_path = is_path
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

--- Get recent files only (ignoring non-paths), sorted by recency
---@return string[] # list of file paths, most recent first
function Store:get_recent_files()
  local files = {}
  for _, entry in ipairs(self.mru_list) do
    if entry.is_path then
      table.insert(files, entry.item)
    end
  end
  return files
end

--- Get all recent items (both paths and non-paths), sorted by recency
---@return snacks.frecency.Entry[] # list of entries, most recent first
function Store:get_recent_items()
  return vim.deepcopy(self.mru_list)
end

function Store:close()
  self:save()
end

-- Initialize the store
function M.setup()
  if M.store then
    return
  end
  
  M.store = Store.new(store_file)

  local group = vim.api.nvim_create_augroup("snacks_frecency", {})
  vim.api.nvim_create_autocmd("ExitPre", {
    group = group,
    callback = function()
      if M.store then
        M.store:close()
        M.store = nil
      end
    end,
  })
end

--- Get recent files only (ignoring non-paths), sorted by recency
---@return string[] # list of file paths, most recent first
function M.get_recent_files()
  assert(M.store, "Snacks.frecency is not initialized. Call Snacks.frecency.setup() first.")
  return M.store:get_recent_files()
end

--- Remember an item (path or arbitrary text)
---@param text_or_path string
---@return boolean # true if successfully saved
function M.remember(text_or_path)
  assert(M.store, "Snacks.frecency is not initialized. Call Snacks.frecency.setup() first.")
  return M.store:remember(text_or_path)
end

--- Get all recent items (both paths and non-paths), sorted by recency
---@return snacks.frecency.Entry[] # list of entries, most recent first
function M.get_recent_items()
  assert(M.store, "Snacks.frecency is not initialized. Call Snacks.frecency.setup() first.")
  return M.store:get_recent_items()
end

-- Expose Store class for testing
M.Store = Store

return M

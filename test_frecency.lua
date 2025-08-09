-- Simple test for the frecency module
-- This test will be run inside Neovim

-- Mock some vim functions for testing
if not vim then
  vim = {
    fn = {
      stdpath = function() return "/tmp" end,
      getpid = function() return 12345 end,
      mkdir = function() end,
      fnamemodify = function(path, mod) return path end,
      has = function() return 1 end,
      system = function() return "" end,
    },
    fs = {
      normalize = function(path) return path end,
    },
    startswith = function(str, prefix) return str:sub(1, #prefix) == prefix end,
    wait = function() end,
    json = {
      encode = function(t) return "{}" end,
      decode = function(s) return {} end,
    },
    api = {
      nvim_create_augroup = function() return 1 end,
      nvim_create_autocmd = function() end,
    },
    uv = {
      hrtime = function() return 1000000000 end, -- 1 second in nanoseconds
      fs_open = function(path, flags)
        if flags == "wx" then return 123 end -- simulate successful lock creation
        return 456 -- simulate file open
      end,
      fs_unlink = function() return true end,
      fs_stat = function() return nil end,
      fs_fstat = function() return { size = 0 } end,
      fs_read = function() return "" end,
      fs_write = function() return true end,
      fs_close = function() return true end,
    },
    v = { shell_error = 0 },
    deepcopy = function(t) return t end,
  }
end

print("Testing Snacks frecency module...")

-- Load the module
local ok, frecency = pcall(require, "lua.snacks.frecency")
if not ok then
  print("Error loading module:", frecency)
  return
end

print("Module loaded successfully!")

-- Test the Store class directly
local Store = frecency.Store
local store = Store.new("/tmp/test_frecency.json")

print("\n1. Testing Store:is_path() function:")
print("'/home/user/test.txt' is path:", store:is_path("/home/user/test.txt"))
print("'~/documents/readme.md' is path:", store:is_path("~/documents/readme.md"))
print("'some search query' is path:", store:is_path("some search query"))
print("'src/main.lua' is path:", store:is_path("src/main.lua"))

print("\n2. Testing Store:normalize_path() function:")
print("Normalize '/home/user/test.txt':", store:normalize_path("/home/user/test.txt"))
print("Normalize 'some search query':", store:normalize_path("some search query"))

print("\nTest completed!")

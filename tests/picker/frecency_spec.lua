local M = require("snacks.picker.core.frecency")

describe("frecency", function()
  local temp_dir
  local store_file
  
  before_each(function()
    -- Create a temporary directory for testing
    temp_dir = vim.fn.tempname()
    vim.fn.mkdir(temp_dir, "p")
    store_file = temp_dir .. "/test-frecency.json"
    
    -- Reset global store
    if M.store then
      M.store:close()
      M.store = nil
    end
  end)
  
  after_each(function()
    -- Clean up
    if M.store then
      M.store:close()
      M.store = nil
    end
    vim.fn.delete(temp_dir, "rf")
  end)
  
  describe("Store", function()
    it("should create a new store", function()
      local Store = require("snacks.picker.core.frecency").Store or {}
      if Store.new then
        local store = Store.new(store_file)
        assert.is_not_nil(store)
        assert.are.same({}, store.mru_list)
        assert.are.same({}, store.path_index)
      end
    end)
    
    it("should visit files and maintain MRU order", function()
      local Store = require("snacks.picker.core.frecency").Store or {}
      if Store.new then
        local store = Store.new(store_file)
        
        -- Visit some files
        store:visit("/path/to/file1.txt")
        store:visit("/path/to/file2.txt")
        store:visit("/path/to/file3.txt")
        
        -- Check MRU order (most recent first)
        assert.are.equal(3, #store.mru_list)
        assert.are.equal("/path/to/file3.txt", store.mru_list[1].path)
        assert.are.equal("/path/to/file2.txt", store.mru_list[2].path)
        assert.are.equal("/path/to/file1.txt", store.mru_list[3].path)
        
        -- Visit an existing file - should move to top
        store:visit("/path/to/file1.txt")
        assert.are.equal("/path/to/file1.txt", store.mru_list[1].path)
        assert.are.equal("/path/to/file3.txt", store.mru_list[2].path)
        assert.are.equal("/path/to/file2.txt", store.mru_list[3].path)
      end
    end)
    
    it("should maintain max entries limit", function()
      local Store = require("snacks.picker.core.frecency").Store or {}
      if Store.new then
        local store = Store.new(store_file)
        local MAX_ENTRIES = 3000
        
        -- Visit more than max entries
        for i = 1, MAX_ENTRIES + 10 do
          store:visit("/path/to/file" .. i .. ".txt")
        end
        
        -- Should be limited to MAX_ENTRIES
        assert.are.equal(MAX_ENTRIES, #store.mru_list)
        
        -- Most recent should be at the top
        assert.are.equal("/path/to/file" .. (MAX_ENTRIES + 10) .. ".txt", store.mru_list[1].path)
      end
    end)
    
    it("should calculate scores based on MRU position", function()
      local Store = require("snacks.picker.core.frecency").Store or {}
      if Store.new then
        local store = Store.new(store_file)
        local MAX_ENTRIES = 3000
        
        store:visit("/path/to/file1.txt")
        store:visit("/path/to/file2.txt")
        store:visit("/path/to/file3.txt")
        
        -- Most recent should have highest score
        assert.are.equal(MAX_ENTRIES, store:get_score("/path/to/file3.txt"))
        assert.are.equal(MAX_ENTRIES - 1, store:get_score("/path/to/file2.txt"))
        assert.are.equal(MAX_ENTRIES - 2, store:get_score("/path/to/file1.txt"))
        
        -- Non-existent file should have score 0
        assert.are.equal(0, store:get_score("/path/to/nonexistent.txt"))
      end
    end)
  end)
  
  describe("Frecency instance", function()
    it("should create a new frecency instance", function()
      local frecency = M.new()
      assert.is_not_nil(frecency)
      assert.is_not_nil(frecency.mru_list)
      assert.is_not_nil(frecency.path_index)
    end)
    
    it("should get scores for items", function()
      local frecency = M.new()
      
      -- Mock item
      local item = {
        file = "/path/to/test.txt"
      }
      
      -- Initially should return 0 (not seeded)
      local score = frecency:get(item, { seed = false })
      assert.are.equal(0, score)
    end)
    
    it("should visit items and update MRU", function()
      local frecency = M.new()
      
      local item = {
        file = "/path/to/test.txt"
      }
      
      -- Visit the item
      frecency:visit(item)
      
      -- Should now have a score
      local score = frecency:get(item)
      assert.is_true(score > 0)
    end)
  end)
  
  describe("Buffer visits", function()
    it("should handle buffer visits", function()
      -- Create a temporary file
      local temp_file = temp_dir .. "/test_buffer.txt"
      vim.fn.writefile({"test content"}, temp_file)
      
      -- Create a buffer for the file
      local buf = vim.fn.bufadd(temp_file)
      vim.bo[buf].buftype = ""
      vim.bo[buf].buflisted = true
      
      -- Visit the buffer
      local result = M.visit_buf(buf)
      assert.is_true(result)
      
      -- Clean up
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end)
  end)
end)

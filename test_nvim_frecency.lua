-- Test the frecency module within Neovim
print("Testing Snacks frecency module in Neovim...")

-- Load the module directly first
local ok, frecency = pcall(require, "snacks.frecency")
if not ok then
  print("Error loading frecency module:", frecency)
  return
end

print("Module loaded successfully!")

-- Test basic functionality
print("\n1. Testing remember() function:")
local result1 = frecency.remember("/home/user/test.txt")
print("Remembering file path result:", result1)

local result2 = frecency.remember("some search query")
print("Remembering non-path text result:", result2)

-- Test getting recent files
print("\n2. Testing get_recent_files():")
local recent_files = frecency.get_recent_files()
print("Recent files count:", #recent_files)
for i, file in ipairs(recent_files) do
  print("  " .. i .. ": " .. file)
end

print("\nTest completed successfully!")

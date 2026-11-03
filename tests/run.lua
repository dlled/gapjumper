-- Test runner: lua tests/run.lua, from the repository root.
-- Exits non-zero if any check fails or any test file raises an error.

package.path = "./?.lua;./?/init.lua;" .. package.path

T = { passed = 0, failed = 0 }

function T.check(name, condition, detail)
  if condition then
    T.passed = T.passed + 1
  else
    T.failed = T.failed + 1
    print("FAIL " .. name .. (detail and (": " .. tostring(detail)) or ""))
  end
end

function T.frame(name, x, y, w, h)
  return { name = name, x = x, y = y, x2 = x + w, y2 = y + h }
end

local FILES = {
  "tests/geometry_test.lua",
  "tests/layouts_test.lua",
  "tests/property_test.lua",
  "tests/runtime_test.lua",
}

-- A file that errors counts as one failure; the remaining files still run.
for _, file in ipairs(FILES) do
  local ok, err = xpcall(dofile, debug.traceback, file)
  T.check("loads " .. file, ok, err)
end

print(string.format("lua: %d checks, %d failures", T.passed + T.failed, T.failed))
os.exit(T.failed == 0 and 0 or 1)

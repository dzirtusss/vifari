-- spec/helpers_spec.lua
-- Unit tests for vifari helper functions using Busted

_G.hs = {
  timer = {
    absoluteTime = function() return 0 end,
  },
  fnutils = {
    -- needed by mergeConfigs
    copy = function(tbl)
      local out = {}
      for k,v in pairs(tbl) do out[k] = v end
      return out
    end,
  },
  -- You can stub more here if you end up invoking other hs.* methods
}

local vifari = require "vifari"
local helpers = vifari.helpers

describe("vifari helpers", function()
  describe("tblContains", function()
    it("returns true when the value is present", function()
      assert.is_true(helpers.tblContains({1, 2, 3}, 2))
    end)
    it("returns false when the value is missing", function()
      assert.is_false(helpers.tblContains({"a", "b"}, "c"))
    end)
  end)

  describe("mergeConfigs", function()
    local defaultCfg = { foo = 1, bar = { x = 1, y = 2 } }
    local userCfg = { bar = { y = 3 }, baz = 4 }
    local merged = helpers.mergeConfigs(defaultCfg, userCfg)

    it("keeps default fields not overridden", function()
      assert.equal(1, merged.foo)
    end)
    it("merges nested tables correctly", function()
      assert.equal(1, merged.bar.x)
      assert.equal(3, merged.bar.y)
    end)
    it("adds new fields from userConfig", function()
      assert.equal(4, merged.baz)
    end)
  end)

  describe("generateCombinations", function()
    local combos = helpers.generateCombinations()

    it("generates 676 two-letter combos", function()
      assert.equal(26 * 26, #combos)
    end)
    it("starts with 'aa'", function()
      assert.equal("aa", combos[1])
    end)
    it("ends with 'zz'", function()
      assert.equal("zz", combos[#combos])
    end)
  end)

  describe("fetchMappingPrefixes", function()
    it("extracts only first letters of two-char keys with truthy values", function()
      local mapping = {
        ab = "cmdFoo",
        c = "cmdBar",
        de = false,
        fg = { "cmd", "Baz" }
      }
      local prefixes = helpers.fetchMappingPrefixes(mapping)

      -- 'a' comes from "ab" and value is truthy
      assert.is_true(prefixes["a"], "expected prefix 'a' to be present")
      -- 'f' comes from "fg"
      assert.is_true(prefixes["f"], "expected prefix 'f' to be present")
      -- 'd' from "de" with false value should be absent
      assert.is_nil(prefixes["d"], "expected prefix 'd' to be absent because value is false")
      -- 'c' is single-char key, should not appear
      assert.is_nil(prefixes["c"], "expected prefix 'c' to be absent")
    end)
  end)

  describe("acceptableChars pattern", function()
    local pat = helpers.acceptableChars

    it("matches letters and digits", function()
      for _, c in ipairs({ 'a', 'Z', '5' }) do
        assert.is_not_nil(c:match(pat), "expected '" .. c .. "' to match acceptableChars")
      end
    end)
    it("matches bracket, dollar, quote and backspace", function()
      for _, c in ipairs({ '[', ']', '$', '"', "'", string.char(0x7f) }) do
        assert.is_not_nil(c:match(pat), "expected char to match acceptableChars: '" .. tostring(c) .. "'")
      end
    end)
    it("does not match punctuation like dot", function()
      assert.is_nil(('.'):match(pat), "expected '.' to not match acceptableChars")
    end)
  end)
end)

# -*- encoding : ascii-8bit -*-

require "spec_helper"

describe "ABI string[][] encoding and decoding" do
  it "encodes and decodes simple string[][] correctly" do
    type = "string[][]"
    data = [["hello", "world"], ["foo", "bar", "baz"]]

    encoded = Abi.encode([type], [data])
    decoded = Abi.decode([type], encoded)

    expect(decoded).to eq([data])
  end

  it "handles empty outer array" do
    type = "string[][]"
    data = []

    encoded = Abi.encode([type], [data])
    decoded = Abi.decode([type], encoded)

    expect(decoded).to eq([data])
  end

  it "handles empty inner arrays" do
    type = "string[][]"
    data = [[], ["single"], []]

    encoded = Abi.encode([type], [data])
    decoded = Abi.decode([type], encoded)

    expect(decoded).to eq([data])
  end

  it "handles array with single empty inner array" do
    type = "string[][]"
    data = [[]]

    encoded = Abi.encode([type], [data])
    decoded = Abi.decode([type], encoded)

    expect(decoded).to eq([data])
  end

  it "handles array with empty strings" do
    type = "string[][]"
    data = [["", ""], ["test", ""]]

    encoded = Abi.encode([type], [data])
    decoded = Abi.decode([type], encoded)

    expect(decoded).to eq([data])
  end

  it "handles large nested arrays" do
    type = "string[][]"
    data = [
      ["a", "b", "c", "d", "e"],
      ["1", "2", "3"],
      ["alpha", "beta", "gamma", "delta"],
      ["x"],
      []
    ]

    encoded = Abi.encode([type], [data])
    decoded = Abi.decode([type], encoded)

    expect(decoded).to eq([data])
  end

  it "handles unicode strings in nested arrays" do
    type = "string[][]"
    data = [["hello 世界", "emoji 🚀"], ["test 测试"]]

    encoded = Abi.encode([type], [data])
    decoded = Abi.decode([type], encoded)

    expect(decoded).to eq([data])
  end

  it "correctly calculates offsets for variable-length inner arrays" do
    type = "string[][]"
    # Different sized inner arrays to test offset calculation
    data = [
      ["short"],
      ["this is a much longer string that should affect offsets"],
      ["mid"],
      ["another", "array", "with", "multiple", "elements"]
    ]

    encoded = Abi.encode([type], [data])
    decoded = Abi.decode([type], encoded)

    expect(decoded).to eq([data])
  end

  it "works as part of complex type combinations" do
    types = ["uint256", "string[][]", "bool"]
    data = [
      42,
      [["hello", "world"], ["foo"]],
      true
    ]

    encoded = Abi.encode(types, data)
    decoded = Abi.decode(types, encoded)

    expect(decoded).to eq(data)
  end

  it "handles string[][] alongside other dynamic types" do
    types = ["string[][]", "bytes", "uint256[]"]
    data = [
      [["a", "b"], ["c"]],
      "\x01\x02\x03",
      [100, 200, 300]
    ]

    encoded = Abi.encode(types, data)
    decoded = Abi.decode(types, encoded)

    expect(decoded).to eq(data)
  end

  describe "edge cases" do
    it "handles very long strings in nested arrays" do
      type = "string[][]"
      long_string = "x" * 1000
      data = [[long_string], ["short", long_string]]

      encoded = Abi.encode([type], [data])
      decoded = Abi.decode([type], encoded)

      expect(decoded).to eq([data])
    end

    it "rejects invalid encoded data with wrong offsets" do
      type = "string[][]"
      # Create invalid data with self-referential offsets
      # The outer offset points to position 32 (0x20)
      invalid_data = "\x00" * 31 + "\x20" + # offset to outer array at position 32
                    "\x00" * 31 + "\x02" + # outer array length = 2
                    "\x00" * 31 + "\x40" + # first inner array offset at 64 (should be >= 96)
                    "\x00" * 31 + "\x40"   # second inner array offset (same, invalid)

      expect { Abi.decode([type], invalid_data) }.to raise_error(Abi::DecodingError)
    end

    it "rejects data with out-of-bounds offsets" do
      type = "string[][]"
      # Create data with offset pointing beyond data end
      invalid_data = "\x00" * 31 + "\x20" + # offset to array data
                    "\x00" * 31 + "\x01" + # length = 1
                    "\xFF" * 32  # offset way out of bounds

      expect { Abi.decode([type], invalid_data) }.to raise_error(Abi::DecodingError)
    end
  end

  describe "comparison with existing uint256[][] test" do
    it "follows same encoding pattern as uint256[][]" do
      # Based on existing test in abi_spec.rb
      uint_types = ["uint256[][]"]
      uint_data = [[[1, 2], [3]]]

      string_types = ["string[][]"]
      string_data = [[["1", "2"], ["3"]]]

      # Both should encode to similar structures (different content but same offset pattern)
      uint_encoded = Abi.encode(uint_types, uint_data)
      string_encoded = Abi.encode(string_types, string_data)

      # Verify both decode correctly
      expect(Abi.decode(uint_types, uint_encoded)).to eq(uint_data)
      expect(Abi.decode(string_types, string_encoded)).to eq(string_data)
    end
  end

  describe "regressions" do
    it "decodes inner dynamic arrays using next-pointer boundaries (was mis-sliced)" do
      # This specifically catches the old bug where decoding string[][] computed
      # an element's size from the inner length word (count of inner items)
      # instead of using the next element's pointer (or end of region). That
      # code would either raise DecodingError or return corrupted values for
      # inner arrays with more than one element.
      type = "string[][]"
      data = [["a", "bb"], ["ccc", "dddd"]]

      encoded = Abi.encode([type], [data])
      decoded = Abi.decode([type], encoded)

      expect(decoded).to eq([data])
    end
  end
end

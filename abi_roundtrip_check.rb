#!/usr/bin/env ruby

$LOAD_PATH.unshift File.expand_path("lib", __dir__)
# Require only what we need to avoid optional client deps
require "eth/constant"
require "eth/rlp"
require "eth/util"
require "eth/address"
require "eth/abi"
require "pp"

# Tiny ABI encode/decode round-trip check for your structs.
#
# Notes:
# - Uses the library decoder first (fixed in this patch).
# - Keeps a minimal manual tuple decoder for comparison and debugging.

# Define TokenParams type
token_params_type = Eth::Abi::Type.parse("tuple", [
  { "type" => "string",  "name" => "op" },
  { "type" => "string",  "name" => "protocol" },
  { "type" => "string",  "name" => "tick" },
  { "type" => "uint256", "name" => "max" },
  { "type" => "uint256", "name" => "lim" },
  { "type" => "uint256", "name" => "amt" }
])

# Define CreateEthscriptionParams type (with nested TokenParams)
create_type = Eth::Abi::Type.parse("tuple", [
  { "type" => "bytes32", "name" => "transactionHash" },
  { "type" => "address", "name" => "initialOwner" },
  { "type" => "bytes",   "name" => "contentUri" },
  { "type" => "string",  "name" => "mimetype" },
  { "type" => "string",  "name" => "mediaType" },
  { "type" => "string",  "name" => "mimeSubtype" },
  { "type" => "bool",    "name" => "esip6" },
  { "type" => "bool",    "name" => "isCompressed" },
  { "type" => "tuple",   "name" => "tokenParams", "components" => token_params_type.components.map { |c|
      { "type" => c.to_s, "name" => c.name }
    }
  }
])

# Sample data
token_params_data = {
  "op"       => "deploy",
  "protocol" => "erc-20",
  "tick"     => "TEST",
  "max"      => 1_000_000,
  "lim"      => 1_000,
  "amt"      => 0
}

tx_hash = [ ("0x" + "a" * 64).delete_prefix("0x") ].pack("H*")

create_ethscription_data = {
  "transactionHash" => tx_hash,
  "initialOwner"    => "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb9",
  "contentUri"      => 'data:application/json,{"test":"data"}'.b,  # bytes
  "mimetype"        => "application/json",
  "mediaType"       => "application",
  "mimeSubtype"     => "json",
  "esip6"           => true,
  "isCompressed"    => false,
  "tokenParams"     => token_params_data
}

# Encode
enc = Eth::Abi.encode([create_type], [create_ethscription_data])
hex = "0x" + Eth::Util.bin_to_hex(enc)

# Print encoded hex for inspection
puts "hex=#{hex}"

# Try library decode (may fail with mixed dynamic tuple bug)
dec = nil
begin
  dec = Eth::Abi.decode([create_type], hex).first
rescue => e
  warn "lib_decode_error=#{e.class}: #{e.message}"
end

if dec
  re_enc = Eth::Abi.encode([create_type], [dec])
  puts "roundtrip_ok=#{enc == re_enc}"
end

# Optional: pretty-print decoded as a Hash by component names
def tuple_array_to_hash(type, ary)
  type.components.each_with_index.map do |c, i|
    val = c.base_type == "tuple" ? tuple_array_to_hash(c, ary[i]) : ary[i]
    [c.name, val]
  end.to_h
end

if dec
  pp tuple_array_to_hash(create_type, dec)
end

# Manual tuple decoder that correctly handles mixed static/dynamic fields
def decode_tuple_manual(type, tuple_bin)
  n = type.components.size
  # Read head words (n * 32 bytes)
  head_words = (0...n).map { |i| tuple_bin[i * 32, 32] }
  results = Array.new(n)
  head_offset = 0

  # Helper to big-endian uint
  to_uint = ->(bytes) { Eth::Util.deserialize_big_endian_to_int(bytes) }

  # Determine slice boundaries for dynamic components by looking at next dynamic offset
  dynamic_indices = type.components.each_index.select { |i| type.components[i].dynamic? }

  # Build next-offset lookup for dynamic components
  next_offset_for = {}
  dynamic_indices.each_with_index do |i, idx|
    this_off = to_uint.call(head_words[i])
    next_off = if idx + 1 < dynamic_indices.length
      to_uint.call(head_words[dynamic_indices[idx + 1]])
    else
      tuple_bin.size
    end
    next_offset_for[i] = [this_off, next_off]
  end

  type.components.each_with_index do |comp, i|
    if comp.dynamic?
      ptr, nxt = next_offset_for[i]
      slice = tuple_bin[ptr, nxt - ptr]
      if comp.base_type == "tuple"
        results[i] = decode_tuple_manual(comp, slice)
      else
        results[i] = Eth::Abi::Decoder.type(comp, slice)
      end
      head_offset += 32
    else
      size = comp.size
      slice = tuple_bin[head_offset, size]
      results[i] = Eth::Abi::Decoder.type(comp, slice)
      head_offset += size
    end
  end

  results
end

# Perform manual decode to avoid tuple mixed-dynamic bug
tuple_offset = Eth::Util.deserialize_big_endian_to_int(enc[0, 32])
tuple_bin = enc[tuple_offset..]
manual_dec = decode_tuple_manual(create_type, tuple_bin)

re_enc2 = Eth::Abi.encode([create_type], [manual_dec])
puts "roundtrip_manual_ok=#{enc == re_enc2}"

pp tuple_array_to_hash(create_type, manual_dec)

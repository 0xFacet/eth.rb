# Copyright (c) 2016-2025 The Ruby-Eth Contributors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# -*- encoding : ascii-8bit -*-

# Provides the {Eth} module.
module Eth

  # Provides a Ruby implementation of the Ethereum Application Binary Interface (ABI).
  module Abi

    # Provides a utility module to assist decoding ABIs.
    module Decoder
      extend self

      # Decodes a specific value, either static or dynamic.
      #
      # @param type [Eth::Abi::Type] type to be decoded.
      # @param arg [String] encoded type data string.
      # @return [String] the decoded data for the type.
      # @raise [DecodingError] if decoding fails for type.
      def type(type, arg)
        if %w(string bytes).include?(type.base_type) and type.sub_type.empty?
          # Case: decoding a string/bytes
          if type.dimensions.empty?
            l = Util.deserialize_big_endian_to_int arg[0, 32]
            data = arg[32..-1]
            raise DecodingError, "Wrong data size for string/bytes object" unless data.size == Util.ceil32(l)

            # decoded strings and bytes
            data[0, l]
            # Case: decoding array of string/bytes
          else
            l = Util.deserialize_big_endian_to_int arg[0, 32]
            raise DecodingError, "Wrong data size for dynamic array" unless arg.size >= 32 + 32 * l

            # Decode each element of the array
            (1..l).map do |i|
              pointer = Util.deserialize_big_endian_to_int arg[i * 32, 32] # Pointer to the size of the array's element
              raise DecodingError, "Offset out of bounds" if pointer < 32 * l || pointer > arg.size - 64
              data_l = Util.deserialize_big_endian_to_int arg[32 + pointer, 32] # length of the element
              raise DecodingError, "Offset out of bounds" if pointer + 32 + Util.ceil32(data_l) > arg.size
              type(Type.parse(type.base_type), arg[pointer + 32, Util.ceil32(data_l) + 32])
            end
          end
        elsif type.base_type == "tuple" && type.dimensions.empty?
          # Decode tuple by first determining head positions for all components.
          # For dynamic components, the head contains a 32-byte offset pointer
          # into the tuple tail. The "next" boundary for a dynamic component is
          # the next dynamic component's pointer (or the end of the tuple), not
          # simply the next 32-byte head word, because static components inline
          # their data in the head and may span multiple 32-byte words.

          raise DecodingError, "Cannot decode tuples without known components" if type.components.nil?

          # First pass: compute head offsets for each component and total head size.
          head_offsets = []
          head_pos = 0
          type.components.each do |comp|
            head_offsets << head_pos
            if comp.dynamic?
              head_pos += 32
            else
              size = comp.size
              head_pos += size
            end
          end
          heads_size = head_pos

          # Build dynamic component indices and their pointers.
          dynamic_indices = []
          dynamic_pointers = []
          type.components.each_with_index do |comp, i|
            next unless comp.dynamic?
            dynamic_indices << i
            ptr = Util.deserialize_big_endian_to_int(arg[head_offsets[i], 32])
            # ABI guarantees dynamic pointers point into the tail (>= heads_size)
            raise DecodingError, "Offset out of bounds" if ptr < heads_size || ptr > arg.size
            dynamic_pointers << ptr
          end
          # Map component index -> dynamic index for O(1) lookup
          dyn_index_map = {}
          dynamic_indices.each_with_index { |ci, di| dyn_index_map[ci] = di }

          # Second pass: decode each component using correct slicing.
          result = []
          type.components.each_with_index do |comp, i|
            if comp.dynamic?
              # Determine this component's pointer and next boundary.
              idx_in_dynamic = dyn_index_map[i]
              pointer = dynamic_pointers[idx_in_dynamic]
              next_pointer = if idx_in_dynamic + 1 < dynamic_indices.length
                dynamic_pointers[idx_in_dynamic + 1]
              else
                arg.size
              end
              raise DecodingError, "Offset out of bounds" if pointer > arg.size || next_pointer > arg.size || next_pointer < pointer
              slice = arg[pointer, next_pointer - pointer]
              result << type(comp, slice)
            else
              size = comp.size
              offset = head_offsets[i]
              raise DecodingError, "Offset out of bounds" if offset + size > arg.size
              result << type(comp, arg[offset, size])
            end
          end
          result
        elsif type.dynamic?
          l = Util.deserialize_big_endian_to_int arg[0, 32]
          nested_sub = type.nested_sub

          if nested_sub.dynamic?
            raise DecodingError, "Wrong data size for dynamic array" unless arg.size >= 32 + 32 * l
            offsets = (0...l).map do |i|
              off = Util.deserialize_big_endian_to_int arg[32 + 32 * i, 32]
              raise DecodingError, "Offset out of bounds" if off < 32 * l || off > arg.size - 32
              off
            end
            offsets.each_with_index.map do |off, i|
              next_off = (i + 1 < offsets.length ? offsets[i + 1] : (arg.size - 32))
              raise DecodingError, "Offset out of bounds" if next_off < off || next_off > arg.size - 32
              type(nested_sub, arg[32 + off, next_off - off])
            end
          else
            raise DecodingError, "Wrong data size for dynamic array" unless arg.size >= 32 + nested_sub.size * l
            # decoded dynamic-sized arrays with static sub-types
            (0...l).map { |i| type(nested_sub, arg[32 + nested_sub.size * i, nested_sub.size]) }
          end
        elsif !type.dimensions.empty?
          l = type.dimensions.first
          nested_sub = type.nested_sub

          if nested_sub.dynamic?
            raise DecodingError, "Wrong data size for static array" unless arg.size >= 32 * l
            offsets = (0...l).map do |i|
              off = Util.deserialize_big_endian_to_int arg[32 * i, 32]
              raise DecodingError, "Offset out of bounds" if off < 32 * l || off > arg.size - 32
              off
            end
            offsets.each_with_index.map do |off, i|
              size = (i + 1 < offsets.length ? offsets[i + 1] : arg.size) - off
              type(nested_sub, arg[off, size])
            end
          else
            # decoded static-size arrays with static sub-types
            (0...l).map { |i| type(nested_sub, arg[nested_sub.size * i, nested_sub.size]) }
          end
        else

          # decoded primitive types
          primitive_type type, arg
        end
      end

      # Decodes primitive types.
      #
      # @param type [Eth::Abi::Type] type to be decoded.
      # @param data [String] encoded primitive type data string.
      # @return [String] the decoded data for the type.
      # @raise [DecodingError] if decoding fails for type.
      def primitive_type(type, data)
        case type.base_type
        when "address"

          # decoded address with 0x-prefix
          Address.new(Util.bin_to_hex data[12..-1]).to_s.downcase
        when "string", "bytes"
          if type.sub_type.empty?
            size = Util.deserialize_big_endian_to_int data[0, 32]

            # decoded dynamic-sized array
            decoded = data[32..-1][0, size]
            decoded.force_encoding(Encoding::UTF_8)
            decoded
          else

            # decoded static-sized array
            data[0, type.sub_type.to_i]
          end
        when "hash"

          # decoded hash
          data[(32 - type.sub_type.to_i), type.sub_type.to_i]
        when "uint"

          # decoded unsigned integer
          Util.deserialize_big_endian_to_int data
        when "int"
          u = Util.deserialize_big_endian_to_int data
          i = u >= 2 ** (type.sub_type.to_i - 1) ? (u - 2 ** 256) : u

          # decoded integer
          i
        when "ureal", "ufixed"
          high, low = type.sub_type.split("x").map(&:to_i)

          # decoded unsigned fixed point numeric
          Util.deserialize_big_endian_to_int(data) * 1.0 / 2 ** low
        when "real", "fixed"
          high, low = type.sub_type.split("x").map(&:to_i)
          u = Util.deserialize_big_endian_to_int data
          i = u >= 2 ** (high + low - 1) ? (u - 2 ** (high + low)) : u

          # decoded fixed point numeric
          i * 1.0 / 2 ** low
        when "bool"

          # decoded boolean
          data[-1] == Constant::BYTE_ONE
        else
          raise DecodingError, "Unknown primitive type: #{type.base_type}"
        end
      end
    end
  end
end

require "spec_helper"

RSpec.describe Eth::Abi::Decoder do
  it "decodes tuples mixing dynamic and static components" do
    token_params_type = Eth::Abi::Type.parse("tuple", [
      { "type" => "string",  "name" => "op" },
      { "type" => "string",  "name" => "protocol" },
      { "type" => "string",  "name" => "tick" },
      { "type" => "uint256", "name" => "max" },
      { "type" => "uint256", "name" => "lim" },
      { "type" => "uint256", "name" => "amt" },
    ])

    create_type = Eth::Abi::Type.parse("tuple", [
      { "type" => "bytes32", "name" => "transactionHash" },
      { "type" => "address", "name" => "initialOwner" },
      { "type" => "bytes",   "name" => "contentUri" },
      { "type" => "string",  "name" => "mimetype" },
      { "type" => "string",  "name" => "mediaType" },
      { "type" => "string",  "name" => "mimeSubtype" },
      { "type" => "bool",    "name" => "esip6" },
      { "type" => "bool",    "name" => "isCompressed" },
      { "type" => "tuple",   "name" => "tokenParams", "components" => token_params_type.components.map { |c| { "type" => c.to_s, "name" => c.name } } },
    ])

    token_params_data = {
      "op" => "deploy",
      "protocol" => "erc-20",
      "tick" => "TEST",
      "max" => 1_000_000,
      "lim" => 1_000,
      "amt" => 0,
    }

    tx_hash = [ ("0x" + "a" * 64).delete_prefix("0x") ].pack("H*")
    create_data = {
      "transactionHash" => tx_hash,
      "initialOwner" => "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb9",
      "contentUri" => 'data:application/json,{"test":"data"}'.b,
      "mimetype" => "application/json",
      "mediaType" => "application",
      "mimeSubtype" => "json",
      "esip6" => true,
      "isCompressed" => false,
      "tokenParams" => token_params_data,
    }

    enc = Eth::Abi.encode([create_type], [create_data])
    dec = Eth::Abi.decode([create_type], enc).first

    # Round-trip
    re_enc = Eth::Abi.encode([create_type], [dec])
    expect(re_enc).to eq(enc)

    # Spot-check a few fields
    expect(dec[0]).to eq(tx_hash)
    expect(dec[1]).to eq("0x742d35cc6634c0532925a3b844bc9e7595f0beb9")
    expect(dec[2]).to eq('data:application/json,{"test":"data"}')
    expect(dec[3]).to eq("application/json")
    expect(dec[8][0]).to eq("deploy")
    expect(dec[8][3]).to eq(1_000_000)
  end
end


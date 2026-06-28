require "test_helper"

class Vassal::PieceTest < ActiveSupport::TestCase
  def parse_fixture(name)
    text = file_fixture("piece_slots/#{name}").read
    command = Vassal::Piece::AddCommand.parse(text)
    Vassal::Piece.parse_traits(command.type, command.state)
  end

  test "parses a wargame counter with prototypes and a layer (Salerno)" do
    traits = parse_fixture("salerno_emb2.txt")

    prototypes = traits.select { |t| t["kind"] == "prototype" }.map { |t| t["name"] }
    assert_includes prototypes, "AL Combat Unit"
    assert_includes prototypes, "US Combat Unit"

    layer = traits.find { |t| t["kind"] == "layer" }
    assert_equal [ "US-3-7-Regt-f.png", "US-3-7-Regt-r.png" ], layer["images"]
    assert_equal 1, layer["value"]

    basic = traits.last
    assert_equal "basic", basic["kind"]
    assert_equal "US-3-7-Regt-f.png", basic["image"]
    assert_equal "US 3/7 Inf Regt", basic["name"], "escaped slash in the name survives"
    assert_equal "2383", basic["gpid"]
    assert_equal({ "ppScale" => "1.0" }, basic["properties"])
  end

  test "parses a card with marker value from state (Here I Stand)" do
    traits = parse_fixture("his_card.txt")

    marker = traits.find { |t| t["kind"] == "marker" }
    assert_equal({ "CP" => "2" }, marker["properties"])

    assert_includes traits.map { |t| t["name"] }, "BasicCard"

    basic = traits.last
    assert_equal "HIS-010.svg", basic["image"]
    assert_equal "Clement VII", basic["name"]

    unknown = traits.select { |t| t["kind"] == "unknown" }
    assert unknown.any?, "unsupported traits degrade to unknown without raising"
  end

  test "parses the card mask trait (Here I Stand prototype)" do
    traits = parse_fixture("his_mask_prototype.txt")

    mask = traits.find { |t| t["kind"] == "mask" }
    assert_equal "cardback.svg", mask["back_image"]
    assert_equal "cardback.svg", mask["others_image"]
    assert_equal "G", mask["display_style"]
  end

  test "parses a legacy module counter (GBoH)" do
    traits = parse_fixture("gboh_legacy_emb.txt")

    basic = traits.last
    assert_equal "Armenian-Cat-HI-A.gif", basic["image"]
    assert_equal "Armenian Cataphract HI", basic["name"]

    layer = traits.find { |t| t["kind"] == "layer" }
    assert_includes layer["images"], "Armenian-Cat-HI-B.gif"
  end

  test "an emb2 layer reads its value from the state and defaults to not-always-active (GBoH leader)" do
    # A GBoH leader "Finished" marker: an old-format emb2 type that ends before
    # the always-active field, and a ";"-terminated state token of "-1".
    type = "emb2;Finished;0;F;;0;;;0;;Reset;;1;false;0;0;Finished-Nanda.gif;;true;Finished;;;false;;1"
    layer = Vassal::Piece::TraitRegistry.parse(type, "-1;")

    assert_equal "layer", layer["kind"]
    assert_equal "Finished", layer["name"]
    assert_equal(-1, layer["value"], "value is the leading ;-delimited int, not Integer of the whole token")
    assert_equal false, layer["always_active"], "a truncated type is not always active (VASSAL's default)"
  end

  test "never raises on garbage" do
    traits = Vassal::Piece.parse_traits("what;is;this\tgarbage", "x\ty")
    assert(traits.all? { |t| t["kind"] == "unknown" })
  end
end

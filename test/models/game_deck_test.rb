require "test_helper"
require "turbo/broadcastable/test_helper"

class GameDeckTest < ActiveSupport::TestCase
  include VmodTestHelper
  include Turbo::Broadcastable::TestHelper

  setup do
    @game_module = create_card_module!
    ModuleImportJob.perform_now(@game_module)
    @game_module.reload
    @scenario = @game_module.scenarios.find_by(kind: "module_setup")
    @game = Game.create!(game_module: @game_module, scenario: @scenario, creator: users(:one), name: "T")
    @game.players.create!(user: users(:one), side: "Bando A")
  end

  teardown do
    FileUtils.rm_rf(Rails.root.join("tmp", "vassal-test", Process.pid.to_s))
  end

  test "materialize_decks! creates in-deck cards with shuffled positions" do
    @game.materialize_decks!
    deck = @game_module.decks.find_by(name: "Mazo")
    cards = @game.game_pieces.in_deck(deck)

    assert_equal 3, cards.count
    assert_equal [ 0, 1, 2 ], cards.pluck(:deck_position).sort
    assert cards.all? { |c| c.in_deck? && !c.on_map? && !c.in_hand? }
  end

  test "copy_scenario_pieces! turns hand-map pieces into hand cards" do
    hand_map = @game_module.game_maps.kind_player_hand.first
    @scenario.scenario_pieces.create!(game_map: hand_map, name: "Carta secreta",
                                      type_string: "x", traits: [ { "kind" => "basic", "image" => "card1.png" } ])
    @game.copy_scenario_pieces!

    hand_card = @game.game_pieces.find_by(name: "Carta secreta")
    assert hand_card.in_hand?
    assert_equal "Bando A", hand_card.hand_side
    assert_nil hand_card.game_map_id

    unit = @game.game_pieces.find_by(name: "Unidad")
    assert unit.on_map?, "ordinary map pieces stay on the map"
  end

  test "a piece can be in only one place" do
    deck = @game_module.decks.first
    piece = @game.game_pieces.new(name: "x", deck: deck, deck_position: 0, hand_side: "Bando A")
    assert_not piece.valid?
    assert_match(/one place/, piece.errors.full_messages.to_sentence)
  end

  test "in-deck cards broadcast nothing; in-hand cards broadcast only to their side stream" do
    @game.materialize_decks!
    card = @game.game_pieces.where.not(deck_id: nil).first

    # In deck: a trait change is silent on every stream
    assert_no_turbo_stream_broadcasts(@game) do
      assert_no_turbo_stream_broadcasts([ @game, "Bando A" ]) do
        card.update!(traits: card.traits)
      end
    end

    # Move to a hand: broadcasts only to that side
    assert_no_turbo_stream_broadcasts(@game) do
      assert_turbo_stream_broadcasts([ @game, "Bando A" ], count: 1) do
        card.update!(deck_id: nil, deck_position: nil, hand_side: "Bando A")
      end
    end
  end
end

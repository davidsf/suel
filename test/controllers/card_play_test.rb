require "test_helper"
require "turbo/broadcastable/test_helper"

class CardPlayTest < ActionDispatch::IntegrationTest
  include VmodTestHelper
  include Turbo::Broadcastable::TestHelper

  setup do
    @game_module = create_card_module!
    ModuleImportJob.perform_now(@game_module)
    @game_module.reload
    scenario = @game_module.scenarios.find_by(kind: "module_setup")
    @game = Game.create!(game_module: @game_module, scenario:, creator: users(:one), name: "T")
    @game.copy_scenario_pieces!
    @game.materialize_decks!
    @game.players.create!(user: users(:one), side: "Bando A")
    @map = @game_module.game_maps.find_by(name: "Mesa")
    @deck = @game_module.decks.find_by(name: "Mazo")
    # Give Bando A a card in hand
    @card = @game.game_pieces.in_deck(@deck).first
    @card.update!(deck_id: nil, deck_position: nil, hand_side: "Bando A")
  end

  teardown do
    FileUtils.rm_rf(Rails.root.join("tmp", "vassal-test", Process.pid.to_s))
  end

  test "the owner plays a hand card onto the map face up" do
    sign_in_as users(:one)
    patch play_game_piece_path(@game, @card), params: { map: @map.id, x: 300, y: 200 }
    assert_response :success

    @card.reload
    assert @card.on_map?
    assert_nil @card.hand_side
    assert_equal @map.id, @card.game_map_id
    mask = @card.traits.find { |t| t["kind"] == "mask" }
    assert_nil mask["obscured_by"], "played cards land face up"
    assert_equal "deck", GameEvent.last.kind
    assert_match(/plays/, GameEvent.last.body)
  end

  test "another side cannot play my hand card" do
    @game.players.create!(user: users(:two), side: "Bando B")
    sign_in_as users(:two)
    patch play_game_piece_path(@game, @card), params: { map: @map.id, x: 0, y: 0 }
    assert_response :forbidden
    assert @card.reload.in_hand?
  end

  test "the owner discards a hand card to a deck" do
    sign_in_as users(:one)
    discard = @game_module.decks.find_by(name: "Descartes")
    assert_difference -> { @game.game_pieces.in_deck(discard).count }, 1 do
      patch discard_game_piece_path(@game, @card), params: { deck: discard.id }
    end
    assert_response :success
    assert @card.reload.in_deck?
  end

  test "a map piece can be discarded to a deck by any player" do
    @game.players.create!(user: users(:two), side: "Bando B")
    @card.play_to!(@map, 300, 200) # now on the map
    discard = @game_module.decks.find_by(name: "Descartes")

    sign_in_as users(:two) # not the original owner
    assert_difference -> { @game.game_pieces.in_deck(discard).count }, 1 do
      patch discard_game_piece_path(@game, @card), params: { deck: discard.id }
    end
    assert_response :success
    assert @card.reload.in_deck?
  end

  test "another player's hand cards never reach my page" do
    # Bando B joins and views the table
    @game.players.create!(user: users(:two), side: "Bando B")
    sign_in_as users(:two)
    get game_path(@game)
    assert_response :success
    assert_no_match(/hand_game_piece_#{@card.id}/, response.body, "B must not receive A's hand card node")
    assert_no_match(/#{@card.name}/, response.body, "B must not see A's card name")
  end

  test "the owner sees their own hand cards" do
    sign_in_as users(:one)
    get game_path(@game)
    assert_match(/hand_game_piece_#{@card.id}/, response.body)
    assert_match(/#{@card.name}/, response.body)
  end
end

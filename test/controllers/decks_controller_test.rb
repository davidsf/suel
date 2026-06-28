require "test_helper"
require "turbo/broadcastable/test_helper"

class DecksControllerTest < ActionDispatch::IntegrationTest
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
    @deck = @game_module.decks.find_by(name: "Mazo")
    @discard = @game_module.decks.find_by(name: "Descartes")
    @hand_deck = @game_module.decks.find_by(name: "Robo A")
  end

  teardown do
    FileUtils.rm_rf(Rails.root.join("tmp", "vassal-test", Process.pid.to_s))
  end

  test "a player draws the top card into their hand" do
    sign_in_as users(:one)

    assert_difference -> { @game.game_pieces.in_hand("Bando A").count }, 1 do
      assert_turbo_stream_broadcasts([ @game, "Bando A" ], count: 1) do
        post draw_game_deck_path(@game, @deck)
      end
    end
    assert_response :success
    assert_equal 2, @game.game_pieces.in_deck(@deck).count
    assert_equal "deck", GameEvent.last.kind
    assert_no_match(/Diplomacia|Asalto|Refuerzo/, GameEvent.last.body, "draw must not reveal the card")
  end

  test "a player draws by dragging a card onto the table" do
    sign_in_as users(:one)
    map = @game_module.game_maps.find_by(name: "Mesa")

    assert_difference -> { @game.game_pieces.on_map.count }, 1 do
      assert_no_difference -> { @game.game_pieces.in_hand("Bando A").count } do
        assert_turbo_stream_broadcasts(@game) do
          post draw_game_deck_path(@game, @deck), params: { map: map.id, x: 410, y: 305 }
        end
      end
    end
    assert_response :no_content
    assert_equal 2, @game.game_pieces.in_deck(@deck).count

    card = @game.game_pieces.on_map.detect { |p| %w[Diplomacia Asalto Refuerzo].include?(p.name) }
    assert card, "the drawn card is on the table"
    # Mazo is drawFaceUp: the chit is revealed (mask cleared) and named in the log.
    assert_nil card.traits.find { |t| t["kind"] == "mask" }["obscured_by"]
    assert_match(/Diplomacia|Asalto|Refuerzo/, GameEvent.last.body)
  end

  test "spectators cannot draw" do
    sign_in_as users(:two)
    post draw_game_deck_path(@game, @deck)
    assert_response :forbidden
  end

  test "a side cannot draw from another side's hand deck" do
    @game.players.create!(user: users(:two), side: "Bando B")
    sign_in_as users(:two)
    post draw_game_deck_path(@game, @hand_deck) # hand deck belongs to Bando A
    assert_response :forbidden
  end

  test "reshuffle moves the discard into its target and shuffles" do
    # Put a card in the discard pile first
    card = @game.game_pieces.in_deck(@deck).first
    card.discard_to!(@discard)
    assert_equal 1, @game.game_pieces.in_deck(@discard).count

    sign_in_as users(:one)
    post reshuffle_game_deck_path(@game, @discard)
    assert_response :no_content
    assert_equal 0, @game.game_pieces.in_deck(@discard).count
    assert_equal 3, @game.game_pieces.in_deck(@deck).count
  end

  test "reshuffle on a non-reshufflable deck is rejected" do
    sign_in_as users(:one)
    post reshuffle_game_deck_path(@game, @deck) # Mazo is not reshufflable
    assert_response :unprocessable_entity
  end
end

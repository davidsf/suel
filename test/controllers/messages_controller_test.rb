require "test_helper"
require "turbo/broadcastable/test_helper"

class MessagesControllerTest < ActionDispatch::IntegrationTest
  include VmodTestHelper
  include Turbo::Broadcastable::TestHelper

  setup do
    @game_module = create_game_module!
    ModuleImportJob.perform_now(@game_module)
    scenario = @game_module.reload.scenarios.create!(name: "Setup", kind: "module_setup", status: "ready")
    @game = Game.create!(game_module: @game_module, scenario: scenario,
                         creator: users(:one), name: "Prueba")
    @game.players.create!(user: users(:one), side: "Bando A")
  end

  teardown do
    FileUtils.rm_rf(Rails.root.join("tmp", "vassal-test", Process.pid.to_s))
  end

  test "a player chats under their side name and the message is broadcast" do
    sign_in_as users(:one)

    streams = capture_turbo_stream_broadcasts(@game) do
      post game_messages_path(@game), params: { body: "¡Buena suerte!" }
    end
    assert_response :no_content
    assert_equal "Bando A: ¡Buena suerte!", GameEvent.last.body
    assert GameEvent.last.chat_kind?

    # Prepend: newest-first DOM + the log's column-reverse = newest at the
    # bottom, by the chat input.
    assert_equal 1, streams.size
    assert_equal "prepend", streams.first["action"]
    assert_equal "game_log", streams.first["target"]
  end

  test "spectators chat under their user name" do
    sign_in_as users(:two)
    post game_messages_path(@game), params: { body: "hola" }
    assert_match(/\Atwo: hola\z/, GameEvent.last.body)
  end

  test "blank messages are rejected" do
    sign_in_as users(:one)
    assert_no_difference "GameEvent.count" do
      post game_messages_path(@game), params: { body: "   " }
    end
    assert_response :unprocessable_entity
  end

  test "anonymous users are redirected" do
    post game_messages_path(@game), params: { body: "x" }
    assert_redirected_to new_session_path
  end
end

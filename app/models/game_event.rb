class GameEvent < ApplicationRecord
  belongs_to :game
  belongs_to :user, optional: true

  enum :kind, { roll: "roll", chat: "chat" }, default: "roll", suffix: true

  validates :body, presence: true

  after_create_commit :broadcast_append

  private

  def broadcast_append
    broadcast_append_to game, target: "game_log",
      partial: "game_events/game_event", locals: { game_event: self }
  end
end

class GameEvent < ApplicationRecord
  belongs_to :game
  belongs_to :user, optional: true

  enum :kind, { roll: "roll", chat: "chat", deck: "deck" }, default: "roll", suffix: true

  validates :body, presence: true

  after_create_commit :broadcast_prepend

  private

  # Prepend: the log DOM runs newest-first and the CSS column-reverse paints
  # it bottom-up, keeping the scroll pinned to the newest entry by the input.
  def broadcast_prepend
    broadcast_prepend_to game, target: "game_log",
      partial: "game_events/game_event", locals: { game_event: self }
  end
end

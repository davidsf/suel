module DecksHelper
  # Top-of-deck traits for the marker: face-down decks show the back to
  # everyone (force the mask obscured), face-up decks show the top card front.
  # Returns nil when the deck is empty.
  def deck_top_traits(game, deck)
    card = game.top_card(deck) or return nil
    if deck.face_down?
      forced = card.traits.deep_dup
      mask = forced.find { |t| t["kind"] == "mask" }
      mask["obscured_by"] = "deck" if mask
      displayed_traits(forced)
    else
      card.traits
    end
  end
end

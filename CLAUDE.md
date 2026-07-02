# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**Suel** is a Rails 8.1 web app that reads [VASSAL](https://vassalengine.org/)
`.vmod` modules (ZIP archives of board-game definitions) and serves them as an
interactive, real-time game table in the browser — no Java, no desktop client.
The hard part is a dependency-free **pure-Ruby port of the relevant parts of
VASSAL's Java file format**, living in `lib/vassal/`.

Ruby 3.3.7, Rails 8.1, SQLite (via the `solid_*` adapters — cache, queue and
cable all on SQLite, no Redis), Hotwire (Turbo + Stimulus) over import maps,
Propshaft assets.

## Commands

```bash
bin/dev                   # run Puma + background workers (Solid Queue); http://localhost:3000
bin/setup --skip-server   # install gems + prepare the DB without booting
bin/rails db:seed         # create the admin user (admin@example.com / password; override via ADMIN_EMAIL/ADMIN_PASSWORD)

bin/rails test                              # unit & integration tests
bin/rails test test/lib/vassal/piece_test.rb        # a single file
bin/rails test test/lib/vassal/piece_test.rb:42     # a single test by line
bin/rails test:system     # Capybara + Selenium system tests (not run in CI by default)

bin/rubocop               # Omakase Ruby style
bin/brakeman              # static security analysis
bin/bundler-audit         # known-vulnerable gem check
bin/ci                    # full CI suite locally (see config/ci.rb)
```

Tests run in parallel and load `fixtures :all`. `libvips` is an optional system
dependency (`ruby-vips` is lazy-loaded via `require: false`); the app boots
without it but module import reads image metadata better with it installed.

## Architecture

### The VASSAL reader (`lib/vassal/`) — start here

This is the conceptually dense part. Read the source comments; they cite the
exact VASSAL Java classes being ported.

- **`module_archive.rb`** opens the `.vmod` ZIP. **`build_file.rb`** +
  `build_file/game_module_reader.rb` parse `buildFile` (XML whose element names
  are VASSAL Java class names) into a generic `Node` tree; unknown elements are
  kept verbatim so callers can degrade gracefully.
- **`sequence_encoder.rb`** is an exact port of VASSAL's `SequenceEncoder` —
  it decodes the dense delimited TYPE/STATE strings that encode pieces.
- **`piece.rb`** — a piece's traits are a **recursive** encoding (each decorator
  wraps the whole inner piece as one escaped token, outermost first), *not* a
  flat list. `split_traits`/`join_traits` peel and rebuild one level at a time.
  `piece/trait_registry.rb` decodes each individual trait into a plain
  JSON-ready hash; unparseable traits become `kind "unknown"` — graceful
  degradation is the contract, parsing **never raises**.
- **`piece/prototype_expander.rb`** inlines prototype references; `piece/add_command.rb`
  handles the `+/id/TYPE/STATE` AddPiece command form.
- **`save_file.rb`** + **`obfuscation.rb`** read `.vsav` saved games, including
  VASSAL's `!VCSK` XOR obfuscation.
- **`images.rb`** reads image metadata (lazily requires `ruby-vips`).
- **`grid_*.rb`** — hex/square grid location, numbering and snapping.

**Standard, not per-game**: implement mechanics to the VASSAL/vmod standard,
driven by module attributes parsed from the buildFile — never hardcode behavior
for a specific game.

### Import pipeline

Uploading a module enqueues **`ModuleImportJob`** (Solid Queue), which extracts
the ZIP to a flat on-disk dir (`storage/vassal/modules/<id>/`), parses
`moduledata` and the buildFile, and delegates to
`app/services/game_module_importer.rb` to persist maps, boards, scenarios,
piece definitions, prototypes and decks. On success it sets the module's
`status` to `ready` (states flow `extracting` → `parsing` → `ready`/`failed`).
Module images are **not** Active Storage blobs — they're served straight off
disk by `ModuleAssetsController` with immutable caching.

### Real-time game table

A `Game` is started from a `Scenario`. `Game#copy_scenario_pieces!` copies the
scenario's placed `ScenarioPiece`s into mutable `GamePiece`s; `materialize_decks!`
turns deck definitions into in-deck pieces (shuffled unless the module says
otherwise).

A `GamePiece` is in exactly one place — on a map, in a deck, or in a player's
hand (`game_map_id` / `deck_id` / `hand_side`, enforced by `one_location_at_most`).
Mutations go through model methods (`move_to!`, `flip!`, `rotate!`,
`play_to!`, `discard_to!`, …) that bundle changes into a single `update!` so the
`after_update_commit` broadcast fires once. `traits` is the JSON-serialized
trait list; piece state lives there (e.g. the `mask`, `rotate`, `layer` traits).

Updates reach clients via **Turbo Streams over Action Cable** (Solid Cable):
`games/show` subscribes with `turbo_stream_from @game` and, for the signed-in
player, `turbo_stream_from @game, @player.side` (a per-side private stream so
hands don't leak). Models broadcast replacements/appends to these streams.
`GameEvent` (rolls / chat / deck events) appends to the shared `game_log`.

Controllers for table actions are thin REST endpoints (`game_pieces`, `decks`,
`rolls`, `messages`, `players`) nested under `games` — see `config/routes.rb`.
The client side is Stimulus: **`game_table_controller.js`** orchestrates
drag/select/toolbars and composes with **`pan_zoom_controller.js`** (maps are
panned/zoomed with CSS transforms; grids drawn as an SVG overlay).

`BoardLayout` (`app/models/board_layout.rb`) maps a piece's map-space pixel
coordinates to the board/zone/grid cell under it (per the `.vsav` BoardPicker
selection), which is how snapping and location names work.

## Conventions

- Don't do custom add hoc code for any module behaviour. Instead try to see how is done in VASSAL. 
- Auth is a hand-rolled session model (`app/controllers/concerns/authentication.rb`,
  `Current`, `Session`); module upload/management is admin-only under `Admin::`.
- The VASSAL reader has no Rails dependencies — keep it that way; it's plain Ruby
  under `lib/vassal/` and tested under `test/lib/vassal/`.
- User-facing strings go through Rails i18n: English is the source language
  (`config/locales/en.yml`) with a Spanish translation (`es.yml`); the locale is
  picked per request from the browser's `Accept-Language`
  (`ApplicationController#switch_locale`). Game-table strings needed by Stimulus
  are passed via the `data-game-table-i18n-value` JSON. Code and comments are
  English.

# Suel

A web-based viewer and real-time play table for [VASSAL](https://vassalengine.org/)
modules (`.vmod` files). Upload a module and play it in the browser — no Java,
no desktop client — with maps, boards, hex/square grids, pieces, decks, dice and
chat shared live between players.

*([README en castellano](README_es.md))*

## What it does

VASSAL is a Java engine for playing board games online. Its modules (`.vmod`,
which are just ZIP archives) bundle the board images, piece graphics, rules
metadata and scenarios for a given game. **Suel** reads those modules
directly — reimplementing the parts of VASSAL's file format in pure Ruby — and
serves them as an interactive web table.

- **Module library** — browse uploaded modules, their maps/boards, the piece
  palette and the bundled scenarios.
- **Module viewer** — pan/zoom maps rendered with CSS transforms, with the hex
  or square grid drawn as an SVG overlay.
- **Live game table** — start a game from a scenario; the scenario's placed
  pieces are copied into a mutable board you and other players manipulate
  together over Action Cable. Move, flip, rotate and re-layer pieces; draw,
  shuffle and reshuffle decks; play cards from a private hand; roll the module's
  dice buttons; and chat. Every action is broadcast live to everyone at the
  table.

### How it works under the hood

The interesting work lives in `lib/vassal/`, a dependency-free Ruby port of the
relevant slices of the VASSAL Java source:

- `module_archive.rb` / `build_file/` reads the `.vmod` ZIP and parses its
  `buildFile` (the module definition tree).
- `sequence_encoder.rb` is an exact port of VASSAL's `SequenceEncoder`, used to
  decode the densely-packed piece TYPE/STATE strings. Piece traits are a
  *recursive* encoding (decorator pairs), not a flat list — they're peeled one
  layer at a time.
- `piece/` expands prototypes and applies traits to build concrete pieces.
- `save_file.rb` / `obfuscation.rb` reads `.vsav` saved games, including
  VASSAL's `!VCSK` XOR obfuscation.
- `images.rb` pulls image metadata. Module images are extracted to a flat
  directory on disk (`storage/vassal/modules/<id>/`) and served by
  `ModuleAssetsController` with immutable caching — they are **not** stored as
  per-image Active Storage blobs.

Uploading a module enqueues `ModuleImportJob`, which extracts the archive,
parses the build tree and scenarios into the database, and flips the module's
status to `ready`.

## Tech stack

- **Ruby 3.3** + **Rails 8.1**
- **SQLite** (via the `solid_*` adapters for cache, queue and cable — no Redis
  or separate services needed)
- **Hotwire** (Turbo + Stimulus) over import maps, **Propshaft** asset pipeline
- **Puma**, with **Solid Queue** running background jobs and **Solid Cable**
  driving the real-time table
- `rubyzip` to read modules; `ruby-vips` (loaded lazily) for image metadata

## Requirements

- Ruby 3.3.7 (see `.ruby-version`)
- `libvips` on the host for image metadata. `ruby-vips` is loaded lazily
  (`require: false`), so the app boots without it, but module imports work best
  with it installed:
  - Debian/Ubuntu: `sudo apt install libvips`
  - macOS: `brew install vips`

## Installation

```bash
git clone <repo-url> suel
cd suel

# Install gems and prepare the database in one step
bin/setup

# Create the default admin user (admin@example.com / password)
bin/rails db:seed
```

`bin/setup` installs dependencies, prepares the SQLite database and (by default)
starts the dev server. To set things up without booting the server, run
`bin/setup --skip-server`.

### Running

```bash
bin/dev
```

This starts Puma and the background workers. Open <http://localhost:3000>.

1. Sign in as the seeded admin (`admin@example.com` / `password`).
2. Upload a `.vmod` module from the admin section; wait for the import to finish
   (status → *ready*).
3. Browse the module, or start a game from one of its scenarios and invite
   others to the table.

Override the seeded admin credentials with the `ADMIN_EMAIL` and
`ADMIN_PASSWORD` environment variables.

### Tests

```bash
bin/rails test            # unit & integration tests
bin/rails test:system     # system tests (Capybara + Selenium)
```

### Linting & security

```bash
bin/rubocop               # Omakase Ruby style
bin/brakeman              # static security analysis
bin/bundler-audit         # known-vulnerable gem check
bin/ci                    # run the full CI suite locally
```

## Deployment

A `Dockerfile` is included, so the app can be built and run as a container.
The Rails default Kamal scaffolding (`config/deploy.yml`, `.kamal/`) is also
present but **not yet configured** — there are no servers or registry set up.
Fill in `config/deploy.yml` and the secrets before attempting a Kamal deploy.

Because cache, jobs and Action Cable all run on SQLite via the `solid_*`
adapters, a single container with a persistent volume for `storage/` is enough —
no external Redis or database server is required.

## Status

The pure-Ruby module reader and viewer are in place, along with the real-time
game table (games, players, pieces, decks, dice and chat over Action Cable).
Modules are uploaded by an admin and imported asynchronously.

## Notes

VASSAL and its modules are the work of the [VASSAL
project](https://vassalengine.org/) and the respective module authors.
Suel only reads existing modules; it does not create or distribute them.

The name *Suel* is the ancient Roman town that stood on the hill of Fuengirola
(Málaga, Spain), where the author is from.

Yes, this was built with AI — Claude Fable (during the two days it was publicly
available) and Opus ever since.

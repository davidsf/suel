module VmodTestHelper
  # Builds an in-memory minimal .vmod and returns it as an uploaded file blob.
  def build_vmod(entries)
    io = StringIO.new
    Zip::OutputStream.write_buffer(io) do |zip|
      entries.each do |name, content|
        zip.put_next_entry(name)
        zip.write content
      end
    end
    io.rewind
    io
  end

  def create_game_module!(entries = default_vmod_entries)
    game_module = GameModule.new
    game_module.package.attach(io: build_vmod(entries), filename: "mini.vmod", content_type: "application/zip")
    game_module.save!
    game_module
  end

  def default_vmod_entries
    {
      "buildFile.xml" => %(<?xml version="1.0"?><VASSAL.build.GameModule name="Mini" version="1.0" VassalVersion="3.7.0"/>),
      "moduledata" => %(<?xml version="1.0"?><data version="1"><name>Mini Module</name><version>1.0</version><VassalVersion>3.7.0</VassalVersion><description>Test module</description></data>),
      "images/board.png" => "fake-image-bytes"
    }
  end

  # Synthetic card-game module: a map with a face-down draw deck, a discard
  # pile that reshuffles into it, an at-start stack (so a ready module_setup
  # scenario exists), a player hand for "Bando A", and a hand deck for the
  # side-authorization test.
  def create_card_module!
    create_game_module!(card_vmod_entries)
  end

  def card_vmod_entries
    {
      "buildFile.xml" => card_build_file,
      "moduledata" => %(<?xml version="1.0"?><data version="1"><name>Cartas</name><version>1.0</version><VassalVersion>3.7.0</VassalVersion></data>),
      "images/board.png" => "fake", "images/back.png" => "fake",
      "images/card1.png" => "fake", "images/card2.png" => "fake", "images/card3.png" => "fake",
      "images/unit.png" => "fake", "images/crt.gif" => "fake", "images/terrain.gif" => "fake",
      "batalla.vsav" => card_vsav
    }
  end

  # A tiny obfuscated .vsav (empty command stream) referenced by a
  # PredefinedSetup, so the importer can name the scenario after the setup.
  def card_vsav
    inner = StringIO.new
    Zip::OutputStream.write_buffer(inner) do |zip|
      zip.put_next_entry("savedGame")
      zip.write Vassal::Obfuscation.obfuscate("begin_save\eend_save")
      zip.put_next_entry("savedata")
      zip.write "<?xml version='1.0'?><data><description>Batalla</description></data>"
    end
    inner.string
  end

  # A module with a square-gridded map and an (empty) hidden-units deck, for
  # exercising the command bus (reveal). Pieces are added by the test directly.
  def create_reveal_module!
    create_game_module!(
      "buildFile.xml" => reveal_build_file,
      "moduledata" => %(<?xml version="1.0"?><data version="1"><name>Reveal</name><version>1.0</version><VassalVersion>3.7.0</VassalVersion></data>),
      "images/board.png" => "fake"
    )
  end

  def reveal_build_file
    <<~XML
      <?xml version="1.0"?>
      <VASSAL.build.GameModule name="Reveal" version="1.0" VassalVersion="3.7.0">
        <VASSAL.build.module.PlayerRoster><entry>GE</entry><entry>AL</entry></VASSAL.build.module.PlayerRoster>
        <VASSAL.build.module.Map mapName="Main Map">
          <VASSAL.build.module.map.BoardPicker>
            <VASSAL.build.module.map.boardPicker.Board name="Board1" image="board.png" width="600" height="400">
              <VASSAL.build.module.map.boardPicker.board.SquareGrid dx="60.0" dy="40.0" x0="30" y0="20" snapTo="true">
                <VASSAL.build.module.map.boardPicker.board.mapgrid.SquareGridNumbering hType="N" vType="N" hOff="1" vOff="1" hLeading="1" vLeading="1" sep="" first="H" hDescend="false" vDescend="false"/>
              </VASSAL.build.module.map.boardPicker.board.SquareGrid>
            </VASSAL.build.module.map.boardPicker.Board>
          </VASSAL.build.module.map.BoardPicker>
          <VASSAL.build.module.map.DrawPile name="Hidden" owningBoard="Board1" x="500" y="350" width="50" height="50" faceDown="Always" shuffle="Always"/>
          <VASSAL.build.module.map.SetupStack name="Start" owningBoard="Board1" x="300" y="200">
            <VASSAL.build.widget.PieceSlot entryName="Dummy" gpid="1" width="50" height="50">+/null/piece;;;board.png;Dummy/null;300;200;1;0</VASSAL.build.widget.PieceSlot>
          </VASSAL.build.module.map.SetupStack>
        </VASSAL.build.module.Map>
        <VASSAL.build.module.PieceWindow name="Markers">
          <VASSAL.build.widget.TabWidget entryName="Markers">
            <VASSAL.build.widget.ListWidget entryName="General">
              <VASSAL.build.widget.PieceSlot entryName="Status Marker" gpid="50" width="50" height="50">+/null/piece;;;board.png;Status Marker/null;0;0;50;0</VASSAL.build.widget.PieceSlot>
            </VASSAL.build.widget.ListWidget>
          </VASSAL.build.widget.TabWidget>
        </VASSAL.build.module.PieceWindow>
      </VASSAL.build.GameModule>
    XML
  end

  # A module with two real (kind: map) windows — "Main Map" and "Reinforcements"
  # — each a square-gridded board with an at-start stack, for exercising moving a
  # piece between maps (VASSAL's drag-between-windows).
  def create_two_map_module!
    create_game_module!(
      "buildFile.xml" => two_map_build_file,
      "moduledata" => %(<?xml version="1.0"?><data version="1"><name>TwoMap</name><version>1.0</version><VassalVersion>3.7.0</VassalVersion></data>),
      "images/board.png" => "fake"
    )
  end

  def two_map_build_file
    map = ->(map_name, board, stack, slot, gpid, x, y) do
      <<~MAP
        <VASSAL.build.module.Map mapName="#{map_name}">
          <VASSAL.build.module.map.BoardPicker>
            <VASSAL.build.module.map.boardPicker.Board name="#{board}" image="board.png" width="600" height="400">
              <VASSAL.build.module.map.boardPicker.board.SquareGrid dx="60.0" dy="40.0" x0="30" y0="20" snapTo="true">
                <VASSAL.build.module.map.boardPicker.board.mapgrid.SquareGridNumbering hType="N" vType="N" hOff="1" vOff="1" hLeading="1" vLeading="1" sep="" first="H" hDescend="false" vDescend="false"/>
              </VASSAL.build.module.map.boardPicker.board.SquareGrid>
            </VASSAL.build.module.map.boardPicker.Board>
          </VASSAL.build.module.map.BoardPicker>
          <VASSAL.build.module.map.SetupStack name="#{stack}" owningBoard="#{board}" x="#{x}" y="#{y}">
            <VASSAL.build.widget.PieceSlot entryName="#{slot}" gpid="#{gpid}" width="50" height="50">+/null/piece;;;board.png;#{slot}/null;#{x};#{y};#{gpid};0</VASSAL.build.widget.PieceSlot>
          </VASSAL.build.module.map.SetupStack>
        </VASSAL.build.module.Map>
      MAP
    end
    <<~XML
      <?xml version="1.0"?>
      <VASSAL.build.GameModule name="TwoMap" version="1.0" VassalVersion="3.7.0">
        <VASSAL.build.module.PlayerRoster><entry>Bando A</entry><entry>Bando B</entry></VASSAL.build.module.PlayerRoster>
        #{map.("Main Map", "Board1", "Start", "Dummy", 1, 300, 200)}
        #{map.("Reinforcements", "Board2", "Reinf", "Reinforcement", 2, 150, 100)}
      </VASSAL.build.GameModule>
    XML
  end

  # An Empire of the Sun-style module: one map window whose BoardPicker offers
  # two alternative boards (the player must choose at new game), plus a
  # SetupStack so a ready module_setup scenario (with empty board_setup) exists.
  def create_multi_board_module!
    create_game_module!(
      "buildFile.xml" => multi_board_build_file,
      "moduledata" => %(<?xml version="1.0"?><data version="1"><name>MultiBoard</name><version>1.0</version><VassalVersion>3.7.0</VassalVersion></data>),
      "images/board.png" => "fake", "images/board2.png" => "fake"
    )
  end

  def multi_board_build_file
    <<~XML
      <?xml version="1.0"?>
      <VASSAL.build.GameModule name="MultiBoard" version="1.0" VassalVersion="3.7.0">
        <VASSAL.build.module.PlayerRoster><entry>Bando A</entry><entry>Bando B</entry></VASSAL.build.module.PlayerRoster>
        <VASSAL.build.module.Map mapName="Main Map">
          <VASSAL.build.module.map.BoardPicker boardPrompt="Select board" title="Choose Boards">
            <VASSAL.build.module.map.boardPicker.Board name="Full Map" image="board.png" width="600" height="400"/>
            <VASSAL.build.module.map.boardPicker.Board name="Small Map" image="board2.png" width="300" height="200"/>
          </VASSAL.build.module.map.BoardPicker>
          <VASSAL.build.module.map.SetupStack name="Start" owningBoard="" x="100" y="100">
            <VASSAL.build.widget.PieceSlot entryName="Dummy" gpid="1" width="50" height="50">+/null/piece;;;board.png;Dummy/null;100;100;1;0</VASSAL.build.widget.PieceSlot>
          </VASSAL.build.module.map.SetupStack>
        </VASSAL.build.module.Map>
      </VASSAL.build.GameModule>
    XML
  end

  # A Holland '44-style module: a Main Map with pieces plus piece-less chart
  # map windows, two of them grouped under a ToolbarMenu "Charts &amp; Tables"
  # (matching by buttonName), one ungrouped, and a ToolbarMenu whose items
  # match nothing (VASSAL Inventory buttons we don't import).
  def create_chart_maps_module!
    create_game_module!(
      "buildFile.xml" => chart_maps_build_file,
      "moduledata" => %(<?xml version="1.0"?><data version="1"><name>Charts</name><version>1.0</version><VassalVersion>3.7.0</VassalVersion></data>),
      "images/board.png" => "fake"
    )
  end

  def chart_maps_build_file
    chart = ->(map_name, button_name, board) do
      <<~MAP
        <VASSAL.build.module.Map mapName="#{map_name}" buttonName="#{button_name}" launch="true" markMoved="Never">
          <VASSAL.build.module.map.BoardPicker>
            <VASSAL.build.module.map.boardPicker.Board name="#{board}" image="board.png" width="600" height="400"/>
          </VASSAL.build.module.map.BoardPicker>
        </VASSAL.build.module.Map>
      MAP
    end
    <<~XML
      <?xml version="1.0"?>
      <VASSAL.build.GameModule name="Charts" version="1.0" VassalVersion="3.7.0">
        <VASSAL.build.module.PlayerRoster><entry>Bando A</entry><entry>Bando B</entry></VASSAL.build.module.PlayerRoster>
        <VASSAL.build.module.Map mapName="Main Map" buttonName="Map" launch="false">
          <VASSAL.build.module.map.BoardPicker>
            <VASSAL.build.module.map.boardPicker.Board name="Board1" image="board.png" width="600" height="400"/>
          </VASSAL.build.module.map.BoardPicker>
          <VASSAL.build.module.map.SetupStack name="Start" owningBoard="Board1" x="300" y="200">
            <VASSAL.build.widget.PieceSlot entryName="Dummy" gpid="1" width="50" height="50">+/null/piece;;;board.png;Dummy/null;300;200;1;0</VASSAL.build.widget.PieceSlot>
          </VASSAL.build.module.map.SetupStack>
        </VASSAL.build.module.Map>
        #{chart.("Combat Results Table", "CRT (Alt+C)", "CRTBoard")}
        #{chart.("Terrain Effects Chart", "TEC (Alt+T)", "TECBoard")}
        #{chart.("Alternative Display", "", "AltBoard")}
        <VASSAL.build.module.ToolbarMenu description="Charts &amp; Tables" text="" tooltip="Charts &amp; Tables" icon="" menuItems="CRT (Alt+C),TEC (Alt+T)"/>
        <VASSAL.build.module.ToolbarMenu description="Unit Inventories" text="" tooltip="Unit Inventories" icon="" menuItems="Nothing Matches"/>
      </VASSAL.build.GameModule>
    XML
  end

  # An Empire of the Sun-style module with a toolbar "Setup" menu: a Main Map
  # (square grid, hidden-units deck) plus a module-level ToolbarMenu whose
  # entry is a GlobalKeyCommand that sends SetupGame to the control piece
  # whose BasicName fast-matches, and a second GKC that matches no menu.
  def create_setup_module!
    create_game_module!(
      "buildFile.xml" => setup_build_file,
      "moduledata" => %(<?xml version="1.0"?><data version="1"><name>Setup</name><version>1.0</version><VassalVersion>3.7.0</VassalVersion></data>),
      "images/board.png" => "fake"
    )
  end

  def setup_build_file
    reveal_build_file.sub("</VASSAL.build.GameModule>", <<~XML)
        <VASSAL.build.module.ToolbarMenu description="Setup Scenarios" text="" tooltip="Setup Scenarios" icon="" menuItems="Setup 1941"/>
        <VASSAL.build.module.GlobalKeyCommand name="1941 Campaign" buttonText="Setup 1941" tooltip="Setup the 1941 scenario" icon="" hotkey="57358,0,SetupGame" deckCount="0" filter="" reportFormat="" target="MODULE|false|MAP|Main Map||||0|0||true|{&quot;BasicName&quot;}|{&quot;Setup 1941 Scenario&quot;}|EQUALS||"/>
      </VASSAL.build.GameModule>
    XML
  end

  # Control piece for the setup chain: SetupGame triggers SetupPieces, which
  # broadcasts setup1941 to every on-map counter (COUNTER target, no deck).
  def setup_control_traits
    [
      { "kind" => "trigger", "key" => "named:SetupGame", "watch_keys" => [],
        "action_keys" => [ "named:SetupPieces" ] },
      { "kind" => "global_key", "key" => "named:SetupPieces", "global_key" => "named:setup1941",
        "count" => 0, "target" => "COUNTER|false|MAP|||||0|0||false|||EQUALS||" },
      { "kind" => "basic", "image" => "board.png", "name" => "Setup 1941 Scenario" }
    ]
  end

  # A unit that self-places to a grid cell when the scenario key arrives.
  def setup_unit_traits(cell, name: "Unit")
    [
      { "kind" => "send_to", "key" => "named:setup1941", "dest" => "G",
        "map" => "Main Map", "board" => "Board1", "grid_location" => cell },
      { "kind" => "basic", "image" => "board.png", "name" => name }
    ]
  end

  # The breadcrumb spec a PlaceMarker trait uses to point at the "Status Marker"
  # palette slot above (PieceWindow → TabWidget → ListWidget → PieceSlot).
  STATUS_MARKER_SPEC =
    "VASSAL.build.module.PieceWindow:Markers/VASSAL.build.widget.TabWidget:Markers/" \
    "VASSAL.build.widget.ListWidget:General/VASSAL.build.widget.PieceSlot:Status Marker".freeze

  # A unit whose "Mark" menu command (a TriggerAction) reports and then places a
  # Status Marker on itself (PlaceMarker), mirroring Holland '44's Disrupted etc.
  def marker_command_unit_traits(command_key: "key:68,585")
    [
      { "kind" => "trigger", "command" => "Mark", "key" => command_key, "watch_keys" => [],
        "action_keys" => [ "named:ReportMark", "named:Mark" ] },
      { "kind" => "place_marker", "key" => "named:Mark", "spec" => STATUS_MARKER_SPEC,
        "x_off" => 0, "y_off" => 0, "gpid" => "1474" },
      { "kind" => "report", "keys" => [ "named:ReportMark" ], "format" => "$location$: $newPieceName$ marked" },
      { "kind" => "basic", "image" => "board.png", "name" => "Unit" }
    ]
  end

  # Parsed-trait stacks for the reveal scenario: a marker that records its
  # location, draws from the "Hidden" deck and removes itself; and a unit that
  # sends itself to the recorded location when the relayed key arrives.
  def reveal_marker_traits(reveal_key: "key:70,130")
    [
      { "kind" => "trigger", "command" => "Reveal", "key" => reveal_key, "watch_keys" => [],
        "action_keys" => [ "named:SetLocation", "named:BringToMap", "named:Remove" ] },
      { "kind" => "set_property", "name" => "GEUnkLoc",
        "changes" => [ { "key" => "named:SetLocation", "op" => "P", "value" => "$LocationName$" } ] },
      { "kind" => "global_key", "key" => "named:BringToMap", "global_key" => "named:GEUnkPlacement",
        "deck" => "Hidden", "count" => 1 },
      { "kind" => "send_to", "key" => "named:Remove", "dest" => "L", "map" => "Main Map", "board" => "Board1",
        "x" => 510, "y" => 300 },
      { "kind" => "basic", "image" => "board.png", "name" => "Marker" }
    ]
  end

  def reveal_unit_traits
    [
      { "kind" => "trigger", "key" => "named:GEUnkPlacement", "watch_keys" => [],
        "action_keys" => [ "named:SendToMap", "named:ReportRevealed" ] },
      { "kind" => "send_to", "key" => "named:SendToMap", "dest" => "G", "map" => "Main Map",
        "board" => "Board1", "grid_location" => "$GEUnkLoc$" },
      { "kind" => "report", "keys" => [ "named:ReportRevealed" ], "format" => "$location$: $newPieceName$ revealed" },
      { "kind" => "basic", "image" => "board.png", "name" => "Real Unit" }
    ]
  end

  # A piece whose "Discard" menu command is a ReturnToDeck trait: to a fixed
  # deck-name expression, or prompting the player for one when select.
  def return_to_deck_traits(deck: nil, select: false)
    [
      { "kind" => "return_to_deck", "command" => "Discard", "key" => "key:68,130",
        "select" => select, "deck" => deck }.compact,
      { "kind" => "basic", "image" => "board.png", "name" => "Card" }
    ]
  end

  # A marker carrying VASSAL's lifecycle commands: Remove (Delete), Clone, and
  # "Change status" (Replace into the Status Marker), each a TriggerAction firing
  # a report then the lifecycle keystroke — mirroring Holland '44's markers.
  def lifecycle_marker_traits
    [
      { "kind" => "trigger", "command" => "Remove", "key" => "key:68,130", "watch_keys" => [],
        "action_keys" => [ "named:ReportRemoved", "named:Remove" ] },
      { "kind" => "trigger", "command" => "Clone", "key" => "key:67,130", "watch_keys" => [],
        "action_keys" => [ "named:ReportCloned", "named:Clone" ] },
      { "kind" => "trigger", "command" => "Change status", "key" => "key:70,130", "watch_keys" => [],
        "action_keys" => [ "named:ReportChange", "named:ChangeTo" ] },
      { "kind" => "delete", "key" => "named:Remove" },
      { "kind" => "clone", "key" => "named:Clone" },
      { "kind" => "replace", "key" => "named:ChangeTo", "spec" => STATUS_MARKER_SPEC, "x_off" => 0, "y_off" => 0 },
      { "kind" => "report", "keys" => [ "named:ReportRemoved" ], "format" => "$location$: $newPieceName$ removed" },
      { "kind" => "report", "keys" => [ "named:ReportCloned" ], "format" => "$location$: $newPieceName$ cloned" },
      { "kind" => "report", "keys" => [ "named:ReportChange" ], "format" => "$location$: $newPieceName$ changed" },
      { "kind" => "basic", "image" => "board.png", "name" => "Disrupted Marker" }
    ]
  end

  # A CardSlot/PieceSlot body: a mask trait wrapping a basic piece.
  def card_slot_text(image, name, gpid)
    "+/null/obs;F;back.png;Flip;I;?;\tpiece;;;#{image};#{name}/null\tnull;0;0;#{gpid};0"
  end

  def card_build_file
    cards = [ %w[card1.png Diplomacia 1], %w[card2.png Asalto 2], %w[card3.png Refuerzo 3] ]
      .map { |img, name, gpid| %(<VASSAL.build.widget.CardSlot entryName="#{name}" gpid="#{gpid}" width="50" height="70">#{card_slot_text(img, name, gpid)}</VASSAL.build.widget.CardSlot>) }
      .join
    <<~XML
      <?xml version="1.0"?>
      <VASSAL.build.GameModule name="Cartas" version="1.0" VassalVersion="3.7.0">
        <VASSAL.build.module.PlayerRoster>
          <entry>Bando A</entry>
          <entry>Bando B</entry>
        </VASSAL.build.module.PlayerRoster>
        <VASSAL.build.module.Map mapName="Mesa">
          <VASSAL.build.module.map.BoardPicker>
            <VASSAL.build.module.map.boardPicker.Board name="Tablero" image="board.png" width="800" height="600"/>
          </VASSAL.build.module.map.BoardPicker>
          <VASSAL.build.module.map.DrawPile name="Mazo" owningBoard="Tablero" x="100" y="100" width="50" height="70" faceDown="Always" drawFaceUp="true" shuffle="Always">
            #{cards}
          </VASSAL.build.module.map.DrawPile>
          <VASSAL.build.module.map.DrawPile name="Descartes" owningBoard="Tablero" x="200" y="100" width="50" height="70" faceDown="Never" reshufflable="true" reshuffleTarget="Mazo"/>
          <VASSAL.build.module.map.SetupStack name="Inicio" owningBoard="Tablero" x="400" y="300">
            <VASSAL.build.widget.PieceSlot entryName="Unidad" gpid="9" width="50" height="50">+/null/piece;;;unit.png;Unidad/null;400;300;9;0</VASSAL.build.widget.PieceSlot>
          </VASSAL.build.module.map.SetupStack>
        </VASSAL.build.module.Map>
        <VASSAL.build.module.PlayerHand side="Bando A" mapName="Mano A">
          <VASSAL.build.module.map.BoardPicker>
            <VASSAL.build.module.map.boardPicker.Board name="Mano A" width="800" height="200"/>
          </VASSAL.build.module.map.BoardPicker>
          <VASSAL.build.module.map.DrawPile name="Robo A" owningBoard="Mano A" x="50" y="50" width="50" height="70" faceDown="Never"/>
        </VASSAL.build.module.PlayerHand>
        <VASSAL.build.module.ChartWindow name="Tablas">
          <VASSAL.build.widget.TabWidget>
            <VASSAL.build.widget.Chart chartName="CRT" fileName="crt.gif"/>
            <VASSAL.build.widget.Chart chartName="Terreno" fileName="terrain.gif"/>
          </VASSAL.build.widget.TabWidget>
        </VASSAL.build.module.ChartWindow>
        <VASSAL.build.module.PredefinedSetup name="Escenarios" isMenu="true" useFile="true">
          <VASSAL.build.module.PredefinedSetup name="Batalla del Río" isMenu="false" useFile="true" file="batalla.vsav"/>
        </VASSAL.build.module.PredefinedSetup>
        <VASSAL.build.module.SpecialDiceButton name="Dado de combate" text="Combate">
          <VASSAL.build.module.SpecialDie name="Combate">
            <VASSAL.build.module.SpecialDieFace value="1" text="Fallo" icon="die-1.png"/>
            <VASSAL.build.module.SpecialDieFace value="2" text="Impacto" icon="die-2.png"/>
          </VASSAL.build.module.SpecialDie>
        </VASSAL.build.module.SpecialDiceButton>
      </VASSAL.build.GameModule>
    XML
  end
end

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
          <VASSAL.build.module.map.DrawPile name="Mazo" owningBoard="Tablero" x="100" y="100" width="50" height="70" faceDown="Always" shuffle="Always">
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
      </VASSAL.build.GameModule>
    XML
  end
end

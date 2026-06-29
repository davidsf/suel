require "test_helper"

# Parsing of the VASSAL command traits (TriggerAction, SendToLocation,
# CounterGlobalKeyCommand, SetGlobalProperty, RestrictCommands) that drive
# menu commands like Holland '44's "Reveal". Strings are taken verbatim from
# the module's buildFile.
class Vassal::CommandTraitsTest < ActiveSupport::TestCase
  def parse(type, state = "")
    Vassal::Piece::TraitRegistry.parse(type, state)
  end

  test "TriggerAction with a menu command and an action sequence" do
    t = parse("macro;Reveal;Reveal;70,130;;;57458\\,0\\,SetLocation,57459\\,0\\,BringToMap,57362\\,0\\,Remove,57368\\,0\\,MarkUnmoved;false;;;counted;;;;false;;1;1")
    assert_equal "trigger", t["kind"]
    assert_equal "Reveal", t["command"], "the right-click menu text"
    assert_equal "key:70,130", t["key"]
    assert_equal %w[named:SetLocation named:BringToMap named:Remove named:MarkUnmoved], t["action_keys"]
    assert_empty t["watch_keys"]
  end

  test "TriggerAction triggered by a named keystroke has no menu command" do
    t = parse("macro;Initial Placement;;57462,0,GEUnkPlacement;;;57378\\,0\\,SendToMap,57463\\,0\\,ReportRevealed;false;;;counted;;;;false;;1;1")
    assert_nil t["command"], "blank command text means no menu item"
    assert_equal "named:GEUnkPlacement", t["key"], "fires when it receives this named keystroke"
    assert_equal %w[named:SendToMap named:ReportRevealed], t["action_keys"]
  end

  test "named and physical keystrokes match by name and by code respectively" do
    assert_equal "named:GEUnkPlacement", Vassal::Piece::TraitRegistry.keystroke("57462,0,GEUnkPlacement")
    assert_equal "key:70,130", Vassal::Piece::TraitRegistry.keystroke("70,130")
    assert_nil Vassal::Piece::TraitRegistry.keystroke("")
  end

  test "SendToLocation to a fixed board point (dest L)" do
    t = parse("sendto;;57362,0,Remove;Main Map;MainMap;282;486;;;0;0;1;1;Removed;L;;;;")
    assert_equal "send_to", t["kind"]
    assert_equal "named:Remove", t["key"]
    assert_equal "L", t["dest"]
    assert_equal "MainMap", t["board"]
    assert_equal [ 282, 486 ], [ t["x"], t["y"] ]
    assert_nil t["grid_location"]
  end

  test "SendToLocation by location name from a property (dest G)" do
    t = parse("sendto;;57378,0,SendToMap;Main Map;MainMap;1700;5452;;;;0;0;0;Send to Map;G;;;;$GEUnkLoc$")
    assert_equal "G", t["dest"]
    assert_equal "named:SendToMap", t["key"]
    assert_equal "$GEUnkLoc$", t["grid_location"], "destination is a $property$ expression"
  end

  test "CounterGlobalKeyCommand relays a key to pieces in a deck" do
    t = parse("globalkey;;57459,0,BringToMap;57460,0,GEUnkPlacement;;false;1;true;true;;Bring to Map;1;COUNTER|true|DECK|||||0|0|GEUnknownUnits|false|||EQUALS||;false;")
    assert_equal "global_key", t["kind"]
    assert_equal "named:BringToMap", t["key"], "the command that activates the relay"
    assert_equal "named:GEUnkPlacement", t["global_key"], "the key sent to matching pieces"
    assert_equal "GEUnknownUnits", t["deck"], "target is the hidden-units deck"
  end

  test "SetGlobalProperty change command sets a named property to an expression" do
    t = parse("setprop;GEUnkLoc;false,0,100,false;:57458\\,0\\,SetLocation:P\\,$LocationName$;Location;Current Zone/Current Map/Module;")
    assert_equal "set_property", t["kind"]
    assert_equal "GEUnkLoc", t["name"]
    assert_equal [ { "key" => "named:SetLocation", "op" => "P", "value" => "$LocationName$" } ], t["changes"]
  end

  test "PlaceMarker captures its key, marker spec and offsets" do
    t = parse("placemark;;57430,0,Disrupted;VASSAL.build.module.PieceWindow:Markers/VASSAL.build.widget.TabWidget:Markers/VASSAL.build.widget.ListWidget:General/VASSAL.build.widget.PieceSlot:Disrupted Marker;null;0;0;false;;Disrupted;1474;2;false;false;;1")
    assert_equal "place_marker", t["kind"]
    assert_equal "named:Disrupted", t["key"]
    assert_equal "VASSAL.build.widget.PieceSlot:Disrupted Marker", t["spec"].split("/").last
    assert_equal [ 0, 0 ], [ t["x_off"], t["y_off"] ]
    assert_equal "1474", t["gpid"], "the gpid stamped on the new instance"
  end

  test "Delete and Clone capture their key command" do
    del = parse("delete;;57358,0,Remove;Remove")
    assert_equal "delete", del["kind"]
    assert_equal "named:Remove", del["key"]

    clone = parse("clone;;57357,0,Clone;Clone")
    assert_equal "clone", clone["kind"]
    assert_equal "named:Clone", clone["key"]
  end

  test "Replace parses like PlaceMarker but with its own kind" do
    t = parse("replace;;57431,0,FullRetreat;VASSAL.build.module.PieceWindow:Markers/VASSAL.build.widget.TabWidget:Markers/VASSAL.build.widget.ListWidget:General/VASSAL.build.widget.PieceSlot:Full Retreat Marker;null;0;0;false;;Full Retreat;297;2;false;false;;1")
    assert_equal "replace", t["kind"]
    assert_equal "named:FullRetreat", t["key"]
    assert_equal "VASSAL.build.widget.PieceSlot:Full Retreat Marker", t["spec"].split("/").last
    assert_equal "297", t["gpid"]
  end

  test "RestrictCommands captures its action and gating expression" do
    t = parse("hideCmd;No Reveal when GE Unknown Units Deck Empty;Disable;{$GEUnkUnitsDeckCount$==0};70\\,130")
    assert_equal "restrict_commands", t["kind"]
    assert_equal "Disable", t["action"]
    assert_equal "{$GEUnkUnitsDeckCount$==0}", t["property_match"]
    assert_equal [ "key:70,130" ], t["keys"], "the keystroke(s) it restricts"
  end
end

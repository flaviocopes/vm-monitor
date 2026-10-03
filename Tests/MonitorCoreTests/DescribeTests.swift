import Foundation
import Testing

@testable import MonitorCore

@Suite struct DescribeTests {
  func run(_ command: String, _ args: [String] = [], input: String? = nil) -> Run {
    Run(id: "x", started: .now, command: command, args: args, input: input)
  }

  @Test func describesEachCommandInPlainWords() {
    #expect(Describe.summary(run("open", ["build/Build/Products/Debug/Skillscout.app"])) == "Opened Skillscout")
    #expect(Describe.summary(run("open", ["Skillscout"])) == "Relaunched Skillscout")
    #expect(Describe.summary(run("open", ["Skillscout.app", "--reset"])) == "Opened Skillscout with --reset")
    #expect(Describe.summary(run("shot", ["Skillscout"])) == "Took a screenshot of Skillscout")
    #expect(Describe.summary(run("shot")) == "Took a screenshot of the screen")
    #expect(Describe.summary(run("ui", ["Skillscout"])) == "Read the controls of Skillscout")
    #expect(Describe.summary(run("click", ["255", "200"])) == "Clicked at 255, 200")
    #expect(Describe.summary(run("type", ["flavioify"])) == "Typed “flavioify”")
    #expect(Describe.summary(run("key", ["cmd+a"])) == "Pressed ⌘A")
    #expect(Describe.summary(run("logs", ["Skillscout"])) == "Read the logs of Skillscout")
    #expect(Describe.summary(run("push", ["/Users/flavio/sample/", "dev/sample/"])) == "Copied sample into the VM")
    #expect(Describe.summary(run("run", ["defaults write com.flaviocopes.skillscout x -bool true"]))
      == "Ran defaults write com.flaviocopes.skillscout x -bool true")
    #expect(Describe.summary(run("note", ["Checking", "the sort menu"])) == "Checking the sort menu")
    #expect(Describe.summary(run("start")) == "Started the VM")
  }

  @Test func namesTheMenuItemAnAppleScriptChooses() {
    let script = """
      tell application "System Events" to tell process "Skillscout"
        click menu item "Settings…" of menu "Skillscout" of menu bar 1
      end tell
      """
    #expect(Describe.summary(run("script", input: script)) == "Chose “Settings…” from a menu")
    #expect(Describe.summary(run("script", input: "return 1")) == "Ran an AppleScript")
  }

  @Test func namesTheControlAClickHit() {
    let button = Control(role: "AXButton", title: "Find repeated tasks", kind: "AXButton", value: nil, x: 976, y: 113)
    let field = Control(role: "AXTextField", title: nil, kind: "search text field", value: "flavio", x: 1171, y: 114)
    #expect(Describe.summary(run("click", ["976", "113"]), clicked: button) == "Clicked “Find repeated tasks”")
    #expect(Describe.summary(run("click", ["1171", "114"]), clicked: field) == "Clicked the search text field")
  }

  @Test func writesKeysTheWayMenusDo() {
    #expect(Describe.keys("cmd+shift+s") == "⇧⌘S")
    #expect(Describe.keys("shift+cmd+s") == "⇧⌘S")
    #expect(Describe.keys("return") == "Return")
    #expect(Describe.keys("cmd+return") == "⌘ Return")
    #expect(Describe.keys("arrow-down") == "↓")
    #expect(Describe.keys("ctrl+option+left") == "⌃⌥←")
  }

  @Test func rebuildsTheCommandLine() {
    #expect(Describe.commandLine(run("click", ["255", "200"])) == "testvm click 255 200")
    #expect(Describe.commandLine(run("open", ["dist/CLI Tools.app"])) == "testvm open 'dist/CLI Tools.app'")
    #expect(Describe.commandLine(run("type", ["it's"])) == #"testvm type 'it'\''s'"#)
    #expect(Describe.commandLine(run("script", input: "return 1")) == "testvm script <<'EOF'\nreturn 1\nEOF")
  }

  @Test func appNamesComeFromBundlePaths() {
    #expect(Describe.appName("build/Debug/Skillscout.app/") == "Skillscout")
    #expect(Describe.appName("dist/CLI Tools.app") == "CLI Tools")
    #expect(Describe.appName("Skillscout") == "Skillscout")
  }
}

@Suite struct ControlTests {
  let listing = """
    WINDOW "Skillscout"
    AXStaticText "Missing somewhere"  center 255,200
    AXPopUpButton [pop up button] = Newest first  center 855,113
    AXButton "Find repeated tasks" (disabled)  center 976,113
    AXTextField [search text field] = flavio  center 1171,114
    AXButton "Cancel"  center 900,600
    AXStaticText "Cancel"  center 900,600
    """

  @Test func parsesTheUIListing() {
    let controls = Control.parse(listing)
    #expect(controls.count == 6)
    #expect(controls[0] == Control(role: "AXStaticText", title: "Missing somewhere", kind: "AXStaticText", value: nil, x: 255, y: 200))
    #expect(controls[1].title == nil)
    #expect(controls[1].kind == "pop up button")
    #expect(controls[1].value == "Newest first")
    #expect(controls[2].title == "Find repeated tasks")
    #expect(controls[3].value == "flavio")
  }

  @Test func findsTheControlAtAClickedCenter() {
    let controls = Control.parse(listing)
    #expect(Control.at(x: 976, y: 113, in: controls)?.title == "Find repeated tasks")
    #expect(Control.at(x: 977, y: 112, in: controls)?.title == "Find repeated tasks")
    #expect(Control.at(x: 900, y: 600, in: controls)?.role == "AXStaticText")
    #expect(Control.at(x: 500, y: 500, in: controls) == nil)
  }
}

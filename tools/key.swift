import CoreGraphics
import Foundation

let args = CommandLine.arguments
let source = CGEventSource(stateID: .hidSystemState)

func postKey(_ code: CGKeyCode, flags: CGEventFlags) {
    let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
    down?.flags = flags
    down?.post(tap: .cghidEventTap)
    usleep(60_000)
    let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
    up?.flags = flags
    up?.post(tap: .cghidEventTap)
}

let cmd = args.count > 1 ? args[1] : ""
switch cmd {
case "quit":
    postKey(12, flags: [.maskCommand, .maskAlternate, .maskControl]) // ⌃⌥⌘Q
    print("sent ctrl-opt-cmd-Q")
case "escape":
    postKey(53, flags: [])
    print("sent escape")
case "panel":
    postKey(0, flags: [.maskCommand, .maskAlternate, .maskControl]) // ⌃⌥⌘A
    print("sent ctrl-opt-cmd-A")
default:
    print("usage: key quit|escape|panel")
}

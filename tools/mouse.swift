import CoreGraphics
import Foundation

func post(_ type: CGEventType, at p: CGPoint, button: CGMouseButton = .left) {
    let source = CGEventSource(stateID: .hidSystemState)
    guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: button) else { return }
    event.post(tap: .cghidEventTap)
}

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: mouse move|click|rightclick x y")
    exit(2)
}
let command = args[1]
let x = Double(args[2]) ?? 0
let y = Double(args[3]) ?? 0
let p = CGPoint(x: x, y: y)

func click(button: CGMouseButton, down: CGEventType, up: CGEventType) {
    CGWarpMouseCursorPosition(p)
    usleep(150_000)
    post(down, at: p, button: button)
    usleep(60_000)
    post(up, at: p, button: button)
}

switch command {
case "move":
    CGWarpMouseCursorPosition(p)
case "click":
    click(button: .left, down: .leftMouseDown, up: .leftMouseUp)
case "rightclick":
    click(button: .right, down: .rightMouseDown, up: .rightMouseUp)
case "hold":
    guard args.count >= 5 else {
        print("usage: mouse hold x y ms")
        exit(2)
    }
    let ms = UInt32(args[4]) ?? 600
    CGWarpMouseCursorPosition(p)
    usleep(150_000)
    post(.leftMouseDown, at: p)
    usleep(ms * 1000)
    post(.leftMouseUp, at: p)
case "scroll":
    guard args.count >= 5 else {
        print("usage: mouse scroll x y lines")
        exit(2)
    }
    let lines = Int32(args[4]) ?? -3
    CGWarpMouseCursorPosition(p)
    usleep(100_000)
    if let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0) {
        event.location = p
        event.post(tap: .cghidEventTap)
    }
default:
    print("unknown command \(command)")
    exit(2)
}

import AppKit
import SwiftUI
import QuartzCore
import Carbon
import Combine
import IOKit.ps
import CoreWLAN
import UserNotifications

struct PixelSprite {
    let frames: [[String]]
    let palette: [Character: Color]
}

private func pxColor(_ r: Double, _ g: Double, _ b: Double) -> Color {
    Color(red: r, green: g, blue: b)
}

extension PixelSprite {
    static let whale = PixelSprite(
        frames: [
            [
                "............",
                "....LL......",
                "....L.......",
                "............",
                "..BBBBBB....",
                ".BBBBBBBB...",
                ".BBWBBBBB...",
                ".BBBBBBBBB..",
                "..BBBBBBB.B.",
                "...DDDDD.BB.",
                "............",
                "............"
            ],
            [
                "............",
                "...L..L.....",
                "....LL......",
                "............",
                "..BBBBBB....",
                ".BBBBBBBB...",
                ".BBWBBBBB...",
                ".BBBBBBBBB..",
                "..BBBBBBB.B.",
                "...DDDDD.BB.",
                "............",
                "............"
            ]
        ],
        palette: [
            "B": pxColor(0.28, 0.56, 1.00),
            "D": pxColor(0.17, 0.38, 0.80),
            "W": Color.white,
            "L": pxColor(0.62, 0.86, 1.00)
        ]
    )

    static let island = PixelSprite(
        frames: [
            [
                "............",
                ".....YY.....",
                "....YYYY....",
                ".....YY.....",
                "..GGGGGGGG..",
                ".GGGGGGGGGG.",
                "..TTTTTTTT..",
                "...TTTTTT...",
                "............",
                "............",
                "............",
                "............"
            ],
            [
                "............",
                "....YYYY....",
                ".....YY.....",
                "............",
                "..GGGGGGGG..",
                ".GGGGGGGGGG.",
                "..TTTTTTTT..",
                "...TTTTTT...",
                "............",
                "............",
                "............",
                "............"
            ]
        ],
        palette: [
            "Y": pxColor(1.00, 0.78, 0.30),
            "G": pxColor(0.34, 0.82, 0.45),
            "T": pxColor(0.78, 0.62, 0.35)
        ]
    )

    static let bolt = PixelSprite(
        frames: [
            [
                "............",
                "......YY....",
                ".....YY.....",
                "....YY......",
                "...YYYYY....",
                "......YY....",
                ".....YY.....",
                "....YY......",
                "............",
                "............",
                "............",
                "............"
            ],
            [
                "......L.....",
                "......YY....",
                ".....YY.....",
                "....YY......",
                "...LLLLL....",
                "......YY....",
                ".....YY.....",
                "....YY......",
                "............",
                "............",
                "............",
                "............"
            ]
        ],
        palette: [
            "Y": pxColor(1.00, 0.80, 0.25),
            "L": pxColor(1.00, 0.96, 0.62)
        ]
    )

    static let magnifier = PixelSprite(
        frames: [
            [
                "............",
                "...WWWW.....",
                "..WCCCCW....",
                "..WCCCCW....",
                "..WCCCCW....",
                "...WWWW.....",
                ".....WW.....",
                "......WW....",
                ".......WW...",
                "............",
                "............",
                "............"
            ],
            [
                "............",
                "...WWWW.....",
                "..WCLCCW....",
                "..WCCLCW....",
                "..WCCCCW....",
                "...WWWW.....",
                ".....WW.....",
                "......WW....",
                ".......WW...",
                "............",
                "............",
                "............"
            ]
        ],
        palette: [
            "W": pxColor(0.86, 0.91, 0.96),
            "C": pxColor(0.26, 0.78, 1.00),
            "L": Color.white
        ]
    )

    static let flask = PixelSprite(
        frames: [
            [
                "............",
                ".....WW.....",
                ".....WW.....",
                "....WWWW....",
                "....WGGW....",
                "...WGGGGW...",
                "..WGGGGGGW..",
                "..WGGGGGGW..",
                "...WWWWWW...",
                "............",
                "............",
                "............"
            ],
            [
                "............",
                ".....WW.....",
                ".....WW.....",
                "....WWWW....",
                "....WGLW....",
                "...WGLLGW...",
                "..WGGGGGGW..",
                "..WGGGGGGW..",
                "...WWWWWW...",
                "............",
                "............",
                "............"
            ]
        ],
        palette: [
            "W": pxColor(0.86, 0.91, 0.96),
            "G": pxColor(0.35, 0.90, 0.55),
            "L": pxColor(0.70, 1.00, 0.80)
        ]
    )

    // MARK: Pixelated renditions of real local app icons (16x16, from the apps' .icns)

    static let appCodex = PixelSprite(
        frames: [
            [
                "0000000000000000", "0007111111117000", "0015444544445100", "0755523232254570",
                "0145635222236410", "0142122223222410", "0153223312212410", "0163233661361510",
                "0151631563323610", "0143122713221610", "0143321223272410", "0146122336125410",
                "0755633731356570", "0016444466455100", "0007111111117000", "0000000000000000"
            ]
        ],
        palette: [
            "0": pxColor(0.071, 0.078, 0.102), "1": pxColor(0.447, 0.451, 0.467),
            "2": pxColor(0.698, 0.706, 0.729), "3": pxColor(0.553, 0.557, 0.588),
            "4": pxColor(1.000, 1.000, 1.000), "5": pxColor(0.980, 0.980, 0.980),
            "6": pxColor(0.890, 0.894, 0.902), "7": pxColor(0.247, 0.255, 0.282)
        ]
    )

    static let appGrok = PixelSprite(
        frames: [
            [
                "0000000000000000", "0005555550070000", "0057744444444700", "0574405504444400",
                "0543621126344470", "0562111112667470", "0312212212736400", "0322213561646370",
                "0312213432133200", "0312121546112130", "0312121632122130", "0322111111112230",
                "0312222222222130", "0061111111111600", "0003333333333000", "0000000000000000"
            ]
        ],
        palette: [
            "0": pxColor(0.071, 0.078, 0.102), "1": pxColor(1.000, 1.000, 1.000),
            "2": pxColor(0.988, 0.988, 0.988), "3": pxColor(0.388, 0.392, 0.400),
            "4": pxColor(0.000, 0.000, 0.000), "5": pxColor(0.118, 0.122, 0.133),
            "6": pxColor(0.804, 0.804, 0.804), "7": pxColor(0.047, 0.051, 0.059)
        ]
    )

    static let appWorkbuddy = PixelSprite(
        frames: [
            [
                "0060000000000600", "7702222222222077", "6621111111551266", "0611111114334120",
                "0211111115335120", "0211111453333320", "0211115333555320", "0255553354111520",
                "0233333411441120", "0253351111534420", "0213311544434420", "0213311334444420",
                "0613311434444320", "0723351445553500", "0002222222222077", "0060000000000000"
            ]
        ],
        palette: [
            "0": pxColor(0.071, 0.078, 0.102), "1": pxColor(0.027, 0.796, 0.612),
            "2": pxColor(0.122, 0.424, 0.357), "3": pxColor(0.918, 0.980, 0.961),
            "4": pxColor(0.153, 0.824, 0.612), "5": pxColor(0.533, 0.898, 0.745),
            "6": pxColor(0.067, 0.078, 0.102), "7": pxColor(0.067, 0.075, 0.098)
        ]
    )

    static let appDSH = PixelSprite(
        frames: [
            [
                "0000000000000000", "0001111111111000", "0043333333333400", "0132222222222310",
                "0472372522232710", "0132411642154540", "0135006665401240", "0134546611112310",
                "0131535665042310", "0134433566652310", "0175644440122310", "0122516645422740",
                "0675225552222310", "0047223333333400", "0006111111111000", "0000000000000000"
            ]
        ],
        palette: [
            "0": pxColor(0.071, 0.078, 0.102), "1": pxColor(0.400, 0.412, 0.431),
            "2": pxColor(0.976, 0.980, 0.980), "3": pxColor(1.000, 1.000, 1.000),
            "4": pxColor(0.518, 0.522, 0.537), "5": pxColor(0.839, 0.843, 0.851),
            "6": pxColor(0.188, 0.200, 0.227), "7": pxColor(0.996, 1.000, 1.000)
        ]
    )
}

extension AgentStatus {
    /// Manifest set name for this status. Idle-only deliveries fall back to `idle`.
    var iconSetName: String {
        switch self {
        case .running: return "running"
        case .waiting: return "waiting"
        case .done: return "done"
        case .failed: return "failed"
        }
    }
}

func pixelSprite(for agentName: String, seed: String = "", live: Bool = false) -> PixelSprite {
    pixelSprite(forIconID: agentIconID(for: agentName, seed: seed, live: live))
}

/// Character-grid fallback used only when the matching PNG set is missing.
/// Claude and generic have no legacy grid, so they use the neutral whale.
func pixelSprite(forIconID id: String) -> PixelSprite {
    switch id {
    case "codex": return .appCodex
    case "grok": return .appGrok
    case "workbuddy": return .appWorkbuddy
    case "dsh": return .appDSH
    case "whale": return .whale
    case "island": return .island
    case "bolt": return .bolt
    case "magnifier": return .magnifier
    case "flask": return .flask
    case "claude", "generic": return .whale
    default: return .whale
    }
}

struct PixelAvatar: View {
    let sprite: PixelSprite
    let status: AgentStatus
    let size: CGFloat
    let phase: Int

    private var interval: Double {
        agentIconInterval(forStatus: status.iconSetName, suggestedIntervalSec: nil)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: interval)) { context in
            let frames = sprite.frames
            let frameIndex = agentIconFrameIndex(
                time: context.date.timeIntervalSinceReferenceDate,
                interval: interval,
                frameCount: frames.count,
                phase: phase
            )
            Canvas { context, canvasSize in
                guard !frames.isEmpty else { return }
                draw(frames[frameIndex], context: &context, canvasSize: canvasSize)
            }
            .frame(width: size, height: size)
            .opacity(status == .failed ? 0.75 : 1.0)
        }
        .frame(width: size, height: size)
    }

    private func draw(_ frame: [String], context: inout GraphicsContext, canvasSize: CGSize) {
        let cols = frame.map { $0.count }.max() ?? 1
        let rows = frame.count
        guard cols > 0, rows > 0 else { return }
        let cell = min(canvasSize.width / CGFloat(cols), canvasSize.height / CGFloat(rows))
        let originX = (canvasSize.width - cell * CGFloat(cols)) / 2
        let originY = (canvasSize.height - cell * CGFloat(rows)) / 2
        for (row, line) in frame.enumerated() {
            for (column, ch) in line.enumerated() {
                guard let color = sprite.palette[ch] else { continue }
                var rect = CGRect(
                    x: originX + CGFloat(column) * cell,
                    y: originY + CGFloat(row) * cell,
                    width: cell,
                    height: cell
                )
                rect = rect.insetBy(dx: -0.3, dy: -0.3)
                context.fill(Path(rect), with: .color(color))
            }
        }
    }
}

// MARK: - Bundled PNG icons
//
// Confirmed frames live in Resources/agents/<id>/ and are drawn with SwiftUI
// Image at the caller's point size. They are not re-encoded into PixelSprite
// grids, and they are not scaled with nearest-neighbor.

private struct IconManifestFile: Decodable {
    let agents: [IconManifestAgent]
}

private struct IconManifestAgent: Decodable {
    let id: String
    let sets: [String: IconManifestSet]
}

private struct IconManifestSet: Decodable {
    let frames: Int
    let suggestedIntervalSec: Double?
}

private struct LoadedIconSet {
    let images: [NSImage]
    let suggestedIntervalSec: Double?
}

struct AgentIconPresentation {
    let images: [NSImage]
    let interval: Double
}

enum AgentIconLibrary {
    private static let agents: [String: [String: LoadedIconSet]] = loadAgents()

    static func presentation(id: String, status: AgentStatus) -> AgentIconPresentation? {
        guard let sets = agents[id] else { return nil }
        let resolved: LoadedIconSet
        if let specific = sets[status.iconSetName], !specific.images.isEmpty {
            resolved = specific
        } else if let idle = sets["idle"], !idle.images.isEmpty {
            resolved = idle
        } else {
            return nil
        }
        let interval = agentIconInterval(
            forStatus: status.iconSetName,
            suggestedIntervalSec: resolved.suggestedIntervalSec
        )
        return AgentIconPresentation(images: resolved.images, interval: interval)
    }

    private static func loadAgents() -> [String: [String: LoadedIconSet]] {
        guard let manifestURL = locateManifest(),
              let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(IconManifestFile.self, from: data) else {
            return [:]
        }
        let root = manifestURL.deletingLastPathComponent()
        var loaded: [String: [String: LoadedIconSet]] = [:]
        for agent in manifest.agents {
            let directory = root.appendingPathComponent(agent.id, isDirectory: true)
            var sets: [String: LoadedIconSet] = [:]
            for (setName, spec) in agent.sets {
                let images = loadFrames(directory: directory, setName: setName, count: spec.frames)
                guard spec.frames > 0, images.count == spec.frames else { continue }
                sets[setName] = LoadedIconSet(images: images, suggestedIntervalSec: spec.suggestedIntervalSec)
            }
            if !sets.isEmpty {
                loaded[agent.id] = sets
            }
        }
        return loaded
    }

    private static func locateManifest() -> URL? {
        if let url = Bundle.main.url(forResource: "manifest", withExtension: "json", subdirectory: "agents") {
            return url
        }
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("agents/manifest.json"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/agents/manifest.json")
        ]
        for candidate in candidates {
            if let url = candidate, FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    /// Loads `<set>_00.png` … in order. The horizontal strip is a preview only
    /// and is never used as a frame. Bytes are decoded for display, not rewritten.
    private static func loadFrames(directory: URL, setName: String, count: Int) -> [NSImage] {
        guard count > 0 else { return [] }
        var images: [NSImage] = []
        images.reserveCapacity(count)
        for index in 0..<count {
            let filename = String(format: "%@_%02d.png", setName, index)
            let url = directory.appendingPathComponent(filename)
            guard let image = NSImage(contentsOf: url) else { return [] }
            image.isTemplate = false
            images.append(image)
        }
        return images
    }
}

struct AgentGlyph: View {
    let name: String
    let seed: String
    let live: Bool
    let status: AgentStatus
    let size: CGFloat
    let phase: Int

    var body: some View {
        glyph(for: agentIconID(for: name, seed: seed, live: live))
    }

    @ViewBuilder
    private func glyph(for id: String) -> some View {
        if let presentation = AgentIconLibrary.presentation(id: id, status: status) {
            AnimatedPNGIcon(
                images: presentation.images,
                interval: presentation.interval,
                size: size,
                phase: phase,
                dimmed: status == .failed
            )
        } else {
            PixelAvatar(
                sprite: pixelSprite(forIconID: id),
                status: status,
                size: size,
                phase: phase
            )
        }
    }
}

struct AnimatedPNGIcon: View {
    let images: [NSImage]
    let interval: Double
    let size: CGFloat
    let phase: Int
    let dimmed: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: interval)) { context in
            frame(at: context.date)
        }
        .frame(width: size, height: size)
    }

    private func frame(at date: Date) -> some View {
        let index = images.isEmpty
            ? 0
            : agentIconFrameIndex(
                time: date.timeIntervalSinceReferenceDate,
                interval: interval,
                frameCount: images.count,
                phase: phase
            )
        return Group {
            if images.isEmpty {
                Color.clear
            } else {
                Image(nsImage: images[index])
                    .interpolation(.high)
                    .resizable()
                    .scaledToFit()
                    .opacity(dimmed ? 0.75 : 1)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Shapes / small components

struct NotchShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 10
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),
                       control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r),
                       control: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

struct StatusDot: View {
    let color: Color
    let animated: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            if animated {
                Circle()
                    .stroke(color.opacity(0.5), lineWidth: 1)
                    .frame(width: 6, height: 6)
                    .scaleEffect(pulse ? 2.6 : 1.0)
                    .opacity(pulse ? 0.0 : 0.9)
            }
            Circle().fill(color).frame(width: 6, height: 6)
        }
        .onAppear {
            guard animated else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}

// MARK: - Rail views (selected unit + burst)

struct BurstOverlay: View {
    let color: Color
    @State private var animate = false

    private let particles: [(CGFloat, CGFloat, CGFloat)] = [
        (-11, -6, 2.4), (-15, 2, 2.0), (-8, 9, 2.2), (-1, -13, 2.6),
        (8, -9, 2.0), (13, 1, 2.2), (7, 10, 2.4), (-2, 13, 2.0)
    ]

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.9), lineWidth: 1.2)
                .frame(width: 18, height: 18)
                .scaleEffect(animate ? 2.1 : 0.5)
                .opacity(animate ? 0 : 0.9)
            ForEach(particles.indices, id: \.self) { index in
                let p = particles[index]
                Circle()
                    .fill(color.opacity(0.9))
                    .frame(width: p.2, height: p.2)
                    .offset(x: animate ? p.0 * 1.9 : 0, y: animate ? p.1 * 1.9 : 0)
                    .opacity(animate ? 0 : 1)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: 0.52)) { animate = true }
        }
    }
}

struct AgentDetailPill: View {
    let agent: Agent
    let width: CGFloat
    @AppStorage("AgentBarShowChineseThought") private var showChineseThought = true
    @State private var thoughtFallback = false

    private var displayedThought: String? {
        guard let thought = agent.thought, !thought.isEmpty else { return nil }
        if !showChineseThought { return thought }
        if let zh = agent.thoughtZh, !zh.isEmpty { return zh }
        if containsCJK(thought) || thoughtFallback { return thought }
        return "翻译中…"
    }
    let phase: Int
    let live: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(agent.name)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.96))
                .lineLimit(1)
            Text(agent.status.label)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(agent.status.color)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Capsule().fill(agent.status.color.opacity(0.14)))
            Text(agent.project)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.38))
                .lineLimit(1)
            Text("·")
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.22))
            Text(agent.tool)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.55))
                .lineLimit(1)
                .truncationMode(.middle)
            if let thought = displayedThought {
                Text("💭 " + thought.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 6)
            Text(elapsedString(since: agent.startedAt))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.40))
                .padding(.trailing, 2)
        }
        .padding(.horizontal, 10)
        .frame(width: width, height: railAvatarSize, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.7)
        )
        .task(id: agent.thought) {
            thoughtFallback = false
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            thoughtFallback = true
        }
    }
}

struct SelectedRailIcon: View {
    let agent: Agent
    let phase: Int
    let live: Bool
    let reduceMotion: Bool
    @State private var iconScale: CGFloat = 0.72

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.32), lineWidth: 0.7)
                )
            AgentGlyph(name: agent.name, seed: agent.id, live: live, status: agent.status, size: 18, phase: phase)
                .padding(2.5)
                .scaleEffect(iconScale)
            Circle()
                .fill(agent.status.color)
                .frame(width: 4.5, height: 4.5)
                .overlay(Circle().stroke(Color.black.opacity(0.65), lineWidth: 0.6))
                .offset(x: 0.5, y: 0.5)
            if !reduceMotion {
                BurstOverlay(color: agent.status.color)
            }
        }
        .frame(width: railAvatarSize, height: railAvatarSize)
        .background(railFrameReader("icon:\(agent.id)"))
        .help(agent.name + " · " + agent.status.label)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.60)) {
                iconScale = 1.0
            }
        }
    }
}

struct ExpandingRailPill: View {
    let agent: Agent
    let width: CGFloat
    let phase: Int
    let live: Bool
    let reduceMotion: Bool
    @State private var expanded = false

    var body: some View {
        AgentDetailPill(agent: agent, width: width, phase: phase, live: live)
            .frame(width: expanded ? width : 0, alignment: .leading)
            .clipped()
            .opacity(expanded ? 1 : 0)
            .background(railFrameReader("pill:\(agent.id)"))
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: 0.20) : .spring(response: 0.50, dampingFraction: 0.82)) {
                    expanded = true
                }
            }
    }
}

struct SelectedAgentUnit: View {
    let agent: Agent
    let pillWidth: CGFloat
    let phase: Int
    let live: Bool
    let namespace: Namespace.ID
    let reduceMotion: Bool

    @State private var expanded = false
    @State private var iconScale: CGFloat = 0.7

    var body: some View {
        HStack(spacing: 5) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.32), lineWidth: 0.7)
                    )
                AgentGlyph(name: agent.name, seed: agent.id, live: live, status: agent.status, size: 18, phase: phase)
                    .padding(2.5)
                    .scaleEffect(iconScale)
                Circle()
                    .fill(agent.status.color)
                    .frame(width: 4.5, height: 4.5)
                    .overlay(Circle().stroke(Color.black.opacity(0.65), lineWidth: 0.6))
                    .offset(x: 0.5, y: 0.5)
                if !reduceMotion {
                    BurstOverlay(color: agent.status.color)
                        .id(agent.id)
                }
            }
            .frame(width: railAvatarSize, height: railAvatarSize)
            .matchedGeometryEffect(id: "rail-icon-\(agent.id)", in: namespace)
            .background(railFrameReader("icon:\(agent.id)"))

            AgentDetailPill(agent: agent, width: pillWidth, phase: phase, live: live)
                .frame(width: expanded ? pillWidth : 0, alignment: .leading)
                .clipped()
                .opacity(expanded ? 1 : 0)
        }
        .onAppear {
            let anim: Animation = reduceMotion
                ? .easeOut(duration: 0.18)
                : .spring(response: 0.42, dampingFraction: 0.76)
            withAnimation(anim) {
                expanded = true
                iconScale = 1.0
            }
        }
    }
}

// MARK: - Bar view

struct BarView: View {
    @ObservedObject var store: DemoStore
    @ObservedObject var geom: Geometry
    @ObservedObject var ui: UIModel
    @ObservedObject var sys: SystemStatus
    let net: NetSpeed
    @AppStorage("AgentBarDailyTokenBudget") private var dailyTokenBudget = 0.0

    @Namespace private var railNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selectedAgent: Agent? {
        if let id = ui.selectedID, let agent = store.agents.first(where: { $0.id == id }) {
            return agent
        }
        return store.agents.first { $0.status == .running } ?? store.agents.first
    }

    private var railAgents: [Agent] { Array(store.agents.prefix(5)) }

    private func indexOf(_ agent: Agent) -> Int {
        railAgents.firstIndex(where: { $0.id == agent.id }) ?? 0
    }

    private func avatarIcon(_ agent: Agent) -> some View {
        let isHovered = ui.hoveredIndex == indexOf(agent)
        return ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(isHovered ? 0.10 : 0.0))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.white.opacity(isHovered ? 0.20 : 0.0), lineWidth: 0.7)
                )
            AgentGlyph(name: agent.name, seed: agent.id, live: store.isLive, status: agent.status, size: 18, phase: indexOf(agent))
                .padding(2.5)
            Circle()
                .fill(agent.status.color)
                .frame(width: 4.5, height: 4.5)
                .overlay(Circle().stroke(Color.black.opacity(0.65), lineWidth: 0.6))
                .offset(x: 0.5, y: 0.5)
        }
        .frame(width: railAvatarSize, height: railAvatarSize)
        .opacity(isHovered ? 0.95 : 0.62)
        .background(railFrameReader("icon:\(agent.id)"))
        .help(agent.name + " · " + agent.status.label + " · 点击切换")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(agent.name)，\(agent.status.label)")
        .accessibilityAddTraits(.isButton)
    }

    var body: some View {
        ZStack(alignment: .top) {
            // opaque base: fully covers the system menu bar underneath
            Color(red: 0.070, green: 0.076, blue: 0.092)

            LinearGradient(
                colors: [Color(red: 0.108, green: 0.118, blue: 0.140),
                         Color(red: 0.062, green: 0.068, blue: 0.082)],
                startPoint: .top, endPoint: .bottom
            )

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 0.5)
                .frame(maxHeight: .infinity, alignment: .top)

            HStack(spacing: 0) {
                leftWing
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 18)
                Color.clear.frame(width: geom.notchWidth + 34, height: 1)
                rightWing
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4)
                    .padding(.trailing, 18)
            }
            .frame(height: geom.barHeight)

            if !geom.hasNotch {
                // simulate the camera housing so the demo reads like a notched MacBook
                NotchShape()
                    .fill(Color.black)
                    .frame(width: geom.notchWidth, height: geom.barHeight)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.white.opacity(0.10))
                            .frame(height: 0.5)
                    }
                    .overlay {
                        Circle()
                            .fill(Color(red: 0.040, green: 0.046, blue: 0.055))
                            .frame(width: 7, height: 7)
                            .overlay(
                                Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                            )
                            .overlay(
                                Circle()
                                    .fill(Color.white.opacity(0.06))
                                    .frame(width: 2, height: 2)
                                    .offset(x: -1.2, y: -1.2)
                            )
                    }
            }

            if store.runningCount > 0 {
                Capsule()
                    .fill(AgentStatus.running.color.opacity(0.35))
                    .frame(width: geom.notchWidth * 0.55, height: 1.5)
                    .blur(radius: 4)
                    .offset(y: geom.barHeight - 2)
            }

            Rectangle()
                .fill(Color.white.opacity(0.045))
                .frame(height: 0.5)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: geom.barHeight)
        .clipped()
    }

    private var leftWing: some View {
        GeometryReader { geo in
            let available = max(0, geo.size.width)
            let agents = railAgents
            let selected = selectedAgent
            let count = CGFloat(agents.count)
            // Capsule uses all remaining left-wing length, after the fixed icon row leaves room for one icon per agent.
            let overflowWidth = store.agents.count > agents.count ? railOverflowWidth + railSpacing : 0
            let pillWidth = max(160, available - count * railAvatarSize - count * railSpacing - 2 - overflowWidth)

            HStack(spacing: railSpacing) {
                ForEach(agents, id: \.id) { agent in
                    if agent.id == selected?.id {
                        SelectedRailIcon(
                            agent: agent,
                            phase: indexOf(agent),
                            live: store.isLive,
                            reduceMotion: reduceMotion
                        )
                        ExpandingRailPill(
                            agent: agent,
                            width: pillWidth,
                            phase: indexOf(agent),
                            live: store.isLive,
                            reduceMotion: reduceMotion
                        )
                    } else {
                        avatarIcon(agent)
                    }
                }
                if store.agents.count > agents.count {
                    Text("+\(store.agents.count - agents.count)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(ui.hoveredOverflow ? 0.78 : 0.34))
                        .frame(width: railOverflowWidth, height: railAvatarSize)
                        .background(Capsule().fill(Color.white.opacity(ui.hoveredOverflow ? 0.10 : 0)))
                        .background(railFrameReader("overflow"))
                        .help("点击展开面板，查看全部 \(store.agents.count) 个 agent")
                }
            }
            .frame(width: available, height: geo.size.height, alignment: .leading)
            .coordinateSpace(name: "rail")
            .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.50, dampingFraction: 0.82), value: selected?.id)
            .onPreferenceChange(RailFramePreferenceKey.self) { frames in
                ui.railLayout.frames = frames
                if CommandLine.arguments.contains("--debug-layout"),
                   Date().timeIntervalSince(lastRailLogAt) > 1.0 {
                    lastRailLogAt = Date()
                    let summary = frames.sorted { $0.value.minX < $1.value.minX }
                        .map { "\($0.key)=\(Int($0.value.minX))-\(Int($0.value.maxX))" }
                        .joined(separator: " | ")
                    dlog("[rail/pref] \(summary)")
                }
            }
        }
        .frame(height: geom.barHeight)
    }

    private var liveChip: some View {
        let mode = store.feedMode
        let color: Color
        switch mode {
        case .protocolMismatch:
            color = Color(red: 1.0, green: 0.45, blue: 0.42)
        case .demo:
            color = Color.white.opacity(0.30)
        case .offline:
            color = Color(red: 1.0, green: 0.75, blue: 0.30)
        case .live:
            color = Color(red: 0.36, green: 0.90, blue: 0.62)
        }
        return HStack(spacing: 4) {
            Circle().fill(color).frame(width: 4.5, height: 4.5)
            Text(barModeLabel(mode))
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .help(mode == .protocolMismatch ? (store.protocolNote ?? "DSH 协议不匹配") : barModeLabel(mode))
    }

    private var agentCountText: String {
        switch store.feedMode {
        case .protocolMismatch:
            return store.agents.isEmpty ? "DSH" : "\(store.agents.count) 个外部"
        case .live, .offline:
            return "\(store.liveTotal) 个 agent"
        case .demo:
            return "\(store.completedToday) 完成"
        }
    }

    private var approvalBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 9, weight: .bold))
            Text("\(store.waitingCount) 待审批")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(Color(red: 1.0, green: 0.80, blue: 0.38))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color(red: 1.0, green: 0.72, blue: 0.25).opacity(0.16)))
        .overlay(Capsule().strokeBorder(Color(red: 1.0, green: 0.72, blue: 0.25).opacity(0.35), lineWidth: 0.5))
    }

    private var usageText: String {
        guard let tokens = store.usageTokensToday else { return "--" }
        return shortTokenText(tokens)
    }

    private var usageOverBudget: Bool {
        guard dailyTokenBudget > 0, let tokens = store.usageTokensToday else { return false }
        return Double(tokens) > dailyTokenBudget
    }

    private var rightWing: some View {
        HStack(spacing: 8) {
            // AI-related info: left-aligned in the right wing, nearest the notch
            if store.waitingCount > 0 {
                approvalBadge
            }
            liveChip
            Text(agentCountText)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.45))
            Text("\(store.runningCount) 运行")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.50))

            HStack(spacing: 3) {
                Image(systemName: usageOverBudget ? "exclamationmark.triangle.fill" : "chart.bar.fill")
                    .font(.system(size: 9, weight: .medium))
                Text("用量 \(usageText)")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(usageOverBudget ? Color(red: 1.0, green: 0.62, blue: 0.28) : Color.white.opacity(0.50))
            .help(dailyTokenBudget > 0 ? "今日用量 / 预算 \(shortTokenText(Int(dailyTokenBudget)))" : "今日用量")

            HStack(spacing: 3) {
                Image(systemName: "creditcard")
                    .font(.system(size: 9, weight: .medium))
                Text("余额 \(store.balanceText ?? "--")")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(Color.white.opacity(0.55))

            Spacer(minLength: 16)

            // system status: right-aligned at the far end
            Rectangle()
                .fill(Color.white.opacity(0.14))
                .frame(width: 0.5, height: 11)
            batteryView
            wifiView
            NetSpeedLabel(net: net)
            weatherView
            Rectangle()
                .fill(Color.white.opacity(0.14))
                .frame(width: 0.5, height: 11)
            Text(dayFormatter.string(from: Date()))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.55))
            Text(clockFormatter.string(from: Date()))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.72))
        }
        .lineLimit(1)
    }

    private var batteryView: some View {
        HStack(spacing: 3) {
            if sys.hasBattery, let percent = sys.batteryPercent {
                Image(systemName: sys.batteryCharging ? "battery.100.bolt" : batterySymbol(percent))
                    .font(.system(size: 10.5, weight: .medium))
                Text("\(percent)%")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
            } else {
                Image(systemName: "powerplug.fill")
                    .font(.system(size: 9.5))
                Text("AC")
                    .font(.system(size: 10, weight: .medium))
            }
        }
        .foregroundStyle(Color.white.opacity(0.55))
    }

    private var wifiView: some View {
        HStack(spacing: 3) {
            Image(systemName: sys.wifiOn ? "wifi" : "wifi.slash")
                .font(.system(size: 10, weight: .medium))
            if let ssid = sys.wifiSSID, !ssid.isEmpty {
                Text(ssid)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .frame(maxWidth: 80, alignment: .leading)
            }
        }
        .foregroundStyle(Color.white.opacity(0.55))
    }


    private var weatherView: some View {
        HStack(spacing: 3) {
            Image(systemName: weatherSymbol(sys.weatherCode))
                .font(.system(size: 10, weight: .medium))
            Text(sys.weatherTemp.map { "\(Int($0.rounded()))°" } ?? "--°")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
        }
        .foregroundStyle(Color.white.opacity(0.55))
    }
}

/// Split out so a per-second speed tick only invalidates this tiny label, not the
/// whole bar (BarView holds a plain reference, not an @ObservedObject).
struct NetSpeedLabel: View {
    @ObservedObject var net: NetSpeed

    var body: some View {
        HStack(spacing: 2.5) {
            Image(systemName: "arrow.down")
                .font(.system(size: 7, weight: .bold))
            Text(net.downText)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .frame(minWidth: 25, alignment: .trailing)
            Image(systemName: "arrow.up")
                .font(.system(size: 7, weight: .bold))
            Text(net.upText)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .frame(minWidth: 25, alignment: .trailing)
        }
        .foregroundStyle(Color.white.opacity(0.42))
        .opacity(net.isIdle ? 0 : 1)
        .frame(width: net.isIdle ? 0 : nil, alignment: .leading)
        .clipped()
        .animation(.easeInOut(duration: 0.25), value: net.isIdle)
        .help("下载 / 上传（30 秒无流量自动隐藏）")
    }
}

// MARK: - Expanded panel view

/// 400ms hold-to-confirm button used for live approvals.
struct HoldToConfirmButton: View {
    let title: String
    let icon: String
    let tint: Color
    let action: () -> Void
    @State private var pressing = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(pressing ? "松开发送…" : title)
                .font(.system(size: 10.5, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(Capsule().fill(tint.opacity(pressing ? 0.28 : 0.14)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.38), lineWidth: 0.6))
        .contentShape(Capsule())
        .onLongPressGesture(minimumDuration: 0.4, maximumDistance: 18, pressing: { value in
            pressing = value
        }, perform: {
            pressing = false
            action()
        })
        .help("长按 0.4 秒确认；松开取消")
    }
}

struct UsageSparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            let peak = max(values.max() ?? 1, 1)
            let count = max(values.count, 2)
            Path { path in
                for (index, value) in values.enumerated() {
                    let x = geo.size.width * CGFloat(index) / CGFloat(count - 1)
                    let y = geo.size.height - CGFloat(value / peak) * (geo.size.height - 2) - 1
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(Color(red: 0.45, green: 0.82, blue: 1.0), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .help(values.isEmpty ? "还没有用量历史" : "峰值 \(shortTokenText(Int(values.max() ?? 0))) tokens")
    }
}

private struct GeocodeCity: Decodable, Identifiable {
    let name: String
    let latitude: Double
    let longitude: Double
    let country: String?
    let admin1: String?

    var id: String { "\(name)|\(latitude)|\(longitude)" }

    var detail: String {
        [admin1, country]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

private struct GeocodeResponse: Decodable {
    let results: [GeocodeCity]?
}

struct PanelView: View {
    @ObservedObject var store: DemoStore
    @ObservedObject var ui: UIModel
    let realMode: Bool
    let onSelect: (String) -> Void
    let onClose: () -> Void
    let onQuit: () -> Void
    let onWeatherChanged: () -> Void
    let onScreenChanged: () -> Void
    let onOpenApp: (String) -> Void
    let onOpenAdapterLog: () -> Void
    let onRestartAdapters: () -> Void

    @AppStorage("AgentBarLatitude") private var weatherLatitude: Double = 31.2304
    @AppStorage("AgentBarLongitude") private var weatherLongitude: Double = 121.4737
    @AppStorage("AgentBarWeatherPlaceName") private var weatherPlaceName = "上海"
    @AppStorage("AgentBarScreenName") private var screenName = ""
    @State private var cityQuery = ""
    @State private var cityResults: [GeocodeCity] = []
    @State private var citySearchInFlight = false
    @State private var citySearchError: String?
    @AppStorage("AgentBarDailyTokenBudget") private var dailyTokenBudget = 0.0

    private let weatherPresets: [(name: String, lat: Double, lon: Double)] = [
        ("上海", 31.2304, 121.4737),
        ("北京", 39.9042, 116.4074),
        ("深圳", 22.5431, 114.0579),
        ("广州", 23.1291, 113.2644),
        ("杭州", 30.2741, 120.1551)
    ]

    @State private var showSettings = false
    @State private var armedApprovalId: String?
    @State private var thoughtFallback = false
    @State private var questionSelections: [String: Set<String>] = [:]
    @State private var questionCustom: [String: String] = [:]
    @AppStorage("AgentBarNotificationsEnabled") private var notificationsEnabled = true
    @AppStorage("AgentBarShowChineseThought") private var showChineseThought = true

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    private func applyWeatherPlace(name: String, latitude: Double, longitude: Double) {
        weatherPlaceName = name
        weatherLatitude = latitude
        weatherLongitude = longitude
        // refreshWeather reads UserDefaults directly, so make the write explicit
        // before kicking off the request.
        UserDefaults.standard.set(name, forKey: "AgentBarWeatherPlaceName")
        UserDefaults.standard.set(latitude, forKey: "AgentBarLatitude")
        UserDefaults.standard.set(longitude, forKey: "AgentBarLongitude")
        cityQuery = ""
        cityResults = []
        citySearchError = nil
        onWeatherChanged()
    }

    private func searchCity() {
        let query = cityQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            cityResults = []
            citySearchError = nil
            return
        }
        guard var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search") else { return }
        components.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "6"),
            URLQueryItem(name: "language", value: "zh"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components.url else { return }
        citySearchInFlight = true
        citySearchError = nil
        cityResults = []
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                let decoded = try JSONDecoder().decode(GeocodeResponse.self, from: data)
                let results = decoded.results ?? []
                await MainActor.run {
                    self.cityResults = results
                    self.citySearchInFlight = false
                    self.citySearchError = results.isEmpty ? "没有找到「\(query)」" : nil
                }
            } catch {
                await MainActor.run {
                    self.citySearchInFlight = false
                    self.cityResults = []
                    self.citySearchError = "搜索失败，请检查网络"
                }
            }
        }
    }

    private var citySearchResults: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let citySearchError {
                Text(citySearchError)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color(red: 1.0, green: 0.62, blue: 0.42).opacity(0.8))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
            }
            ForEach(cityResults) { city in
                Button(action: {
                    applyWeatherPlace(name: city.name, latitude: city.latitude, longitude: city.longitude)
                }) {
                    HStack(spacing: 7) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(Color(red: 0.45, green: 0.82, blue: 1.0).opacity(0.7))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(city.name)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.78))
                            if !city.detail.isEmpty {
                                Text(city.detail)
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color.white.opacity(0.34))
                            }
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.25))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
                Divider().overlay(Color.white.opacity(0.06))
            }
        }
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 0.6))
    }

    private func displayedThought(_ agent: Agent) -> String? {
        guard let thought = agent.thought, !thought.isEmpty else { return nil }
        if !showChineseThought { return thought }
        if let zh = agent.thoughtZh, !zh.isEmpty { return zh }
        if containsCJK(thought) || thoughtFallback { return thought }
        return "翻译中…"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.08))
            if showSettings {
                settingsBody
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if store.feedMode == .protocolMismatch {
                            protocolBanner
                        }
                        let waiting = store.waitingAgents
                        ForEach(waiting.prefix(3)) { agent in
                            approvalCard(agent)
                        }
                        if waiting.count > 3 {
                            Text("还有 \(waiting.count - 3) 条待审批")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.white.opacity(0.35))
                        }
                        if let selected = store.agents.first(where: { $0.id == ui.selectedID }) {
                            thoughtCard(selected)
                        }
                        ForEach(store.agents) { agent in
                            row(agent)
                            if agent.id == ui.selectedID, !agent.sessions.isEmpty {
                                ForEach(agent.sessions) { session in
                                    sessionRow(session)
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
            Divider().overlay(Color.white.opacity(0.08))
            footer
        }
        .frame(width: 560, height: 500)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.070, green: 0.076, blue: 0.092).opacity(0.985))
        )
        .overlay(
            // Rim light: brighter along the top edge, as if the panel caught the screen's light.
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.15),
                            Color.white.opacity(0.07),
                            Color.white.opacity(0.05)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.6
                )
        )
        .overlay(
            // Inner hairline, so the glass reads as a physical edge instead of a flat fill.
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .inset(by: 1.2)
                .strokeBorder(Color.white.opacity(0.045), lineWidth: 0.5)
        )
        // The drop shadow is drawn by the window (hasShadow), not by SwiftUI: a
        // manual shadow had to be cropped to the window bounds and the crop line
        // read as a hard edge. The window shadow follows the card's rounded alpha
        // shape and is composited outside the frame, so nothing gets clipped.
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(red: 0.45, green: 0.82, blue: 1.0))
            Text("Agent Bar")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.95))
            Text("非官方")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.62))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.6))
                .help("与 DeepSeek Harness、Codex、Claude、Grok、WorkBuddy 无隶属或背书关系")
            Text(panelModeText)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(panelModeColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(panelModeColor.opacity(0.10)))
            Spacer()
            Text("\(store.runningCount) 运行 · \(store.waitingCount) 待审批")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.5))
            Button(action: { ui.isPinned.toggle() }) {
                Image(systemName: ui.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ui.isPinned ? Color(red: 1.0, green: 0.78, blue: 0.36) : Color.white.opacity(0.55))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.white.opacity(ui.isPinned ? 0.12 : 0.06)))
            }
            .buttonStyle(.plain)
            .help(ui.isPinned ? "取消固定面板" : "固定面板（切到其他 App 也不收起）")
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
    }

    private func row(_ agent: Agent) -> some View {
        let isSelected = agent.id == ui.selectedID
        let phase = store.agents.firstIndex(where: { $0.id == agent.id }) ?? 0
        return HStack(spacing: 10) {
                AgentGlyph(name: agent.name, seed: agent.id, live: store.isLive, status: agent.status, size: 26, phase: phase)
                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.92))
                    Text("\(agent.project) · \(agent.tool)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let note = agent.note {
                    Text(note)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.32))
                }
                if let today = agent.tokensToday, today > 0 {
                    Text(shortTokenText(today))
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.30))
                        .help("本 agent 今日约 \(today) tokens")
                }
                if agent.sessions.count > 1 {
                    Text("\(agent.sessions.count) 会话")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.35))
                }
                if let bundle = agent.appBundleID {
                    Button(action: { onOpenApp(bundle) }) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.45))
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Color.white.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                    .help("打开 \(agent.name)")
                }
                Text(agent.status.label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(agent.status.color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(agent.status.color.opacity(0.12)))
                Text(elapsedString(since: agent.startedAt))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .frame(width: 42, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.075 : 0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(isSelected ? 0.20 : 0.0), lineWidth: 0.7)
            )
            .contentShape(Rectangle())
            .onTapGesture { onSelect(agent.id) }
    }

    private func sessionRow(_ session: AgentSession) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(session.status.color)
                .frame(width: 5, height: 5)
            Text(session.project)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.62))
                .lineLimit(1)
            Text(session.tool ?? "")
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.34))
                .lineLimit(1)
            Spacer()
            if let tokens = session.tokens, tokens > 0 {
                Text(shortTokenText(tokens))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.26))
            }
            Text(session.status.label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(session.status.color.opacity(0.85))
        }
        .padding(.leading, 36)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.025)))
    }

    private func thoughtCard(_ agent: Agent) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 10, weight: .semibold))
                Text("思考与过程")
                    .font(.system(size: 11.5, weight: .semibold))
                Spacer()
                Text(agent.name)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.40))
            }
            .foregroundStyle(Color(red: 0.62, green: 0.82, blue: 1.0))

            if let thought = displayedThought(agent) {
                Text(inlineThoughtAttributed(thought))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .tint(Color(red: 0.55, green: 0.82, blue: 1.0))
                    .lineLimit(8)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !agent.steps.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(agent.steps.suffix(8))) { step in
                        HStack(spacing: 6) {
                            Image(systemName: stepIcon(step.kind))
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundStyle(stepColor(step.kind))
                                .frame(width: 12)
                            Text(step.label ?? "")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.62))
                            if let detail = step.detail, !detail.isEmpty {
                                Text(detail)
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundStyle(Color.white.opacity(0.38))
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            if let at = step.at {
                                Text(stepTimeFormatter.string(from: at))
                                    .font(.system(size: 8.5, design: .monospaced))
                                    .foregroundStyle(Color.white.opacity(0.25))
                            }
                        }
                    }
                }
            } else if agent.thought == nil {
                Text("暂无思考记录")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.30))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.7)
        )
        .task(id: agent.thought) {
            thoughtFallback = false
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            thoughtFallback = true
        }
    }

    private func isDangerousApproval(_ agent: Agent) -> Bool {
        let text = (agent.approvalCommand ?? "") + " " + (agent.note ?? "")
        let patterns = [
            "danger-full-access", "escalate", "rm -rf", "sudo ", "mkfs", "dd if=",
            "chmod -r 777", "chmod -R 777", "git reset --hard", "git clean -fd",
            "kill -9", "shutdown", "reboot"
        ]
        return patterns.contains { text.localizedCaseInsensitiveContains($0) }
    }

    private func requestAllow(_ agent: Agent) {
        guard agent.approvalId != nil else {
            store.approvalNotice = "审批 ID 缺失，请用打开 DSH 处理"
            return
        }
        let dangerous = isDangerousApproval(agent)
        if dangerous && armedApprovalId != agent.id {
            armedApprovalId = agent.id
            store.approvalNotice = "危险操作：再次长按允许以确认"
            NSSound.beep()
            return
        }
        submitApproval(agent, decision: "allowed-once")
    }

    private func submitApproval(_ agent: Agent, decision: String) {
        guard let approvalId = agent.approvalId else {
            store.approvalNotice = "审批 ID 缺失"
            return
        }
        if store.submitApproval(
            approvalId: approvalId,
            sessionId: agent.id,
            tool: agent.tool,
            command: agent.approvalCommand,
            decision: decision
        ) {
            armedApprovalId = nil
        }
    }

    private var panelModeText: String {
        switch store.feedMode {
        case .protocolMismatch: return "协议不匹配"
        case .live: return "DSH 实时"
        case .offline: return "桥接离线"
        case .demo: return realMode ? "真实模式 · 演示" : "模拟数据 · 演示"
        }
    }

    private var panelModeColor: Color {
        switch store.feedMode {
        case .protocolMismatch: return Color(red: 1.0, green: 0.45, blue: 0.42)
        case .live: return Color(red: 0.36, green: 0.90, blue: 0.62)
        case .offline: return Color(red: 1.0, green: 0.75, blue: 0.30)
        case .demo: return Color.white.opacity(0.32)
        }
    }

    private var protocolBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("协议不匹配")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(red: 1.0, green: 0.62, blue: 0.55))
            Text(store.protocolNote ?? "DSH 的 session/list 与当前桥不一致。")
                .font(.system(size: 10.5))
                .foregroundStyle(Color.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
            Text("状态条保持这个提示，不会改用演示数据。")
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.40))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(red: 1.0, green: 0.45, blue: 0.38).opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(red: 1.0, green: 0.45, blue: 0.38).opacity(0.28), lineWidth: 0.7))
    }

    @ViewBuilder
    private func approvalCard(_ agent: Agent) -> some View {
        if store.isLive && !agent.isExternal && agent.approvalKind == "question" {
            questionCard(agent)
        } else {
            commandApprovalCard(agent)
        }
    }

    private func customBinding(_ questionID: String) -> Binding<String> {
        Binding(
            get: { questionCustom[questionID] ?? "" },
            set: { questionCustom[questionID] = $0 }
        )
    }

    private func toggleQuestionOption(_ question: AgentQuestion, label: String) {
        var chosen = questionSelections[question.id] ?? []
        if question.multiSelect {
            if chosen.contains(label) { chosen.remove(label) } else { chosen.insert(label) }
        } else if chosen.contains(label) {
            chosen = []
        } else {
            chosen = [label]
        }
        questionSelections[question.id] = chosen
    }

    private func submitQuestion(_ agent: Agent, cancelled: Bool) {
        guard let approvalId = agent.approvalId else {
            store.approvalNotice = "问题 ID 缺失，请用打开 DSH 处理"
            return
        }
        if cancelled {
            _ = store.submitQuestion(approvalId: approvalId, sessionId: agent.id, answers: [], cancelled: true)
            return
        }
        switch buildQuestionAnswers(questions: agent.questions, selections: questionSelections, customText: questionCustom) {
        case .failure(let message):
            store.approvalNotice = message
        case .success(let answers):
            _ = store.submitQuestion(approvalId: approvalId, sessionId: agent.id, answers: answers, cancelled: false)
        }
    }

    private func questionCard(_ agent: Agent) -> some View {
        let needsHold = agent.questions.contains { $0.intent == "approval" }
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.bubble.fill")
                    .font(.system(size: 10, weight: .bold))
                Text(agent.questionAnswerable ? "需要你的回答" : "问题只读")
                    .font(.system(size: 11.5, weight: .semibold))
                Spacer()
                Text(agent.name)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            .foregroundStyle(Color(red: 1.0, green: 0.80, blue: 0.38))

            if agent.questionAnswerable {
                ForEach(agent.questions) { question in
                    VStack(alignment: .leading, spacing: 6) {
                        if let header = question.header, !header.isEmpty {
                            Text(header)
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.40))
                        }
                        Text(question.prompt)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.white.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)
                        if let detail = question.detail, !detail.isEmpty {
                            Text(detail)
                                .font(.system(size: 10))
                                .foregroundStyle(Color.white.opacity(0.48))
                                .lineLimit(6)
                        }
                        ForEach(question.options) { option in
                            let selected = questionSelections[question.id]?.contains(option.label) == true
                            Button(action: { toggleQuestionOption(question, label: option.label) }) {
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: selected ? (question.multiSelect ? "checkmark.square.fill" : "largecircle.fill.circle") : (question.multiSelect ? "square" : "circle"))
                                        .font(.system(size: 10, weight: .semibold))
                                        .padding(.top, 1)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(option.title)
                                            .font(.system(size: 11, weight: .semibold))
                                        if let detail = option.detail, !detail.isEmpty {
                                            Text(detail)
                                                .font(.system(size: 9.5))
                                                .foregroundStyle(Color.white.opacity(0.40))
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .foregroundStyle(Color.white.opacity(selected ? 0.92 : 0.68))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(selected ? 0.12 : 0.04)))
                            }
                            .buttonStyle(.plain)
                        }
                        if question.allowCustom {
                            TextField(question.options.isEmpty ? "输入回答" : "其他回答", text: customBinding(question.id))
                                .textFieldStyle(.plain)
                                .font(.system(size: 11))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.28)))
                        }
                    }
                }
                HStack(spacing: 8) {
                    if needsHold {
                        HoldToConfirmButton(title: "按住提交", icon: "checkmark", tint: Color(red: 0.46, green: 0.90, blue: 0.62)) {
                            submitQuestion(agent, cancelled: false)
                        }
                    } else {
                        Button(action: { submitQuestion(agent, cancelled: false) }) {
                            Text("提交回答")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.black)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color(red: 0.46, green: 0.90, blue: 0.62)))
                        }
                        .buttonStyle(.plain)
                    }
                    Button(action: { submitQuestion(agent, cancelled: true) }) {
                        Text("取消问答")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.7))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .help("向 DSH 发送 ASK_CANCELLED，不会改成某个选项")
                    Spacer()
                    Text(store.approvalNotice ?? (needsHold ? "授权题需长按提交" : "选中选项后提交"))
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color.white.opacity(0.32))
                        .lineLimit(1)
                }
            } else {
                Text(agent.approvalCommand ?? agent.questions.first?.prompt ?? "这个问题暂不能在面板里安全回答")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
                Text("题型无法按 DSH 的 answers[{id, selected, custom}] 校验，保持只读。请打开 DSH 处理。")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.40))
            }

            if let host = store.dshURL, let url = URL(string: host) {
                Button(action: { NSWorkspace.shared.open(url) }) {
                    Text("打开 DSH 处理")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.65))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.07)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(red: 1.0, green: 0.72, blue: 0.25).opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(red: 1.0, green: 0.72, blue: 0.25).opacity(0.22), lineWidth: 0.8))
    }

    private func commandApprovalCard(_ agent: Agent) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 10, weight: .bold))
                Text(agent.isExternal ? "外部 agent 需要处理" : "等待你的授权")
                    .font(.system(size: 11.5, weight: .semibold))
                Spacer()
                Text(agent.name)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.white.opacity(0.45))
                AgentGlyph(name: agent.name, seed: agent.id, live: store.isLive, status: agent.status, size: 18, phase: 2)
            }
            .foregroundStyle(Color(red: 1.0, green: 0.80, blue: 0.38))

            Text(agent.approvalCommand ?? "")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.82))
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.35)))
                .lineLimit(2)

            HStack(spacing: 8) {
                if store.isLive {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            if agent.isExternal {
                                Text("外部 agent 审批 · 请在对应工具内处理")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(Color.white.opacity(0.55))
                            } else if agent.approvalId != nil {
                                let dangerous = isDangerousApproval(agent)
                                HoldToConfirmButton(
                                    title: dangerous && armedApprovalId == agent.id ? "再次长按允许" : "按住允许",
                                    icon: "checkmark",
                                    tint: Color(red: 0.46, green: 0.90, blue: 0.62)
                                ) {
                                    requestAllow(agent)
                                }
                                HoldToConfirmButton(
                                    title: "按住拒绝",
                                    icon: "xmark",
                                    tint: Color(red: 1.0, green: 0.52, blue: 0.52)
                                ) {
                                    submitApproval(agent, decision: "rejected")
                                }
                                if dangerous {
                                    Text("危险")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.55))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.12)))
                                }
                            } else {
                                Text("只读 · 请回 DSH 处理")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(Color(red: 1.0, green: 0.80, blue: 0.38).opacity(0.9))
                            }
                            Spacer()
                            Text(agent.isExternal ? "外部 agent · 只读" : (store.approvalNotice ?? "长按 0.4 秒确认 · 危险命令二次确认"))
                                .font(.system(size: 9.5))
                                .foregroundStyle(Color.white.opacity(0.32))
                                .lineLimit(1)
                        }
                        HStack(spacing: 8) {
                            if !agent.isExternal, let host = store.dshURL, let url = URL(string: host) {
                                Button(action: { NSWorkspace.shared.open(url) }) {
                                    Text("打开 DSH 处理")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.white.opacity(0.65))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(Color.white.opacity(0.07)))
                                }
                                .buttonStyle(.plain)
                            }
                            Button(action: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(agent.id, forType: .string)
                            }) {
                                Text("复制会话 ID")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.white.opacity(0.55))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.white.opacity(0.07)))
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            Text(agent.isExternal ? "外部 agent 只读展示" : "审计：bridge/audit.log")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.white.opacity(0.22))
                        }
                    }
                } else if store.feedMode == .protocolMismatch {
                    Text(agent.isExternal ? "外部 agent · 只读" : "协议不匹配，演示操作已停用")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Color(red: 1.0, green: 0.62, blue: 0.55))
                    Spacer()
                } else {
                    Button(action: { store.approve(agent.id) }) {
                        Text("允许")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color(red: 0.46, green: 0.90, blue: 0.62)))
                    }
                    .buttonStyle(.plain)

                    Button(action: { store.deny(agent.id) }) {
                        Text("拒绝")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Color(red: 1.0, green: 0.52, blue: 0.52))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                            .overlay(Capsule().strokeBorder(Color(red: 1.0, green: 0.52, blue: 0.52).opacity(0.4), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text("演示数据 · 不会真的执行")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color.white.opacity(0.28))
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 1.0, green: 0.72, blue: 0.25).opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(red: 1.0, green: 0.72, blue: 0.25).opacity(0.22), lineWidth: 0.8)
        )
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("点击刘海展开/收起 · 顶边呼出系统菜单栏 · ⌃⌥⌘A 呼出面板")
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.35))
            Spacer()
            if let host = store.dshURL, let url = URL(string: host) {
                Button(action: { NSWorkspace.shared.open(url) }) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help("打开 DSH")
            }
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { showSettings.toggle() } }) {
                HStack(spacing: 5) {
                    Image(systemName: showSettings ? "chevron.left" : "gearshape.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text(showSettings ? "返回" : "设置")
                        .font(.system(size: 10.5, weight: .semibold))
                }
                .foregroundStyle(Color.white.opacity(0.72))
                .padding(.horizontal, 11)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 42)
    }

    private let localAdapterNames = ["Codex", "WorkBuddy", "Grok Bot"]

    private func adapterBadge(_ name: String) -> some View {
        let rows = store.agents.filter { $0.name == name }
        let connected = !rows.isEmpty
        let running = rows.filter { $0.status == .running }.count
        let dotColor = connected
            ? (running > 0 ? Color(red: 0.36, green: 0.90, blue: 0.62) : Color(red: 0.45, green: 0.82, blue: 1.0).opacity(0.7))
            : Color.white.opacity(0.18)
        return HStack(spacing: 3) {
            Circle()
                .fill(dotColor)
                .frame(width: 5, height: 5)
            Text(name == "Grok Bot" ? "Grok" : name)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.white.opacity(connected ? 0.65 : 0.30))
            if connected, running > 0 {
                Text("\(running)")
                    .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.36, green: 0.90, blue: 0.62).opacity(0.9))
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.white.opacity(0.05)))
        .help(connected ? "\(name)：\(running) 运行 / \(rows.count) 会话" : "\(name)：未检测到本地 adapter")
    }

    private var usageTrendValues: [Double] {
        var values = store.usageHistory.map { Double($0) }
        if let today = store.usageTokensToday, today > 0 {
            values.append(Double(today))
        }
        return Array(values.suffix(7))
    }

    private var settingsBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(Color(red: 0.62, green: 0.82, blue: 1.0))
                    Text("设置")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.9))
                    Spacer()
                    Text("Agent Bar v\(appVersion)")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.25))
                }
                .padding(.top, 2)

                Text("非官方。与 DeepSeek Harness、Codex、Claude、Grok、WorkBuddy 无隶属、合作或背书关系。DSH 接入读取本机凭据，随对方版本可能失效。")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.46))
                    .fixedSize(horizontal: false, vertical: true)

                settingsRow(title: "固定面板", subtitle: "切换到其他 App 时面板保持展开") {
                    Toggle("", isOn: $ui.isPinned)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                settingsRow(title: "通知", subtitle: "审批、完成、失败时提醒（需系统授权）") {
                    Toggle("", isOn: $notificationsEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                settingsRow(title: "思考自动中文化", subtitle: "优先显示中文译文，关闭则显示原文") {
                    Toggle("", isOn: $showChineseThought)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                settingsRow(title: "天气位置", subtitle: "\(weatherPlaceName) · 搜索城市，选择后立即刷新") {
                    HStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.35))
                            TextField("城市名", text: $cityQuery)
                                .textFieldStyle(.plain)
                                .frame(width: 88)
                                .onSubmit { searchCity() }
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.white.opacity(0.06)))
                        Button(action: searchCity) {
                            Text(citySearchInFlight ? "…" : "搜索")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.65))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                        .disabled(citySearchInFlight)
                        Menu {
                            ForEach(weatherPresets, id: \.name) { preset in
                                Button(preset.name) {
                                    applyWeatherPlace(name: preset.name, latitude: preset.lat, longitude: preset.lon)
                                }
                            }
                        } label: {
                            Text("常用")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.65))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.white.opacity(0.08)))
                        }
                        .menuStyle(.borderlessButton)
                    }
                }

                if !cityResults.isEmpty || citySearchError != nil {
                    citySearchResults
                }

                settingsRow(title: "每日 token 预算", subtitle: "超过后右栏用量变橙；0 = 关闭（单位 token）") {
                    TextField("", value: $dailyTokenBudget, format: .number.precision(.fractionLength(0)))
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 96)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.white.opacity(0.06)))
                }

                settingsRow(title: "用量趋势", subtitle: "近 7 天 token（今天已计入）") {
                    UsageSparkline(values: usageTrendValues)
                        .frame(width: 120, height: 26)
                }

                settingsRow(title: "本机 App 接入", subtitle: "Codex / WorkBuddy / Grok Bot（每个 App 最多 3 个会话）") {
                    HStack(spacing: 5) {
                        ForEach(localAdapterNames, id: \.self) { name in
                            adapterBadge(name)
                        }
                    }
                }

                settingsRow(title: "Adapter 控制", subtitle: "查看本机 App 接入日志，或重启 adapter watcher") {
                    HStack(spacing: 5) {
                        Button(action: onOpenAdapterLog) {
                            Label("日志", systemImage: "doc.text")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.65))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                        Button(action: onRestartAdapters) {
                            Label("重启", systemImage: "arrow.clockwise")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.65))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }

                settingsRow(title: "显示屏幕", subtitle: "顶部条与面板跟随的显示器") {
                    Menu {
                        Button("主屏（默认）") {
                            screenName = ""
                            onScreenChanged()
                        }
                        Divider()
                        ForEach(NSScreen.screens.map(\.localizedName), id: \.self) { name in
                            Button(name) {
                                screenName = name
                                onScreenChanged()
                            }
                        }
                    } label: {
                        Text(screenName.isEmpty ? "主屏" : screenName)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.65))
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                    .menuStyle(.borderlessButton)
                }

                Divider().overlay(Color.white.opacity(0.08)).padding(.vertical, 2)

                HStack(spacing: 8) {
                    if let host = store.dshURL, let url = URL(string: host) {
                        Button(action: { NSWorkspace.shared.open(url) }) {
                            Label("打开 DSH", systemImage: "arrow.up.right.square")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.75))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }

                Button(action: onQuit) {
                    HStack(spacing: 7) {
                        Image(systemName: "power")
                            .font(.system(size: 10.5, weight: .bold))
                        Text("退出 Agent Bar")
                            .font(.system(size: 11.5, weight: .semibold))
                        Spacer()
                        Text("⌃⌥⌘Q")
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.55).opacity(0.6))
                    }
                    .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.55))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.10)))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.22), lineWidth: 0.6))
                }
                .buttonStyle(.plain)

                Text("设置仅保存在本机 UserDefaults；退出后菜单栏立即恢复。")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.white.opacity(0.28))
                    .padding(.top, 2)
            }
            .padding(16)
        }
    }

    private func settingsRow<Content: View>(title: String, subtitle: String, @ViewBuilder control: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                Text(subtitle)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.white.opacity(0.35))
            }
            Spacer()
            control()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 0.6))
    }
}

// MARK: - Click catcher for the bar


import AppKit
import SwiftUI
import Testing
import IslandCore
@testable import IslandMac

@MainActor struct PromptLayoutTests {
    @Test func promptContentFitsItsAttachedSurface() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("island-prompt-layout")
        let capture = ProcessInfo.processInfo.environment["ISLAND_UI_CAPTURE"] == "1"
        if capture { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        let session = SessionID(ownerInstanceID: "codex-daemon:preview", pid: 10, processStartTime: 1, terminalSessionKey: "preview")
        let fixtures: [(String, AgentPrompt)] = [
            ("short", AgentPrompt(id: PromptID(sessionID: session, localRequestID: "short"), revision: 1,
                text: "Mau pakai layout yang mana?", choices: [PromptChoice(id: "compact", text: "Compact"), PromptChoice(id: "wide", text: "Lebih luas")], acceptsText: true)),
            ("long", AgentPrompt(id: PromptID(sessionID: session, localRequestID: "long"), revision: 1,
                text: String(repeating: "Illustrative long permission context with command and working directory. ", count: 30),
                choices: [PromptChoice(id: "accept", text: "Allow once"), PromptChoice(id: "decline", text: "Deny")], acceptsText: false)),
            ("grouped", AgentPrompt(id: PromptID(sessionID: session, localRequestID: "grouped"), revision: 1,
                text: "", choices: [], acceptsText: false, questions: [
                    AgentQuestion(id: "layout", text: "Mau pakai layout yang mana?", choices: [PromptChoice(id: "compact", text: "Compact"), PromptChoice(id: "wide", text: "Lebih luas")], acceptsText: false),
                    AgentQuestion(id: "notes", text: "Ada yang ingin disesuaikan?", choices: [], acceptsText: true)
                ]))
        ]
        var heights: [String: CGFloat] = [:]
        for (name, prompt) in fixtures {
            let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let bundle = Bundle(url: root.appendingPathComponent(".build/apps/Notchent.app")) ?? .main
            let shell = IslandShell(store: SettingsStore(url: directory.appendingPathComponent(UUID().uuidString)), localizations: bundle)
            let registry = shell.agents
            let coordinator = registry.coordinator
            await coordinator.ingest(.prompt(prompt, kind: .codex))
            // A missing fixture request publishes the queue without starting discovery or delivering a response.
            let missing = AgentPrompt(id: PromptID(sessionID: session, localRequestID: "missing"), revision: 1, text: "", choices: [], acceptsText: true)
            await registry.respond(.text("preview"), to: missing).value
            #expect(registry.prompt == prompt)
            shell.presentedMode = .prompt
            shell.state.mode = .prompt
            var measured = CGSize(width: 480, height: 500)
            shell.contentSizeDidChange = { _, size in measured = size }
            let host = NSHostingView(rootView: IslandRootView(shell: shell))
            let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 480, height: 500), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            window.orderFront(nil)
            defer { window.orderOut(nil) }
            for _ in 0..<6 {
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(40))
                window.setContentSize(measured)
                shell.surface.size = measured
            }
            #expect(abs(host.frame.width - 480) < 1)
            #expect(host.frame.height < 520)
            heights[name] = host.frame.height
            if capture {
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try #require(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent(name + ".png"))
                print("Illustrative native prompt capture: " + directory.appendingPathComponent(name + ".png").path)
            }
        }
        #expect(try #require(heights["long"]) < 400)
        #expect(try #require(heights["short"]) < #require(heights["grouped"]))
    }
}

extension PromptLayoutTests {
    @Test func longDetailsHaveCompactAndExpandedLayouts() async throws {
        let shell = IslandShell(store: SettingsStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        let text = "Bash\n\n" + String(repeating: "A long command with its complete original arguments.\n", count: 20)
        var heights: [Bool: CGFloat] = [:]
        for expanded in [false, true] {
            let host = NSHostingView(rootView: ExpandablePromptText(text: text, shell: shell, expanded: expanded)
                .frame(width: 440).fixedSize().buttonStyle(.plain).foregroundStyle(.white).background(.black))
            let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 440, height: 500), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            window.orderFront(nil)
            defer { window.orderOut(nil) }
            for _ in 0..<6 {
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(40))
                window.setContentSize(host.fittingSize)
            }
            heights[expanded] = host.frame.height
        }
        #expect(try #require(heights[false]) < 110)
        #expect(try #require(heights[true]) > 300)
    }
}

extension PromptLayoutTests {
    @Test func onlySentResponsesShrinkToConfirmationStatus() async throws {
        let session = SessionID(ownerInstanceID: "codex-daemon:preview", pid: 10, processStartTime: 1, terminalSessionKey: "preview")
        for receipt in [ResponseReceipt.sent, .unknown, .rejected] {
            let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let shell = IslandShell(store: SettingsStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)), localizations: Bundle(url: root.appendingPathComponent(".build/apps/Notchent.app")) ?? .main)
            let registry = shell.agents
            let route = AgentRoute(sessionID: session, kind: .codex, capabilities: AgentCapabilities(readPrompt: true, sendResponse: true), permissionGranted: true)
            await registry.coordinator.register(PromptReceiptAdapter(route: route, receipt: receipt), for: .codex)
            await registry.coordinator.ingest(.route(route))
            let prompt = AgentPrompt(id: PromptID(sessionID: session, localRequestID: "status"), revision: 1, text: "Illustrative question", choices: [], acceptsText: true)
            await registry.coordinator.ingest(.prompt(prompt, kind: .codex))
            await registry.respond(.text("reply"), to: prompt).value
            #expect(registry.prompt == prompt, "A sent response must keep waiting for the actual resolution")
            let view = PromptView(registry: registry, shell: shell).fixedSize()
            let size = NSHostingView(rootView: view).fittingSize
            if receipt == .sent {
                #expect(size.width < 440)
                #expect(size.height <= 18, "The compact status must not add extra top space")
                if ProcessInfo.processInfo.environment["ISLAND_UI_CAPTURE"] == "1" {
                    let renderer = ImageRenderer(content: IslandSurface { view.padding(20) }
                        .frame(width: size.width + 40, height: size.height + 40).foregroundStyle(.white).preferredColorScheme(.dark))
                    renderer.scale = 2
                    let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
                    let destination = FileManager.default.temporaryDirectory.appendingPathComponent("notchent-prompt-sent.png")
                    try #require(bitmap.representation(using: .png, properties: [:])).write(to: destination)
                    print("Illustrative sent-status capture: " + destination.path)
                }
            } else {
                #expect(size.width == 440, "Unknown or rejected delivery must keep its error visible")
                #expect(size.height > 60)
            }
        }
    }
}

private struct PromptReceiptAdapter: AgentAdapter {
    let route: AgentRoute
    let receipt: ResponseReceipt
    func events() -> AsyncStream<AgentEvent> { AsyncStream { $0.finish() } }
    func validate(sessionID: SessionID) async throws -> AgentRoute { route }
    func respond(prompt: AgentPrompt, response: AgentResponse) async throws -> ResponseReceipt { receipt }
    func openOrigin(sessionID: SessionID) async throws { throw AgentRoutingError.unavailable }
}

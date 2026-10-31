import CoreGraphics
import Foundation
import Testing
@testable import Wiggle

struct RemoteServerTests {
    private func request(_ raw: String) -> RemoteServer.Request? {
        RemoteServer.parse(Data(raw.utf8))
    }

    @Test func parsesARequestOnceItsBodyArrives() throws {
        let head = "POST /message HTTP/1.1\r\nHost: 127.0.0.1:5000\r\nContent-Length: 12\r\n\r\n"
        #expect(request(head + "{\"text\":") == nil)
        let full = try #require(request(head + "{\"text\":\"a\"}"))
        #expect(full.method == "POST")
        #expect(full.path == "/message")
        #expect(full.headers["host"] == "127.0.0.1:5000")
        #expect(String(data: full.body, encoding: .utf8) == "{\"text\":\"a\"}")
    }

    @Test func needsTheTokenAndTurnsAwayBrowsers() throws {
        let base = "GET /status HTTP/1.1\r\nHost: 127.0.0.1:5000\r\n"
        let good = try #require(request(base + "Authorization: Bearer abc\r\n\r\n"))
        #expect(RemoteServer.isAllowed(good, token: "abc"))
        #expect(!RemoteServer.isAllowed(good, token: "xyz"))
        #expect(!RemoteServer.isAllowed(good, token: ""))
        let noToken = try #require(request(base + "\r\n"))
        #expect(!RemoteServer.isAllowed(noToken, token: "abc"))
        let browser = try #require(request(base + "Authorization: Bearer abc\r\nOrigin: https://evil.example\r\n\r\n"))
        #expect(!RemoteServer.isAllowed(browser, token: "abc"))
        let rebound = try #require(request("GET /status HTTP/1.1\r\nHost: evil.example:5000\r\nAuthorization: Bearer abc\r\n\r\n"))
        #expect(!RemoteServer.isAllowed(rebound, token: "abc"))
    }
}

/// Answers every message with the same reply.
@MainActor
private final class CannedSession: ChatSession {
    let modelName = "Canned"
    var reply: String
    private(set) var sent: [String] = []

    init(reply: String) { self.reply = reply }

    func send(_ prompt: String, screenshot: Screenshot?) -> AsyncThrowingStream<String, Error> {
        sent.append(prompt)
        let reply = reply
        return makeTextStream { yield in yield(reply) }
    }
}

@MainActor
struct RemoteChatTests {
    private let folder = FileManager.default.temporaryDirectory.appending(path: "wiggle-tests-\(UUID().uuidString)")

    private func setUp(reply: String = "Hello!", blocker: String? = nil)
        -> (chat: RemoteChat, store: WorkflowStore, runs: () -> [String], session: CannedSession)
    {
        let store = WorkflowStore(url: folder.appending(path: "workflows.json"))
        store.add(Workflow(name: "Linkedin cold message", steps: [
            WorkflowStep(delay: 0, action: .click(at: CGPoint(x: 5, y: 5), button: .left, count: 1, modifiers: 0)),
            WorkflowStep(delay: 0.3, action: .text("Hi")),
            WorkflowStep(delay: 0.5, action: .key(code: 36, modifiers: 0, characters: "\r")),
        ]))
        var runs: [String] = []
        var playing = false
        let session = CannedSession(reply: reply)
        let controls = RemoteChat.Controls(
            isPlaying: { playing }, isPaused: { false },
            run: { runs.append($0.name); playing = true },
            togglePause: {}, stop: { playing = false }, blocker: { blocker })
        let chat = RemoteChat(store: store, controls: controls, makeSession: { session }, keys: { KeyLayout(keys: [:]) })
        return (chat, store, { runs }, session)
    }

    @Test func runsOnlyAfterAYes() async {
        defer { try? FileManager.default.removeItem(at: folder) }
        let (chat, _, runs, _) = setUp()
        let ask = await chat.handle("run linkedin")
        #expect(ask.text.contains("Reply yes"))
        #expect(ask.text.contains("• Hi"))
        #expect(runs().isEmpty)
        let yes = await chat.handle("Yes")
        #expect(yes.started == "Linkedin cold message")
        #expect(runs() == ["Linkedin cold message"])
        #expect(await chat.handle("stop").text == "Stopped.")
    }

    @Test func aYesCountsOnlyAsTheNextMessage() async {
        defer { try? FileManager.default.removeItem(at: folder) }
        let (chat, _, runs, _) = setUp()
        _ = await chat.handle("run 1")
        _ = await chat.handle("workflows")
        #expect(await chat.handle("yes").text == "There's nothing waiting for a yes.")
        #expect(runs().isEmpty)
    }

    @Test func saysWhyARunCantStart() async {
        defer { try? FileManager.default.removeItem(at: folder) }
        let (chat, _, runs, _) = setUp(blocker: "Your Mac's screen is locked.")
        _ = await chat.handle("run 1")
        #expect(await chat.handle("yes").text == "Your Mac's screen is locked.")
        #expect(runs().isEmpty)
    }

    @Test func changesSavesAndRunsTheEditedCopy() async {
        defer { try? FileManager.default.removeItem(at: folder) }
        let (chat, store, runs, session) = setUp(reply: "Here you go. <type step=\"2\">Hi Sarah</type>")
        #expect(await chat.handle("change linkedin").text.contains("Changing “Linkedin cold message”"))
        let proposal = await chat.handle("for Sarah at Stripe")
        #expect(proposal.text.contains("Step 2 will type:\nHi Sarah"))
        #expect(session.sent.last?.contains("<workflow>") == true)
        #expect(await chat.handle("save").text == "Saved “Linkedin cold message (edited)”. Text run to run it.")
        #expect(store.workflows.count == 2)
        #expect(store.workflows.first { $0.name == "Linkedin cold message" }?.steps[1].action == .text("Hi"))
        _ = await chat.handle("run")
        _ = await chat.handle("yes")
        #expect(runs() == ["Linkedin cold message (edited)"])
    }

    @Test func refusesChangesOnStepsThatDontType() async {
        defer { try? FileManager.default.removeItem(at: folder) }
        let (chat, store, _, _) = setUp(reply: "<type step=\"1\">Hi Sarah</type>")
        _ = await chat.handle("change 1")
        #expect(await chat.handle("for Sarah").text.contains("doesn't type anything"))
        #expect(await chat.handle("save").text == "There are no changes to save yet.")
        #expect(store.workflows.count == 1)
    }

    @Test func asksWhichOneWhenANameMatchesSeveral() async {
        defer { try? FileManager.default.removeItem(at: folder) }
        let (chat, store, runs, _) = setUp()
        store.add(Workflow(name: "Linkedin cold message (edited)", steps: [WorkflowStep(delay: 0, action: .text("a"))]))
        let reply = await chat.handle("run linkedin")
        #expect(reply.text == "Which one? Text its number:\n1. Linkedin cold message (edited)\n2. Linkedin cold message")
        #expect(await chat.handle("yes").text == "There's nothing waiting for a yes.")
        #expect(runs().isEmpty)
    }

    @Test func chatsWhenNotChangingAWorkflow() async {
        defer { try? FileManager.default.removeItem(at: folder) }
        let (chat, _, _, session) = setUp(reply: "Hello!")
        #expect(await chat.handle("how are you?").text == "Hello!")
        #expect(session.sent == ["how are you?"])
    }
}

struct TextingTests {
    @Test @MainActor func acceptsANumberOrAnEmailToTextFrom() {
        #expect(Texting.isValidSender("+1 (555) 123-4567"))
        #expect(Texting.isValidSender("me@icloud.com"))
        #expect(!Texting.isValidSender("555-1234"))
        #expect(!Texting.isValidSender(""))
    }
}

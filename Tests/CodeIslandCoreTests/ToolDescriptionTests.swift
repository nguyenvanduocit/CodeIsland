import Foundation
import Testing
@testable import CodeIslandCore

@Suite("HookEvent.toolDescription derivation")
struct ToolDescriptionTests {

    private func makeEvent(toolName: String, toolInput: [String: Any]) -> HookEvent {
        var json: [String: Any] = [
            "session_id": "test-session",
            "hook_event_name": "PreToolUse",
            "tool_name": toolName,
            "tool_input": toolInput,
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        return HookEvent(from: data)!
    }

    private func makeEventFromJson(_ json: [String: Any]) -> HookEvent {
        let data = try! JSONSerialization.data(withJSONObject: json)
        return HookEvent(from: data)!
    }

    @Test func bashPrefersDescription() {
        let event = makeEvent(toolName: "Bash", toolInput: [
            "command": "cd /tmp && ls -la",
            "description": "List files in /tmp",
        ])
        #expect(event.toolDescription == "List files in /tmp")
    }

    @Test func bashFallsBackToFirstLineOfCommand() {
        let event = makeEvent(toolName: "Bash", toolInput: [
            "command": "git status\ngit diff",
        ])
        #expect(event.toolDescription == "git status")
    }

    @Test func bashTruncatesLongCommand() {
        let longCmd = String(repeating: "x", count: 100)
        let event = makeEvent(toolName: "Bash", toolInput: ["command": longCmd])
        #expect(event.toolDescription?.count == 60)
    }

    @Test func readShowsFilenameOnly() {
        let event = makeEvent(toolName: "Read", toolInput: [
            "file_path": "/Users/dev/project/src/main.swift",
        ])
        #expect(event.toolDescription == "main.swift")
    }

    @Test func readShowsFilenameWithOffset() {
        let event = makeEvent(toolName: "Read", toolInput: [
            "file_path": "/Users/dev/project/src/main.swift",
            "offset": 42,
        ])
        #expect(event.toolDescription == "main.swift:42")
    }

    @Test func editShowsFilename() {
        let event = makeEvent(toolName: "Edit", toolInput: [
            "file_path": "/path/to/config.json",
        ])
        #expect(event.toolDescription == "config.json")
    }

    @Test func writeShowsFilename() {
        let event = makeEvent(toolName: "Write", toolInput: [
            "file_path": "/path/to/output.txt",
        ])
        #expect(event.toolDescription == "output.txt")
    }

    @Test func grepShowsPatternOnly() {
        let event = makeEvent(toolName: "Grep", toolInput: [
            "pattern": "TODO|FIXME",
        ])
        #expect(event.toolDescription == "TODO|FIXME")
    }

    @Test func grepShowsPatternWithDir() {
        let event = makeEvent(toolName: "Grep", toolInput: [
            "pattern": "import Foundation",
            "path": "/Users/dev/project/Sources",
        ])
        #expect(event.toolDescription == "import Foundation in Sources")
    }

    @Test func globShowsPattern() {
        let event = makeEvent(toolName: "Glob", toolInput: [
            "pattern": "**/*.swift",
        ])
        #expect(event.toolDescription == "**/*.swift")
    }

    @Test func webSearchShowsQuery() {
        let event = makeEvent(toolName: "WebSearch", toolInput: [
            "query": "swift concurrency tutorial",
        ])
        #expect(event.toolDescription == "swift concurrency tutorial")
    }

    @Test func webFetchShowsDomain() {
        let event = makeEvent(toolName: "WebFetch", toolInput: [
            "url": "https://developer.apple.com/documentation/swiftui",
        ])
        #expect(event.toolDescription == "developer.apple.com")
    }

    @Test func webFetchFallsBackToTruncatedUrl() {
        let event = makeEvent(toolName: "WebFetch", toolInput: [
            "url": "not-a-valid-url",
        ])
        #expect(event.toolDescription == "not-a-valid-url")
    }

    @Test func agentShowsDescription() {
        let event = makeEvent(toolName: "Agent", toolInput: [
            "description": "Research codebase",
            "prompt": "Find all API endpoints in the project",
        ])
        #expect(event.toolDescription == "Research codebase")
    }

    @Test func agentFallsBackToPromptPrefix() {
        let event = makeEvent(toolName: "Agent", toolInput: [
            "prompt": "Find all API endpoints in the project and document them thoroughly",
        ])
        #expect(event.toolDescription == "Find all API endpoints in the project an")
    }

    @Test func todoWriteReturnsFixed() {
        let event = makeEvent(toolName: "TodoWrite", toolInput: ["todos": []])
        #expect(event.toolDescription == "Updating tasks")
    }

    @Test func unknownToolTriesCommonFields() {
        let event = makeEvent(toolName: "CustomTool", toolInput: [
            "file_path": "/path/to/file.rs",
        ])
        #expect(event.toolDescription == "file.rs")
    }

    @Test func noToolInputFallsBackToMessage() {
        let event = makeEventFromJson([
            "session_id": "test",
            "hook_event_name": "Notification",
            "message": "Build completed",
        ])
        #expect(event.toolDescription == "Build completed")
    }
}

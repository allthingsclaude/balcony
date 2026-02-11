import Foundation

/// Payload carrying a list of project files for the @ file picker.
public struct FileListPayload: Codable, Sendable {
    public let sessionId: String
    public let files: [String]

    public init(sessionId: String, files: [String]) {
        self.sessionId = sessionId
        self.files = files
    }
}

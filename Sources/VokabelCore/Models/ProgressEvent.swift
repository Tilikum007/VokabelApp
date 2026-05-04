import Foundation

public struct ProgressEvent: Codable, Equatable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var entryID: String
    public var learner: Learner
    public var timestamp: Date
    public var grade: AnswerGrade
    public var correctLevelDelta: Double

    public init(
        id: UUID = UUID(),
        entryID: String,
        learner: Learner,
        timestamp: Date = Date(),
        grade: AnswerGrade,
        correctLevelDelta: Double
    ) {
        self.id = id
        self.entryID = entryID
        self.learner = learner
        self.timestamp = timestamp
        self.grade = grade
        self.correctLevelDelta = correctLevelDelta
    }
}

import Foundation

public enum Learner: String, CaseIterable, Identifiable {
    case papa = "Papa"
    case mama = "Mama"

    public var id: String { rawValue }
}

public enum AnswerGrade: String, CaseIterable, Identifiable {
    case correct = "richtig"
    case almost = "fast richtig"
    case wrong = "falsch"

    public var id: String { rawValue }
}

public enum QuestionDirection: String {
    case germanToNorwegian
    case norwegianToGerman
}

public struct VocabularyEntry: Identifiable, Equatable {
    public var id: String
    public var german: String
    public var norwegian: String
    public var partOfSpeech: String
    public var source: String
    public var lesson: String
    public var levelPapa: Int
    public var levelMama: Int
    public var lastPapa: String
    public var lastMama: String
    public var lastResultPapa: String
    public var lastResultMama: String
    public var correctPapa: Int
    public var wrongPapa: Int
    public var correctMama: Int
    public var wrongMama: Int
    public var exampleNO: String
    public var exampleDE: String
    public var note: String
    public var active: String

    public init(
        id: String,
        german: String,
        norwegian: String,
        partOfSpeech: String,
        source: String,
        lesson: String,
        levelPapa: Int,
        levelMama: Int,
        lastPapa: String,
        lastMama: String,
        lastResultPapa: String,
        lastResultMama: String,
        correctPapa: Int,
        wrongPapa: Int,
        correctMama: Int,
        wrongMama: Int,
        exampleNO: String,
        exampleDE: String,
        note: String,
        active: String
    ) {
        self.id = id
        self.german = german
        self.norwegian = norwegian
        self.partOfSpeech = partOfSpeech
        self.source = source
        self.lesson = lesson
        self.levelPapa = levelPapa
        self.levelMama = levelMama
        self.lastPapa = lastPapa
        self.lastMama = lastMama
        self.lastResultPapa = lastResultPapa
        self.lastResultMama = lastResultMama
        self.correctPapa = correctPapa
        self.wrongPapa = wrongPapa
        self.correctMama = correctMama
        self.wrongMama = wrongMama
        self.exampleNO = exampleNO
        self.exampleDE = exampleDE
        self.note = note
        self.active = active
    }

    public var isActive: Bool {
        active.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare("ja") == .orderedSame
    }

    public func level(for learner: Learner) -> Int {
        learner == .papa ? levelPapa : levelMama
    }

    public mutating func apply(_ grade: AnswerGrade, learner: Learner, date: Date = Date()) {
        let formatter = ISO8601DateFormatter()
        let stamp = formatter.string(from: date)
        let delta: Int

        switch grade {
        case .correct:
            delta = 1
        case .almost:
            delta = 0
        case .wrong:
            delta = -1
        }

        switch learner {
        case .papa:
            levelPapa = min(5, max(0, levelPapa + delta))
            lastPapa = stamp
            lastResultPapa = grade.rawValue
            if grade == .correct {
                correctPapa += 1
            } else if grade == .wrong {
                wrongPapa += 1
            }
        case .mama:
            levelMama = min(5, max(0, levelMama + delta))
            lastMama = stamp
            lastResultMama = grade.rawValue
            if grade == .correct {
                correctMama += 1
            } else if grade == .wrong {
                wrongMama += 1
            }
        }
    }
}

public struct TrainingFilter: Equatable {
    public var level: Int?
    public var source: String?
    public var lesson: String?

    public init(level: Int? = nil, source: String? = nil, lesson: String? = nil) {
        self.level = level
        self.source = source
        self.lesson = lesson
    }
}

public struct TrainingQuestion: Identifiable, Equatable {
    public let id = UUID()
    public let entryID: String
    public let prompt: String
    public let expectedAnswer: String
    public let direction: QuestionDirection
    public let options: [String]
}

import Foundation

public enum Learner: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case papa = "Papa"
    case mama = "Mama"

    public var id: String { rawValue }
}

public enum AnswerGrade: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case correct = "richtig"
    case almost = "fast richtig"
    case wrong = "falsch"

    public var id: String { rawValue }
}

public enum QuestionDirection: String {
    case germanToNorwegian
    case norwegianToGerman
}

public enum DirectionMode: String, CaseIterable, Identifiable {
    case germanToNorwegian = "Deutsch -> Norwegisch"
    case norwegianToGerman = "Norwegisch -> Deutsch"
    case alternating = "Abwechselnd"

    public var id: String { rawValue }

    public var shortTitle: String {
        switch self {
        case .germanToNorwegian:
            "DE -> NO"
        case .norwegianToGerman:
            "NO -> DE"
        case .alternating:
            "Mix"
        }
    }
}

public enum AnswerMode: String, CaseIterable, Identifiable {
    case typed = "Eingeben"
    case choice = "Auswahl"

    public var id: String { rawValue }
}

public enum TrainingFocus: String, CaseIterable, Identifiable {
    case vocabulary = "Wortschatz"
    case articles = "Artikel"

    public var id: String { rawValue }
}

public struct VocabularyEntry: Identifiable, Equatable {
    public var id: String
    public var german: String
    public var norwegian: String
    public var article: String
    public var partOfSpeech: String
    public var source: String
    public var lesson: String
    public var levelPapa: Double
    public var levelMama: Double
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
        article: String = "",
        partOfSpeech: String,
        source: String,
        lesson: String,
        levelPapa: Double,
        levelMama: Double,
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
        self.article = article
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

    public var sourceTokens: [String] {
        source
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public var normalizedSource: String {
        var seen = Set<String>()
        let uniqueTokens = sourceTokens.filter { seen.insert($0).inserted }
        if uniqueTokens.isEmpty {
            return source.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return uniqueTokens.joined(separator: "; ")
    }

    public var normalizedLesson: String {
        lesson.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var strippingProgress: VocabularyEntry {
        VocabularyEntry(
            id: id,
            german: german,
            norwegian: norwegian,
            article: article,
            partOfSpeech: partOfSpeech,
            source: source,
            lesson: lesson,
            levelPapa: 0,
            levelMama: 0,
            lastPapa: "",
            lastMama: "",
            lastResultPapa: "",
            lastResultMama: "",
            correctPapa: 0,
            wrongPapa: 0,
            correctMama: 0,
            wrongMama: 0,
            exampleNO: exampleNO,
            exampleDE: exampleDE,
            note: note,
            active: active
        )
    }

    public func level(for learner: Learner) -> Double {
        learner == .papa ? levelPapa : levelMama
    }

    public mutating func apply(
        _ grade: AnswerGrade,
        learner: Learner,
        correctLevelDelta: Double = 1,
        date: Date = Date()
    ) {
        let formatter = ISO8601DateFormatter()
        let stamp = formatter.string(from: date)
        let delta: Double

        switch grade {
        case .correct:
            delta = correctLevelDelta
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
    public let promptDetail: String
    public let expectedAnswer: String
    public let expectedArticle: String
    public let direction: QuestionDirection
    public let focus: TrainingFocus
    public let options: [String]
    public let articleOptions: [String]
    public let exampleNO: String
    public let exampleDE: String

    public var requiresArticle: Bool {
        focus == .vocabulary && direction == .germanToNorwegian && !expectedArticle.isEmpty
    }

    public var asksOnlyArticle: Bool {
        focus == .articles
    }

    public var expectedDisplayAnswer: String {
        guard !asksOnlyArticle else { return expectedArticle }
        guard requiresArticle else { return expectedAnswer }
        return "\(expectedArticle) \(expectedAnswer)"
    }
}

public struct SessionMistake: Identifiable, Equatable {
    public let id = UUID()
    public let entryID: String
    public let prompt: String
    public let expectedAnswer: String
    public let givenAnswer: String
    public let exampleNO: String
    public let exampleDE: String
}

public struct MasterValidationIssue: Identifiable, Equatable {
    public let id = UUID()
    public let entryID: String
    public let message: String
}

public struct MasterValidationReport: Equatable {
    public var checkedCount: Int
    public var issues: [MasterValidationIssue]

    public var title: String {
        issues.isEmpty ? "Master-Pruefung bestanden" : "\(issues.count) Auffaelligkeiten gefunden"
    }
}

public struct MasterValidator {
    public init() {}

    public func validate(_ entries: [VocabularyEntry]) -> MasterValidationReport {
        var issues: [MasterValidationIssue] = []
        var seenIDs = Set<String>()

        for entry in entries {
            if entry.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(MasterValidationIssue(entryID: "ohne ID", message: "ID fehlt"))
            } else if !seenIDs.insert(entry.id).inserted {
                issues.append(MasterValidationIssue(entryID: entry.id, message: "ID ist doppelt vorhanden"))
            }

            if entry.german.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(MasterValidationIssue(entryID: entry.id, message: "Deutsch fehlt"))
            }

            if entry.norwegian.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(MasterValidationIssue(entryID: entry.id, message: "Norwegisch fehlt"))
            }

            let article = entry.article.trimmingCharacters(in: .whitespacesAndNewlines)
            if !article.isEmpty && !["en", "et", "en/ei"].contains(article) {
                issues.append(MasterValidationIssue(entryID: entry.id, message: "Artikel ist nicht erlaubt: \(article)"))
            }

            if entry.norwegian.range(of: #",\s*(en|ei|et|en/ei|ei/en)\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil {
                issues.append(MasterValidationIssue(entryID: entry.id, message: "Artikel steht noch im norwegischen Wortfeld"))
            }

            let partOfSpeech = entry.partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !article.isEmpty && !partOfSpeech.contains("substantiv") {
                issues.append(MasterValidationIssue(entryID: entry.id, message: "Artikel gesetzt, aber Wortart ist nicht Substantiv"))
            }
        }

        return MasterValidationReport(checkedCount: entries.count, issues: issues)
    }
}

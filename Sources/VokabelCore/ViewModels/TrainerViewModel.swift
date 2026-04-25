import Foundation

@MainActor
public final class TrainerViewModel: ObservableObject {
    @Published public var learner: Learner = .papa
    @Published public var filter = TrainingFilter()
    @Published public var currentQuestion: TrainingQuestion?
    @Published public var answerText = ""
    @Published public var feedback: FeedbackState?
    @Published public var sessionSize = 10
    @Published public var remaining = 0
    @Published public var directionMode: DirectionMode = .germanToNorwegian
    @Published public var answerMode: AnswerMode

    public let store: VocabularyStore
    public let auth: AuthCoordinator
    private let engine = TrainingEngine()
    private var session: [VocabularyEntry] = []
    private var directionIndex = 0
    private var lastEntryID: String?

    public init(store: VocabularyStore, auth: AuthCoordinator = AuthCoordinator()) {
        self.store = store
        self.auth = auth
        self.answerMode = TrainerViewModel.defaultAnswerMode
    }

    public var sources: [String] {
        store.entries.map(\.source).filter { !$0.isEmpty }.uniqued().sorted()
    }

    public var lessons: [String] {
        store.entries.map(\.lesson).filter { !$0.isEmpty }.uniqued().sorted()
    }

    public func load() async {
        await auth.restoreSavedLogin()
        await store.loadBundledSampleIfNeeded()
        if let accessToken = auth.accessToken {
            await store.syncFromDrive(accessToken: accessToken)
        }
        startSession()
    }

    public func syncNow() async {
        guard let accessToken = auth.accessToken else {
            store.setSyncMessage("Bitte zuerst mit Google anmelden")
            return
        }

        await store.syncFromDrive(accessToken: accessToken)
    }

    public func uploadNow() async {
        guard let accessToken = auth.accessToken else {
            store.setSyncMessage("Bitte zuerst mit Google anmelden")
            return
        }

        await store.uploadToDrive(accessToken: accessToken)
    }

    public func signInAndSync() async {
        await auth.signIn()
        if auth.isSignedIn {
            await syncNow()
        }
    }

    public func handleOpenURL(_ url: URL) {
        _ = auth.handleOpenURL(url)
    }

    public func startSession() {
        session = engine.makeSession(
            from: store.entries,
            learner: learner,
            filter: filter,
            count: sessionSize,
            lastEntryID: lastEntryID
        )
        remaining = session.count
        feedback = nil
        directionIndex = 0
        nextQuestion()
    }

    public func submitTypedAnswer() {
        guard let question = currentQuestion else { return }
        submit(grade: engine.grade(answer: answerText, expected: question.expectedAnswer))
    }

    public func choose(_ option: String) {
        guard let question = currentQuestion else { return }
        submit(grade: option == question.expectedAnswer ? .correct : .wrong)
    }

    private func submit(grade: AnswerGrade) {
        guard let question = currentQuestion else { return }
        let correctLevelDelta = answerMode == .choice ? 0.5 : 1
        store.update(
            entryID: question.entryID,
            grade: grade,
            learner: learner,
            correctLevelDelta: correctLevelDelta
        )
        feedback = FeedbackState(grade: grade, expectedAnswer: question.expectedAnswer)
        lastEntryID = question.entryID
        nextQuestion()
    }

    private func nextQuestion() {
        answerText = ""
        guard !session.isEmpty else {
            currentQuestion = nil
            remaining = 0
            return
        }

        let entry = session.removeFirst()
        remaining = session.count + 1
        let direction = nextDirection()
        currentQuestion = engine.makeQuestion(
            entry: entry,
            direction: direction,
            allEntries: store.entries,
            optionsCount: answerMode == .choice ? 5 : 0
        )
    }

    private func nextDirection() -> QuestionDirection {
        switch directionMode {
        case .germanToNorwegian:
            return .germanToNorwegian
        case .norwegianToGerman:
            return .norwegianToGerman
        case .alternating:
            let direction: QuestionDirection = directionIndex.isMultiple(of: 2) ? .germanToNorwegian : .norwegianToGerman
            directionIndex += 1
            return direction
        }
    }

    public static var defaultAnswerMode: AnswerMode {
        #if os(iOS)
        .choice
        #else
        .typed
        #endif
    }
}

public struct FeedbackState: Equatable, Identifiable {
    public let id = UUID()
    public let grade: AnswerGrade
    public let expectedAnswer: String

    public init(grade: AnswerGrade, expectedAnswer: String) {
        self.grade = grade
        self.expectedAnswer = expectedAnswer
    }

    public var title: String {
        switch grade {
        case .correct:
            "Richtig"
        case .almost:
            "Fast richtig"
        case .wrong:
            "Falsch"
        }
    }

    public var emoji: String {
        switch grade {
        case .correct:
            "✅"
        case .almost:
            "✨"
        case .wrong:
            "❄️"
        }
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

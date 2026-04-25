import Foundation

@MainActor
public final class TrainerViewModel: ObservableObject {
    @Published public var learner: Learner = .papa
    @Published public var filter = TrainingFilter()
    @Published public var currentQuestion: TrainingQuestion?
    @Published public var answerText = ""
    @Published public var feedback = ""
    @Published public var sessionSize = 10
    @Published public var remaining = 0

    public let store: VocabularyStore
    public let auth: AuthCoordinator
    private let engine = TrainingEngine()
    private var session: [VocabularyEntry] = []
    private var directionIndex = 0
    private var lastEntryID: String?

    public init(store: VocabularyStore, auth: AuthCoordinator = AuthCoordinator()) {
        self.store = store
        self.auth = auth
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
        startSession(singleQuestion: Self.usesChoiceMode)
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

    public func startSession(singleQuestion: Bool = false) {
        session = engine.makeSession(
            from: store.entries,
            learner: learner,
            filter: filter,
            count: singleQuestion ? 1 : sessionSize,
            lastEntryID: lastEntryID
        )
        remaining = session.count
        feedback = ""
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
        store.update(entryID: question.entryID, grade: grade, learner: learner)
        feedback = "\(grade.rawValue.capitalized): \(question.expectedAnswer)"
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
        let direction: QuestionDirection = directionIndex.isMultiple(of: 2) ? .germanToNorwegian : .norwegianToGerman
        directionIndex += 1
        currentQuestion = engine.makeQuestion(
            entry: entry,
            direction: direction,
            allEntries: store.entries,
            optionsCount: Self.usesChoiceMode ? 5 : 0
        )
    }

    public static var usesChoiceMode: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

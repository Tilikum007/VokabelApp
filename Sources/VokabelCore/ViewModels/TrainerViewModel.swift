import Foundation
import Combine

@MainActor
public final class TrainerViewModel: ObservableObject {
    @Published public var learner: Learner = .papa {
        didSet {
            normalizeFilter(for: store.entries)
        }
    }
    @Published public var filter = TrainingFilter() {
        didSet {
            guard !isNormalizingFilter else { return }
            normalizeFilter(for: store.entries)
        }
    }
    @Published public var currentQuestion: TrainingQuestion?
    @Published public var answerText = ""
    @Published public var feedback: FeedbackState?
    @Published public var sessionSize = 10
    @Published public var sessionTotal = 0
    @Published public var correctCount = 0
    @Published public var wrongCount = 0
    @Published public var remaining = 0
    @Published public var directionMode: DirectionMode = .germanToNorwegian
    @Published public var answerMode: AnswerMode
    @Published public private(set) var sessionMessage: String?

    public let store: VocabularyStore
    public let auth: AuthCoordinator
    private let engine = TrainingEngine()
    private var session: [VocabularyEntry] = []
    private var directionIndex = 0
    private var lastEntryID: String?
    private var cancellables = Set<AnyCancellable>()
    private var isNormalizingFilter = false

    public init(store: VocabularyStore, auth: AuthCoordinator = AuthCoordinator()) {
        self.store = store
        self.auth = auth
        self.answerMode = TrainerViewModel.defaultAnswerMode

        store.$entries
            .receive(on: RunLoop.main)
            .sink { [weak self] entries in
                guard let self else { return }
                self.normalizeFilter(for: entries)
                self.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    public var sources: [String] {
        store.entries
            .flatMap(\.sourceTokens)
            .filter { !$0.isEmpty }
            .uniqued()
            .sorted()
    }

    public var lessons: [String] {
        entriesMatching(source: filter.source)
            .map(\.lesson)
            .filter { !$0.isEmpty }
            .uniqued()
            .sorted()
    }

    public var levels: [Int] {
        levelBuckets(for: entriesMatching(source: filter.source, lesson: filter.lesson))
    }

    public var sessionSizeOptions: [Int] {
        [5, 10, 15, 20, 30, 50]
    }

    public func load() async {
        await auth.restoreSavedLogin()
        await store.loadBundledSampleIfNeeded()
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

    public func checkVocabularyUpdates() async {
        guard let accessToken = auth.accessToken else {
            store.setSyncMessage("Bitte zuerst mit Google anmelden")
            return
        }

        await store.checkForVocabularyUpdates(accessToken: accessToken)
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
        sessionTotal = session.count
        correctCount = 0
        wrongCount = 0
        remaining = session.count
        feedback = nil
        directionIndex = 0
        sessionMessage = sessionMessage(for: session.count)
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
        if grade == .correct {
            correctCount += 1
        } else {
            wrongCount += 1
        }
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

    private func normalizeFilter(for entries: [VocabularyEntry]) {
        var normalizedFilter = filter
        let availableSources = Set(entries.filter(\.isActive).flatMap(\.sourceTokens).filter { !$0.isEmpty })

        if let source = normalizedFilter.source, !availableSources.contains(source) {
            normalizedFilter.source = nil
        }

        let availableLessons = Set(
            entriesMatching(source: normalizedFilter.source, in: entries)
                .map(\.lesson)
                .filter { !$0.isEmpty }
        )

        if let lesson = normalizedFilter.lesson, !availableLessons.contains(lesson) {
            normalizedFilter.lesson = nil
        }

        let availableLevels = Set(
            levelBuckets(for: entriesMatching(source: normalizedFilter.source, lesson: normalizedFilter.lesson, in: entries))
        )

        if let level = normalizedFilter.level, !availableLevels.contains(level) {
            normalizedFilter.level = nil
        }

        guard normalizedFilter != filter else { return }
        isNormalizingFilter = true
        filter = normalizedFilter
        isNormalizingFilter = false
    }

    private func entriesMatching(source: String? = nil, lesson: String? = nil, in entries: [VocabularyEntry]? = nil) -> [VocabularyEntry] {
        (entries ?? store.entries).filter { entry in
            guard entry.isActive else { return false }
            if let source, !entry.sourceTokens.contains(source) { return false }
            if let lesson, entry.lesson != lesson { return false }
            return true
        }
    }

    private func levelBuckets(for entries: [VocabularyEntry]) -> [Int] {
        entries
            .filter(\.isActive)
            .map { Int($0.level(for: learner).rounded(.down)) }
            .uniqued()
            .sorted()
    }

    private func sessionMessage(for count: Int) -> String? {
        guard count == 0 else { return nil }
        guard !store.entries.isEmpty else { return "Keine Vokabeln geladen." }

        if filter.source != nil || filter.lesson != nil || filter.level != nil {
            return "Keine passenden Vokabeln fuer die aktuellen Filter."
        }

        return "Keine aktiven Vokabeln verfuegbar."
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

    public var characterImageName: String {
        switch grade {
        case .correct:
            "cheer"
        case .almost:
            "wave"
        case .wrong:
            "down"
        }
    }

    public var characterTitle: String {
        switch grade {
        case .correct:
            "Bra!"
        case .almost:
            "Nesten!"
        case .wrong:
            "Proev igjen!"
        }
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

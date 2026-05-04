import Foundation
import Combine

@MainActor
public final class TrainerViewModel: ObservableObject {
    @Published public var learner: Learner = .papa {
        didSet {
            UserDefaults.standard.set(learner.rawValue, forKey: Self.learnerDefaultsKey)
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
    @Published public var selectedArticle = ""
    @Published public var selectedChoice = ""
    @Published public var feedback: FeedbackState?
    @Published public var sessionSize = 10 {
        didSet {
            UserDefaults.standard.set(sessionSize, forKey: Self.sessionSizeDefaultsKey)
        }
    }
    @Published public var sessionTotal = 0
    @Published public var correctCount = 0
    @Published public var wrongCount = 0
    @Published public var remaining = 0
    @Published public var directionMode: DirectionMode = .germanToNorwegian {
        didSet {
            UserDefaults.standard.set(directionMode.rawValue, forKey: Self.directionModeDefaultsKey)
        }
    }
    @Published public var trainingFocus: TrainingFocus = .vocabulary {
        didSet {
            UserDefaults.standard.set(trainingFocus.rawValue, forKey: Self.trainingFocusDefaultsKey)
        }
    }
    @Published public var answerMode: AnswerMode {
        didSet {
            UserDefaults.standard.set(answerMode.rawValue, forKey: Self.answerModeDefaultsKey)
        }
    }
    @Published public private(set) var sessionMessage: String?
    @Published public private(set) var sessionMistakes: [SessionMistake] = []
    @Published public private(set) var masterValidationReport: MasterValidationReport?

    public let store: VocabularyStore
    public let auth: AuthCoordinator
    private let engine = TrainingEngine()
    private let validator = MasterValidator()
    private var session: [VocabularyEntry] = []
    private var directionIndex = 0
    private var lastEntryID: String?
    private var cancellables = Set<AnyCancellable>()
    private var isNormalizingFilter = false

    private static let learnerDefaultsKey = "de.papa.vokabelapp.settings.learner"
    private static let directionModeDefaultsKey = "de.papa.vokabelapp.settings.directionMode"
    private static let trainingFocusDefaultsKey = "de.papa.vokabelapp.settings.trainingFocus"
    private static let answerModeDefaultsKey = "de.papa.vokabelapp.settings.answerMode"
    private static let sessionSizeDefaultsKey = "de.papa.vokabelapp.settings.sessionSize"

    public init(store: VocabularyStore, auth: AuthCoordinator = AuthCoordinator()) {
        self.store = store
        self.auth = auth
        self.learner = Self.persistedLearner
        self.directionMode = Self.persistedDirectionMode
        self.trainingFocus = Self.persistedTrainingFocus
        self.answerMode = Self.persistedAnswerMode
        self.sessionSize = Self.persistedSessionSize

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
        await store.syncWithBackend()
    }

    public func uploadNow() async {
        await store.syncWithBackend()
    }

    public func checkVocabularyUpdates() async {
        await store.checkForBackendVocabularyUpdates()
    }

    public func signInAndSync() async {
        await syncNow()
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
            lastEntryID: lastEntryID,
            focus: trainingFocus
        )
        sessionTotal = session.count
        correctCount = 0
        wrongCount = 0
        remaining = session.count
        feedback = nil
        sessionMistakes = []
        directionIndex = 0
        sessionMessage = sessionMessage(for: session.count)
        nextQuestion()
    }

    public func submitTypedAnswer() {
        guard let question = currentQuestion else { return }
        let grade: AnswerGrade
        if question.asksOnlyArticle {
            grade = engine.gradeArticle(answer: selectedArticle, expected: question.expectedArticle)
        } else if question.requiresArticle {
            grade = engine.grade(
                answer: answerText,
                expected: question.expectedAnswer,
                articleAnswer: selectedArticle,
                expectedArticle: question.expectedArticle
            )
        } else {
            grade = engine.grade(answer: answerText, expected: question.expectedAnswer)
        }
        submit(grade: grade)
    }

    public func choose(_ option: String) {
        guard let question = currentQuestion else { return }
        guard !question.requiresArticle else {
            chooseWord(option)
            return
        }
        submit(grade: option == question.expectedAnswer ? .correct : .wrong)
    }

    public func chooseWord(_ option: String) {
        selectedChoice = option
    }

    public func chooseArticle(_ option: String) {
        selectedArticle = option
    }

    public func submitChoiceAnswer() {
        guard let question = currentQuestion else { return }
        if question.asksOnlyArticle {
            guard !selectedArticle.isEmpty else { return }
            submit(grade: engine.gradeArticle(answer: selectedArticle, expected: question.expectedArticle))
            return
        }
        guard question.requiresArticle else {
            guard !selectedChoice.isEmpty else { return }
            submit(grade: selectedChoice == question.expectedAnswer ? .correct : .wrong)
            return
        }
        guard !selectedChoice.isEmpty, !selectedArticle.isEmpty else { return }
        let wordCorrect = selectedChoice == question.expectedAnswer
        let articleCorrect = engine.gradeArticle(answer: selectedArticle, expected: question.expectedArticle) == .correct
        submit(grade: wordCorrect && articleCorrect ? .correct : .wrong)
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
        feedback = FeedbackState(
            grade: grade,
            expectedAnswer: question.expectedDisplayAnswer,
            exampleNO: question.exampleNO,
            exampleDE: question.exampleDE
        )
        if grade != .correct {
            sessionMistakes.append(SessionMistake(
                entryID: question.entryID,
                prompt: question.prompt,
                expectedAnswer: question.expectedDisplayAnswer,
                givenAnswer: currentGivenAnswer(for: question),
                exampleNO: question.exampleNO,
                exampleDE: question.exampleDE
            ))
        }
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
        selectedArticle = ""
        selectedChoice = ""
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
            optionsCount: answerMode == .choice ? 5 : 0,
            focus: trainingFocus
        )
    }

    private func nextDirection() -> QuestionDirection {
        guard trainingFocus == .vocabulary else { return .germanToNorwegian }
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

    public func validateMaster() {
        masterValidationReport = validator.validate(store.entries)
    }

    public func retryMistakes() {
        let mistakeIDs = Set(sessionMistakes.map(\.entryID))
        let pool = store.entries.filter { mistakeIDs.contains($0.id) }
        guard !pool.isEmpty else { return }
        session = Array(pool.prefix(sessionSize))
        sessionTotal = session.count
        correctCount = 0
        wrongCount = 0
        remaining = session.count
        feedback = nil
        sessionMistakes = []
        sessionMessage = sessionMessage(for: session.count)
        nextQuestion()
    }

    private func currentGivenAnswer(for question: TrainingQuestion) -> String {
        if question.asksOnlyArticle {
            return selectedArticle.isEmpty ? "keine Auswahl" : selectedArticle
        }

        if answerMode == .choice {
            if question.requiresArticle {
                let article = selectedArticle.isEmpty ? "kein Artikel" : selectedArticle
                let word = selectedChoice.isEmpty ? "kein Wort" : selectedChoice
                return "\(article) \(word)"
            }
            return selectedChoice.isEmpty ? "keine Auswahl" : selectedChoice
        }

        if question.requiresArticle {
            let article = selectedArticle.isEmpty ? "kein Artikel" : selectedArticle
            return "\(article) \(answerText)"
        }
        return answerText
    }

    public static var defaultAnswerMode: AnswerMode {
        #if os(iOS)
        .choice
        #else
        .typed
        #endif
    }

    private static var persistedLearner: Learner {
        guard let rawValue = UserDefaults.standard.string(forKey: learnerDefaultsKey),
              let learner = Learner(rawValue: rawValue) else {
            return .papa
        }
        return learner
    }

    private static var persistedDirectionMode: DirectionMode {
        guard let rawValue = UserDefaults.standard.string(forKey: directionModeDefaultsKey),
              let mode = DirectionMode(rawValue: rawValue) else {
            return .germanToNorwegian
        }
        return mode
    }

    private static var persistedTrainingFocus: TrainingFocus {
        guard let rawValue = UserDefaults.standard.string(forKey: trainingFocusDefaultsKey),
              let focus = TrainingFocus(rawValue: rawValue) else {
            return .vocabulary
        }
        return focus
    }

    private static var persistedAnswerMode: AnswerMode {
        guard let rawValue = UserDefaults.standard.string(forKey: answerModeDefaultsKey),
              let mode = AnswerMode(rawValue: rawValue) else {
            return defaultAnswerMode
        }
        return mode
    }

    private static var persistedSessionSize: Int {
        let value = UserDefaults.standard.integer(forKey: sessionSizeDefaultsKey)
        guard value > 0 else { return 10 }
        return value
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
    public let exampleNO: String
    public let exampleDE: String

    public init(grade: AnswerGrade, expectedAnswer: String, exampleNO: String = "", exampleDE: String = "") {
        self.grade = grade
        self.expectedAnswer = expectedAnswer
        self.exampleNO = exampleNO
        self.exampleDE = exampleDE
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

import Foundation

public struct TrainingEngine {
    public init() {}

    public func eligibleEntries(
        from entries: [VocabularyEntry],
        learner: Learner,
        filter: TrainingFilter
    ) -> [VocabularyEntry] {
        entries.filter { entry in
            guard entry.isActive else { return false }
            if let level = filter.level {
                let entryLevel = entry.level(for: learner)
                guard entryLevel >= Double(level), entryLevel <= Double(level) + 0.5 else { return false }
            }
            if let source = filter.source, !source.isEmpty, !entry.sourceTokens.contains(source) { return false }
            if let lesson = filter.lesson, !lesson.isEmpty, entry.lesson != lesson { return false }
            return true
        }
    }

    public func makeSession(
        from entries: [VocabularyEntry],
        learner: Learner,
        filter: TrainingFilter,
        count: Int,
        lastEntryID: String? = nil,
        focus: TrainingFocus = .vocabulary
    ) -> [VocabularyEntry] {
        let pool = eligibleEntries(from: entries, learner: learner, filter: filter)
            .filter { $0.id != lastEntryID }
            .filter { focus == .vocabulary || !$0.article.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        return pool.sorted { left, right in
            let leftScore = score(left, learner: learner)
            let rightScore = score(right, learner: learner)
            if leftScore == rightScore { return left.id < right.id }
            return leftScore < rightScore
        }
        .prefix(count)
        .map { $0 }
    }

    public func makeQuestion(
        entry: VocabularyEntry,
        direction: QuestionDirection,
        allEntries: [VocabularyEntry],
        optionsCount: Int,
        focus: TrainingFocus = .vocabulary
    ) -> TrainingQuestion {
        if focus == .articles {
            let expectedArticle = cleanArticle(entry.article)
            return TrainingQuestion(
                entryID: entry.id,
                prompt: entry.german,
                promptDetail: entry.norwegian,
                expectedAnswer: expectedArticle,
                expectedArticle: expectedArticle,
                direction: .germanToNorwegian,
                focus: .articles,
                options: [],
                articleOptions: makeArticleOptions(expectedArticle: expectedArticle, entries: allEntries),
                exampleNO: entry.exampleNO,
                exampleDE: entry.exampleDE
            )
        }

        let expected = direction == .germanToNorwegian ? entry.norwegian : entry.german
        let expectedArticle = direction == .germanToNorwegian ? cleanArticle(entry.article) : ""
        let prompt = direction == .germanToNorwegian ? entry.german : norwegianPrompt(for: entry)
        let distractors = allEntries
            .filter { $0.id != entry.id && $0.isActive }
            .map { direction == .germanToNorwegian ? $0.norwegian : $0.german }
            .filter { !$0.isEmpty && $0 != expected }
            .uniqued()
            .shuffled()
            .prefix(max(0, optionsCount - 1))
        let articleOptions = makeArticleOptions(expectedArticle: expectedArticle, entries: allEntries)

        return TrainingQuestion(
            entryID: entry.id,
            prompt: prompt,
            promptDetail: "",
            expectedAnswer: expected,
            expectedArticle: expectedArticle,
            direction: direction,
            focus: .vocabulary,
            options: ([expected] + distractors).shuffled(),
            articleOptions: articleOptions,
            exampleNO: entry.exampleNO,
            exampleDE: entry.exampleDE
        )
    }

    public func grade(answer: String, expected: String) -> AnswerGrade {
        let normalizedAnswer = normalize(answer)
        let normalizedExpected = normalize(expected)
        guard normalizedAnswer != normalizedExpected else { return .correct }

        if normalizedExpected.contains(normalizedAnswer) || normalizedAnswer.contains(normalizedExpected) {
            return .almost
        }

        return levenshtein(normalizedAnswer, normalizedExpected) <= 2 ? .almost : .wrong
    }

    public func gradeArticle(answer: String, expected: String) -> AnswerGrade {
        let normalizedAnswer = normalizeArticle(answer)
        let normalizedExpected = normalizeArticle(expected)
        guard !normalizedExpected.isEmpty else { return .correct }
        return normalizedAnswer == normalizedExpected ? .correct : .wrong
    }

    public func grade(answer: String, expected: String, articleAnswer: String, expectedArticle: String) -> AnswerGrade {
        let wordGrade = grade(answer: answer, expected: expected)
        let articleGrade = gradeArticle(answer: articleAnswer, expected: expectedArticle)

        if wordGrade == .correct && articleGrade == .correct {
            return .correct
        }

        if wordGrade == .wrong || articleGrade == .wrong {
            return .wrong
        }

        return .almost
    }

    private func score(_ entry: VocabularyEntry, learner: Learner) -> Double {
        let last = learner == .papa ? entry.lastPapa : entry.lastMama
        let wrong = learner == .papa ? entry.wrongPapa : entry.wrongMama
        let correct = learner == .papa ? entry.correctPapa : entry.correctMama
        let staleBonus = last.isEmpty ? -10.0 : 0.0
        let weaknessBonus = Double(wrong * 3) - Double(correct)
        return entry.level(for: learner) * 10 + staleBonus - weaknessBonus
    }

    private func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    private func cleanArticle(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeArticle(_ value: String) -> String {
        cleanArticle(value)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
    }

    private func makeArticleOptions(expectedArticle: String, entries: [VocabularyEntry]) -> [String] {
        guard !expectedArticle.isEmpty else { return [] }
        let base = ["en", "et", "en/ei"]
        let dynamic = entries
            .map { cleanArticle($0.article) }
            .filter { !$0.isEmpty }
        return ([expectedArticle] + base + dynamic)
            .uniqued()
            .sorted { left, right in
                if left == expectedArticle { return true }
                if right == expectedArticle { return false }
                return left < right
            }
    }

    private func norwegianPrompt(for entry: VocabularyEntry) -> String {
        let article = cleanArticle(entry.article)
        guard !article.isEmpty else { return entry.norwegian }
        return "\(article) \(entry.norwegian)"
    }

    private func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a)
        let b = Array(b)
        var distances = Array(0...b.count)

        for (i, characterA) in a.enumerated() {
            var previous = i
            distances[0] = i + 1
            for (j, characterB) in b.enumerated() {
                let old = distances[j + 1]
                if characterA == characterB {
                    distances[j + 1] = previous
                } else {
                    distances[j + 1] = min(previous, distances[j], distances[j + 1]) + 1
                }
                previous = old
            }
        }

        return distances[b.count]
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

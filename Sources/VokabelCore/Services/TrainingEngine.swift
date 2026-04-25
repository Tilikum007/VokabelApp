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
            if let level = filter.level, entry.level(for: learner) != level { return false }
            if let source = filter.source, !source.isEmpty, entry.source != source { return false }
            if let lesson = filter.lesson, !lesson.isEmpty, entry.lesson != lesson { return false }
            return true
        }
    }

    public func makeSession(
        from entries: [VocabularyEntry],
        learner: Learner,
        filter: TrainingFilter,
        count: Int,
        lastEntryID: String? = nil
    ) -> [VocabularyEntry] {
        let pool = eligibleEntries(from: entries, learner: learner, filter: filter)
            .filter { $0.id != lastEntryID }

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
        optionsCount: Int
    ) -> TrainingQuestion {
        let expected = direction == .germanToNorwegian ? entry.norwegian : entry.german
        let prompt = direction == .germanToNorwegian ? entry.german : entry.norwegian
        let distractors = allEntries
            .filter { $0.id != entry.id && $0.isActive }
            .map { direction == .germanToNorwegian ? $0.norwegian : $0.german }
            .filter { !$0.isEmpty && $0 != expected }
            .uniqued()
            .shuffled()
            .prefix(max(0, optionsCount - 1))

        return TrainingQuestion(
            entryID: entry.id,
            prompt: prompt,
            expectedAnswer: expected,
            direction: direction,
            options: ([expected] + distractors).shuffled()
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

    private func score(_ entry: VocabularyEntry, learner: Learner) -> Int {
        let last = learner == .papa ? entry.lastPapa : entry.lastMama
        let staleBonus = last.isEmpty ? -10 : 0
        return entry.level(for: learner) * 10 + staleBonus
    }

    private func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
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

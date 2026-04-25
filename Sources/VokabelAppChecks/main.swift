import VokabelCore

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fatalError(message)
    }
}

let engine = TrainingEngine()
check(engine.grade(answer: "takk", expected: "takk") == .correct, "Expected exact answer to be correct")
check(engine.grade(answer: "tak", expected: "takk") == .almost, "Expected near answer to be almost correct")
check(engine.grade(answer: "hund", expected: "takk") == .wrong, "Expected unrelated answer to be wrong")

var entry = VocabularyEntry(
    id: "NO0001",
    german: "danke",
    norwegian: "takk",
    partOfSpeech: "",
    source: "",
    lesson: "",
    levelPapa: 5,
    levelMama: 0,
    lastPapa: "",
    lastMama: "",
    lastResultPapa: "",
    lastResultMama: "",
    correctPapa: 0,
    wrongPapa: 0,
    correctMama: 0,
    wrongMama: 0,
    exampleNO: "",
    exampleDE: "",
    note: "",
    active: "ja"
)

entry.apply(.correct, learner: .papa)
entry.apply(.wrong, learner: .mama)

check(entry.levelPapa == 5, "Papa level should be capped at 5")
check(entry.correctPapa == 1, "Papa correct counter should increment")
check(entry.levelMama == 0, "Mama level should be floored at 0")
check(entry.wrongMama == 1, "Mama wrong counter should increment")

entry.levelPapa = 1
entry.apply(.correct, learner: .papa, correctLevelDelta: 0.5)
check(entry.levelPapa == 1.5, "Choice mode should increase level by half a point")

let filtered = engine.eligibleEntries(from: [entry], learner: .papa, filter: TrainingFilter(level: 1))
check(filtered.count == 1, "Level 1 filter should include level 1.5 entries")

print("VokabelApp checks passed")

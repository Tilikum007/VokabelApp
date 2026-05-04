import Foundation
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
check(engine.grade(answer: "bord", expected: "bord", articleAnswer: "et", expectedArticle: "et") == .correct, "Expected noun word and article to be correct")
check(engine.grade(answer: "bord", expected: "bord", articleAnswer: "en", expectedArticle: "et") == .wrong, "Expected wrong noun article to be wrong")

let codec = CSVCodec()
let crlf = String(UnicodeScalar(13)) + String(UnicodeScalar(10))
let csvWithCRLF = [
    "ID,Deutsch,Norwegisch,Artikel,Wortart,Herkunft,Lektion,Level_Papa,Level_Mama,Zuletzt_Papa,Zuletzt_Mama,Letztes_Ergebnis_Papa,Letztes_Ergebnis_Mama,Richtig_Papa,Falsch_Papa,Richtig_Mama,Falsch_Mama,Beispielsatz_NO,Beispielsatz_DE,Notiz,Aktiv",
    "NO1000,ja,ja,,,Sonstige; Norsk for deg,Lektion 1,0,0,,,,,0,0,0,0,,,,ja",
    "NO1001,nein,nei,,,Norsk for deg,Lektion 2,0,0,,,,,0,0,0,0,,,,ja"
].joined(separator: crlf)
let decodedCSV = try codec.decode(csvWithCRLF)
check(decodedCSV.count == 2, "CRLF CSV should decode into two rows")
check(decodedCSV[0].sourceTokens == ["Sonstige", "Norsk for deg"], "Source tokens should split semicolon-separated sources")

let legacyCSV = [
    "ID,Deutsch,Norwegisch,Wortart,Herkunft,Lektion,Level_Papa,Level_Mama,Zuletzt_Papa,Zuletzt_Mama,Letztes_Ergebnis_Papa,Letztes_Ergebnis_Mama,Richtig_Papa,Falsch_Papa,Richtig_Mama,Falsch_Mama,Beispielsatz_NO,Beispielsatz_DE,Notiz,Aktiv",
    "NO1002,Tisch,bord,,Sonstige,,0,0,,,,,0,0,0,0,,,,ja"
].joined(separator: "\n")
let decodedLegacyCSV = try codec.decode(legacyCSV)
check(decodedLegacyCSV.count == 1, "Legacy CSV without article should decode")
check(decodedLegacyCSV[0].article.isEmpty, "Legacy CSV should default article to empty")

let legacyArticleCSV = [
    "ID,Deutsch,Norwegisch,Wortart,Herkunft,Lektion,Level_Papa,Level_Mama,Zuletzt_Papa,Zuletzt_Mama,Letztes_Ergebnis_Papa,Letztes_Ergebnis_Mama,Richtig_Papa,Falsch_Papa,Richtig_Mama,Falsch_Mama,Beispielsatz_NO,Beispielsatz_DE,Notiz,Aktiv",
    "NO1003,Tag,\"dag, en\",Substantiv,Sonstige,,0,0,,,,,0,0,0,0,,,,ja"
].joined(separator: "\n")
let decodedLegacyArticleCSV = try codec.decode(legacyArticleCSV)
check(decodedLegacyArticleCSV[0].norwegian == "dag", "Legacy noun word should be stripped")
check(decodedLegacyArticleCSV[0].article == "en", "Legacy noun article should be migrated")

let legacyFeminineArticleCSV = [
    "ID,Deutsch,Norwegisch,Wortart,Herkunft,Lektion,Level_Papa,Level_Mama,Zuletzt_Papa,Zuletzt_Mama,Letztes_Ergebnis_Papa,Letztes_Ergebnis_Mama,Richtig_Papa,Falsch_Papa,Richtig_Mama,Falsch_Mama,Beispielsatz_NO,Beispielsatz_DE,Notiz,Aktiv",
    "NO1004,Frau,\"kvinne, ei\",Substantiv,Sonstige,,0,0,,,,,0,0,0,0,,,,ja"
].joined(separator: "\n")
let decodedLegacyFeminineArticleCSV = try codec.decode(legacyFeminineArticleCSV)
check(decodedLegacyFeminineArticleCSV[0].norwegian == "kvinne", "Legacy feminine noun word should be stripped")
check(decodedLegacyFeminineArticleCSV[0].article == "en/ei", "Legacy feminine noun article should normalize to en/ei")

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

let sourceFiltered = engine.eligibleEntries(
    from: decodedCSV,
    learner: .papa,
    filter: TrainingFilter(source: "Norsk for deg")
)
check(sourceFiltered.count == 2, "Source filter should match semicolon-separated origin tags")

let base = VocabularyEntry(
    id: "NO2000",
    german: "hallo",
    norwegian: "hei",
    partOfSpeech: "",
    source: "Norsk for deg",
    lesson: "Lektion 1",
    levelPapa: 1,
    levelMama: 0,
    lastPapa: "2026-04-26T10:00:00Z",
    lastMama: "",
    lastResultPapa: "richtig",
    lastResultMama: "",
    correctPapa: 1,
    wrongPapa: 0,
    correctMama: 0,
    wrongMama: 0,
    exampleNO: "",
    exampleDE: "",
    note: "",
    active: "ja"
)

let noun = VocabularyEntry(
    id: "NO2001",
    german: "Tisch",
    norwegian: "bord",
    article: "et",
    partOfSpeech: "Substantiv",
    source: "Norsk for deg",
    lesson: "Lektion 1",
    levelPapa: 1,
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

let nounQuestion = engine.makeQuestion(entry: noun, direction: .germanToNorwegian, allEntries: [base, noun], optionsCount: 5)
check(nounQuestion.requiresArticle, "Norwegian noun answers should require an article")
check(nounQuestion.expectedAnswer == "bord", "Norwegian noun answer should contain only the word")
check(nounQuestion.expectedArticle == "et", "Norwegian noun article should be separate")
check(nounQuestion.articleOptions.contains("et"), "Article options should contain the expected article")

let nounDistractorEntries = [
    noun,
    VocabularyEntry(id: "NO2002", german: "Stuhl", norwegian: "stol", article: "en", partOfSpeech: "Substantiv", source: "", lesson: "", levelPapa: 0, levelMama: 0, lastPapa: "", lastMama: "", lastResultPapa: "", lastResultMama: "", correctPapa: 0, wrongPapa: 0, correctMama: 0, wrongMama: 0, exampleNO: "", exampleDE: "", note: "", active: "ja"),
    VocabularyEntry(id: "NO2003", german: "Haus", norwegian: "hus", article: "et", partOfSpeech: "Substantiv", source: "", lesson: "", levelPapa: 0, levelMama: 0, lastPapa: "", lastMama: "", lastResultPapa: "", lastResultMama: "", correctPapa: 0, wrongPapa: 0, correctMama: 0, wrongMama: 0, exampleNO: "", exampleDE: "", note: "", active: "ja"),
    VocabularyEntry(id: "NO2004", german: "Auto", norwegian: "bil", article: "en", partOfSpeech: "Substantiv", source: "", lesson: "", levelPapa: 0, levelMama: 0, lastPapa: "", lastMama: "", lastResultPapa: "", lastResultMama: "", correctPapa: 0, wrongPapa: 0, correctMama: 0, wrongMama: 0, exampleNO: "", exampleDE: "", note: "", active: "ja"),
    VocabularyEntry(id: "NO2005", german: "Buch", norwegian: "bok", article: "en/ei", partOfSpeech: "Substantiv", source: "", lesson: "", levelPapa: 0, levelMama: 0, lastPapa: "", lastMama: "", lastResultPapa: "", lastResultMama: "", correctPapa: 0, wrongPapa: 0, correctMama: 0, wrongMama: 0, exampleNO: "", exampleDE: "", note: "", active: "ja"),
    VocabularyEntry(id: "NO2006", german: "gehen", norwegian: "gå", partOfSpeech: "Verb", source: "", lesson: "", levelPapa: 0, levelMama: 0, lastPapa: "", lastMama: "", lastResultPapa: "", lastResultMama: "", correctPapa: 0, wrongPapa: 0, correctMama: 0, wrongMama: 0, exampleNO: "", exampleDE: "", note: "", active: "ja")
]
let nounChoiceQuestion = engine.makeQuestion(entry: noun, direction: .germanToNorwegian, allEntries: nounDistractorEntries, optionsCount: 5)
check(!nounChoiceQuestion.options.contains("gå"), "Noun choice distractors should prefer nouns when enough noun options exist")

let articleQuestion = engine.makeQuestion(entry: noun, direction: .germanToNorwegian, allEntries: [base, noun], optionsCount: 5, focus: .articles)
check(articleQuestion.asksOnlyArticle, "Article training should ask only for the article")
check(articleQuestion.expectedAnswer == "et", "Article training expected answer should be the article")

let validator = MasterValidator()
let cleanReport = validator.validate([noun])
check(cleanReport.issues.isEmpty, "Clean noun entry should pass master validation")

var invalidNoun = noun
invalidNoun.article = "ei"
let invalidReport = validator.validate([invalidNoun])
check(!invalidReport.issues.isEmpty, "Invalid article values should be reported")

let catalogCSV = codec.encodeCatalog([base])
let catalogDecoded = try codec.decode(catalogCSV)
check(catalogDecoded.count == 1, "Catalog CSV should decode")
check(catalogDecoded[0].levelPapa == 0 && catalogDecoded[0].levelMama == 0, "Catalog CSV should not persist progress values")

var progressApplied = base.strippingProgress
let events = [
    ProgressEvent(
        id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEE1")!,
        entryID: base.id,
        learner: .papa,
        timestamp: ISO8601DateFormatter().date(from: "2026-04-26T10:00:00Z")!,
        grade: .correct,
        correctLevelDelta: 1
    ),
    ProgressEvent(
        id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEE2")!,
        entryID: base.id,
        learner: .papa,
        timestamp: ISO8601DateFormatter().date(from: "2026-04-26T10:05:00Z")!,
        grade: .correct,
        correctLevelDelta: 0.5
    ),
    ProgressEvent(
        id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEE3")!,
        entryID: base.id,
        learner: .mama,
        timestamp: ISO8601DateFormatter().date(from: "2026-04-26T10:06:00Z")!,
        grade: .wrong,
        correctLevelDelta: 1
    )
]

for event in events.sorted(by: { $0.timestamp < $1.timestamp }) {
    progressApplied.apply(
        event.grade,
        learner: event.learner,
        correctLevelDelta: event.correctLevelDelta,
        date: event.timestamp
    )
}

check(progressApplied.levelPapa == 1.5, "Progress events should rebuild Papa level correctly")
check(progressApplied.correctPapa == 2, "Progress events should rebuild Papa correct counter")
check(progressApplied.wrongMama == 1, "Progress events should rebuild Mama wrong counter")

print("VokabelApp checks passed")

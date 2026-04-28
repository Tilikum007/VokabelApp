import Foundation

public enum CSVCodecError: Error, Equatable {
    case missingHeader
    case invalidColumnCount(row: Int, expected: Int, actual: Int)
}

public struct CSVCodec {
    public static let header = [
        "ID", "Deutsch", "Norwegisch", "Artikel", "Wortart", "Herkunft", "Lektion",
        "Level_Papa", "Level_Mama", "Zuletzt_Papa", "Zuletzt_Mama",
        "Letztes_Ergebnis_Papa", "Letztes_Ergebnis_Mama",
        "Richtig_Papa", "Falsch_Papa", "Richtig_Mama", "Falsch_Mama",
        "Beispielsatz_NO", "Beispielsatz_DE", "Notiz", "Aktiv"
    ]
    public static let catalogHeader = [
        "ID", "Deutsch", "Norwegisch", "Artikel", "Wortart", "Herkunft", "Lektion",
        "Beispielsatz_NO", "Beispielsatz_DE", "Notiz", "Aktiv"
    ]

    public init() {}

    public func decode(_ text: String) throws -> [VocabularyEntry] {
        let rows = parseRows(text)
        guard let first = rows.first else { throw CSVCodecError.missingHeader }
        let normalizedHeader = first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\u{feff}", with: "") }
        let expected = normalizedHeader.count

        return try rows.dropFirst().enumerated().compactMap { offset, row in
            guard row.contains(where: { !$0.isEmpty }) else { return nil }
            guard row.count == expected else {
                throw CSVCodecError.invalidColumnCount(row: offset + 2, expected: expected, actual: row.count)
            }

            var values = Dictionary(uniqueKeysWithValues: zip(normalizedHeader, row))
            let entry = VocabularyEntry(
                id: values.removeValue(forKey: "ID") ?? "",
                german: values.removeValue(forKey: "Deutsch") ?? "",
                norwegian: values.removeValue(forKey: "Norwegisch") ?? "",
                article: values.removeValue(forKey: "Artikel") ?? "",
                partOfSpeech: values.removeValue(forKey: "Wortart") ?? "",
                source: values.removeValue(forKey: "Herkunft") ?? "",
                lesson: values.removeValue(forKey: "Lektion") ?? "",
                levelPapa: Self.decodeLevel(values.removeValue(forKey: "Level_Papa") ?? ""),
                levelMama: Self.decodeLevel(values.removeValue(forKey: "Level_Mama") ?? ""),
                lastPapa: values.removeValue(forKey: "Zuletzt_Papa") ?? "",
                lastMama: values.removeValue(forKey: "Zuletzt_Mama") ?? "",
                lastResultPapa: values.removeValue(forKey: "Letztes_Ergebnis_Papa") ?? "",
                lastResultMama: values.removeValue(forKey: "Letztes_Ergebnis_Mama") ?? "",
                correctPapa: Int(values.removeValue(forKey: "Richtig_Papa") ?? "") ?? 0,
                wrongPapa: Int(values.removeValue(forKey: "Falsch_Papa") ?? "") ?? 0,
                correctMama: Int(values.removeValue(forKey: "Richtig_Mama") ?? "") ?? 0,
                wrongMama: Int(values.removeValue(forKey: "Falsch_Mama") ?? "") ?? 0,
                exampleNO: values.removeValue(forKey: "Beispielsatz_NO") ?? "",
                exampleDE: values.removeValue(forKey: "Beispielsatz_DE") ?? "",
                note: values.removeValue(forKey: "Notiz") ?? "",
                active: values.removeValue(forKey: "Aktiv") ?? "ja"
            )
            return Self.separateLegacyArticle(in: entry)
        }
    }

    public func encode(_ entries: [VocabularyEntry]) -> String {
        let lines = [Self.header] + entries.map { entry in
            [
                entry.id, entry.german, entry.norwegian, entry.article, entry.partOfSpeech, entry.normalizedSource, entry.normalizedLesson,
                Self.encodeLevel(entry.levelPapa), Self.encodeLevel(entry.levelMama), entry.lastPapa, entry.lastMama,
                entry.lastResultPapa, entry.lastResultMama, String(entry.correctPapa), String(entry.wrongPapa),
                String(entry.correctMama), String(entry.wrongMama), entry.exampleNO, entry.exampleDE,
                entry.note, entry.active.isEmpty ? "ja" : entry.active
            ]
        }

        return lines.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    public func encodeCatalog(_ entries: [VocabularyEntry]) -> String {
        let lines = [Self.catalogHeader] + entries.map { entry in
            [
                entry.id,
                entry.german,
                entry.norwegian,
                entry.article,
                entry.partOfSpeech,
                entry.normalizedSource,
                entry.normalizedLesson,
                entry.exampleNO,
                entry.exampleDE,
                entry.note,
                entry.active.isEmpty ? "ja" : entry.active
            ]
        }

        return lines.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    private func parseRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let scalars = Array(text.unicodeScalars)
        var index = 0

        while index < scalars.count {
            let scalar = scalars[index]

            if scalar == "\"" {
                let nextIndex = index + 1
                if inQuotes, nextIndex < scalars.count, scalars[nextIndex] == "\"" {
                    field.append("\"")
                    index += 2
                    continue
                }

                inQuotes.toggle()
                index += 1
                continue
            }

            if scalar == ",", !inQuotes {
                row.append(field)
                field = ""
                index += 1
                continue
            }

            if !inQuotes && (scalar == "\r" || scalar == "\n") {
                if !field.isEmpty || !row.isEmpty {
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                }

                if scalar == "\r", index + 1 < scalars.count, scalars[index + 1] == "\n" {
                    index += 2
                } else {
                    index += 1
                }
                continue
            }

            field.unicodeScalars.append(scalar)
            index += 1
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }

        return rows
    }

    private func escape(_ value: String) -> String {
        let requiresQuotes = value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r")
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return requiresQuotes ? "\"\(escaped)\"" : escaped
    }

    private static func decodeLevel(_ value: String) -> Double {
        Double(value.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private static func encodeLevel(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }

    private static func separateLegacyArticle(in entry: VocabularyEntry) -> VocabularyEntry {
        guard entry.article.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return entry
        }

        let patterns = ["en/ei", "ei/en", "en", "ei", "et"]
        let norwegian = entry.norwegian.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let article = patterns.first(where: { norwegian.localizedCaseInsensitiveCompareSuffix(", \($0)") }) else {
            return entry
        }

        let suffixLength = article.count + 2
        let wordEnd = norwegian.index(norwegian.endIndex, offsetBy: -suffixLength)
        let word = norwegian[..<wordEnd].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return entry }

        var migrated = entry
        migrated.norwegian = String(word)
        migrated.article = article
        return migrated
    }
}

private extension String {
    func localizedCaseInsensitiveCompareSuffix(_ suffix: String) -> Bool {
        lowercased().hasSuffix(suffix.lowercased())
    }
}

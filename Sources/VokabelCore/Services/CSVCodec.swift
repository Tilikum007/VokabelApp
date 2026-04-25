import Foundation

public enum CSVCodecError: Error, Equatable {
    case missingHeader
    case invalidColumnCount(row: Int, expected: Int, actual: Int)
}

public struct CSVCodec {
    public static let header = [
        "ID", "Deutsch", "Norwegisch", "Wortart", "Herkunft", "Lektion",
        "Level_Papa", "Level_Mama", "Zuletzt_Papa", "Zuletzt_Mama",
        "Letztes_Ergebnis_Papa", "Letztes_Ergebnis_Mama",
        "Richtig_Papa", "Falsch_Papa", "Richtig_Mama", "Falsch_Mama",
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
            return VocabularyEntry(
                id: values.removeValue(forKey: "ID") ?? "",
                german: values.removeValue(forKey: "Deutsch") ?? "",
                norwegian: values.removeValue(forKey: "Norwegisch") ?? "",
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
        }
    }

    public func encode(_ entries: [VocabularyEntry]) -> String {
        let lines = [Self.header] + entries.map { entry in
            [
                entry.id, entry.german, entry.norwegian, entry.partOfSpeech, entry.source, entry.lesson,
                Self.encodeLevel(entry.levelPapa), Self.encodeLevel(entry.levelMama), entry.lastPapa, entry.lastMama,
                entry.lastResultPapa, entry.lastResultMama, String(entry.correctPapa), String(entry.wrongPapa),
                String(entry.correctMama), String(entry.wrongMama), entry.exampleNO, entry.exampleDE,
                entry.note, entry.active.isEmpty ? "ja" : entry.active
            ]
        }

        return lines.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    private func parseRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = Array(text).makeIterator()

        while let character = iterator.next() {
            if character == "\"" {
                if inQuotes, let next = iterator.next() {
                    if next == "\"" {
                        field.append("\"")
                    } else {
                        inQuotes = false
                        if next == "," {
                            row.append(field)
                            field = ""
                        } else if next == "\n" || next == "\r" {
                            row.append(field)
                            rows.append(row)
                            row = []
                            field = ""
                        } else {
                            field.append(next)
                        }
                    }
                } else {
                    inQuotes.toggle()
                }
            } else if character == ",", !inQuotes {
                row.append(field)
                field = ""
            } else if (character == "\n" || character == "\r"), !inQuotes {
                if !field.isEmpty || !row.isEmpty {
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                }
            } else {
                field.append(character)
            }
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
}

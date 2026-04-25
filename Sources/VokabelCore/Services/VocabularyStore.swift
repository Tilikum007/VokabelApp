import Foundation

@MainActor
public final class VocabularyStore: ObservableObject {
    @Published public private(set) var entries: [VocabularyEntry] = []
    @Published public private(set) var isSyncing = false
    @Published public private(set) var lastSyncMessage = "Noch nicht synchronisiert"

    private let codec = CSVCodec()
    private let localFileName: String
    private let driveFileID: String
    private let driveClient: GoogleDriveClient

    public init(localFileName: String, driveFileID: String, driveClient: GoogleDriveClient = GoogleDriveClient()) {
        self.localFileName = localFileName
        self.driveFileID = driveFileID
        self.driveClient = driveClient
    }

    public func loadBundledSampleIfNeeded() async {
        guard entries.isEmpty else { return }

        if let localText = try? String(contentsOf: localURL(), encoding: .utf8),
           let decoded = try? codec.decode(localText) {
            entries = decoded
            lastSyncMessage = "Lokale Datei geladen"
            return
        }

        if let bundledURL = Self.resourceBundle.url(forResource: "MASTER_vokabelheft_norwegisch", withExtension: "csv"),
           let bundledText = try? String(contentsOf: bundledURL, encoding: .utf8),
           let decoded = try? codec.decode(bundledText) {
            entries = decoded
            try? persist()
            lastSyncMessage = "Beispieldaten geladen"
        }
    }

    public func syncFromDrive(accessToken: String) async {
        isSyncing = true
        defer { isSyncing = false }

        do {
            let csv = try await driveClient.downloadCSV(fileID: driveFileID, accessToken: accessToken)
            entries = try codec.decode(csv)
            try persist()
            lastSyncMessage = "Von Google Drive geladen"
        } catch {
            lastSyncMessage = "Drive-Download fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    public func uploadToDrive(accessToken: String) async {
        isSyncing = true
        defer { isSyncing = false }

        do {
            let csv = codec.encode(entries)
            try await driveClient.uploadCSV(csv, fileID: driveFileID, accessToken: accessToken)
            try persist()
            lastSyncMessage = "Nach Google Drive hochgeladen"
        } catch {
            lastSyncMessage = "Drive-Upload fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    public func update(
        entryID: String,
        grade: AnswerGrade,
        learner: Learner,
        correctLevelDelta: Double = 1,
        date: Date = Date()
    ) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        entries[index].apply(grade, learner: learner, correctLevelDelta: correctLevelDelta, date: date)
        try? persist()
    }

    public func setSyncMessage(_ message: String) {
        lastSyncMessage = message
    }

    private func persist() throws {
        try FileManager.default.createDirectory(
            at: documentsURL(),
            withIntermediateDirectories: true
        )
        try codec.encode(entries).write(to: localURL(), atomically: true, encoding: .utf8)
    }

    private func documentsURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func localURL() -> URL {
        documentsURL().appendingPathComponent(localFileName)
    }

    private static var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle(for: BundleToken.self)
        #endif
    }
}

private final class BundleToken {}

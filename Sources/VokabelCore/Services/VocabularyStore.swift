import Foundation

@MainActor
public final class VocabularyStore: ObservableObject {
    @Published public private(set) var entries: [VocabularyEntry] = []
    @Published public private(set) var isSyncing = false
    @Published public private(set) var lastSyncMessage = "Noch nicht synchronisiert"
    @Published public private(set) var lastSyncResult: SyncResult = .idle
    @Published public private(set) var lastSyncDate: Date?

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
            setSyncMessage("Lokale Datei geladen", result: .success)
            return
        }

        if let bundledURL = Self.resourceBundle.url(forResource: "MASTER_vokabelheft_norwegisch", withExtension: "csv"),
           let bundledText = try? String(contentsOf: bundledURL, encoding: .utf8),
           let decoded = try? codec.decode(bundledText) {
            entries = decoded
            try? persist()
            setSyncMessage("Beispieldaten geladen", result: .success)
        }
    }

    public func syncFromDrive(accessToken: String) async {
        isSyncing = true
        setSyncMessage("Lade von Google Drive ...", result: .working)
        defer { isSyncing = false }

        do {
            let csv = try await driveClient.downloadCSV(fileID: driveFileID, accessToken: accessToken)
            entries = try codec.decode(csv)
            try persist()
            setSyncMessage("Von Google Drive geladen", result: .success)
        } catch {
            setSyncMessage("Drive-Download fehlgeschlagen: \(error.localizedDescription)", result: .failure)
        }
    }

    public func uploadToDrive(accessToken: String) async {
        isSyncing = true
        setSyncMessage("Speichere nach Google Drive ...", result: .working)
        defer { isSyncing = false }

        do {
            let csv = codec.encode(entries)
            try await driveClient.uploadCSV(csv, fileID: driveFileID, accessToken: accessToken)
            try persist()
            setSyncMessage("Nach Google Drive hochgeladen", result: .success)
        } catch {
            setSyncMessage("Drive-Upload fehlgeschlagen: \(error.localizedDescription)", result: .failure)
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
        setSyncMessage(message, result: .failure)
    }

    public func setSyncMessage(_ message: String, result: SyncResult) {
        lastSyncMessage = message
        lastSyncResult = result
        lastSyncDate = Date()
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

public enum SyncResult: Equatable {
    case idle
    case working
    case success
    case failure
}

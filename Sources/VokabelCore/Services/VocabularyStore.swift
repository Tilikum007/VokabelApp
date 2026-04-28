import Foundation

@MainActor
public final class VocabularyStore: ObservableObject {
    @Published public private(set) var entries: [VocabularyEntry] = []
    @Published public private(set) var isSyncing = false
    @Published public private(set) var lastSyncMessage = "Noch nicht synchronisiert"
    @Published public private(set) var lastSyncResult: SyncResult = .idle
    @Published public private(set) var lastSyncDate: Date?
    @Published public private(set) var lastVocabularyUpdateCheckDate: Date?
    @Published public private(set) var vocabularyUpdateSummary = "Noch nicht geprueft"

    private let codec = CSVCodec()
    private let localFileName: String
    private let legacyDriveFileID: String
    private let driveClient: GoogleDriveClient
    private let progressFolderName = "VokabelAppProgress"
    private let remoteMasterName = "MASTER_vokabelheft_norwegisch.csv"
    private let archivedMasterName = "MASTER_vokabelheft_norwegisch_alt.csv"
    private let deviceID: String

    private var catalogEntries: [VocabularyEntry] = []
    private var knownProgressEvents: [ProgressEvent] = []

    public init(localFileName: String, driveFileID: String, driveClient: GoogleDriveClient = GoogleDriveClient()) {
        self.localFileName = localFileName
        self.legacyDriveFileID = driveFileID
        self.driveClient = driveClient
        self.deviceID = Self.resolveDeviceID()
    }

    public func loadBundledSampleIfNeeded() async {
        guard entries.isEmpty else { return }

        if let catalogText = try? String(contentsOf: catalogLocalURL(), encoding: .utf8),
           let decoded = try? codec.decode(catalogText) {
            catalogEntries = decoded.map(\.strippingProgress)
            knownProgressEvents = loadCachedEvents()
            rebuildEntries()
            try? persistCatalog()
            setSyncMessage("Lokale Daten geladen", result: .success)
            return
        }

        if let bundledURL = Self.resourceBundle.url(forResource: "MASTER_vokabelheft_norwegisch", withExtension: "csv"),
           let bundledText = try? String(contentsOf: bundledURL, encoding: .utf8),
           let decoded = try? codec.decode(bundledText) {
            catalogEntries = decoded.map(\.strippingProgress)
            knownProgressEvents = loadCachedEvents()
            rebuildEntries()
            try? persistCatalog()
            try? persistProgressCache()
            setSyncMessage("Beispieldaten geladen", result: .success)
        }
    }

    public func syncFromDrive(accessToken: String) async {
        await synchronizeWithDrive(accessToken: accessToken)
    }

    public func uploadToDrive(accessToken: String) async {
        await synchronizeWithDrive(accessToken: accessToken)
    }

    public func checkForVocabularyUpdates(accessToken: String) async {
        isSyncing = true
        setSyncMessage("Suche nach neuen Vokabeln ...", result: .working)
        defer { isSyncing = false }

        do {
            let configuration = try await ensureRemoteStructure(accessToken: accessToken)
            let catalogText = try await driveClient.downloadText(fileID: configuration.masterFile.id, accessToken: accessToken)
            let remoteCatalog = try codec.decode(catalogText).map(\.strippingProgress)
            let localIDs = Set(catalogEntries.map(\.id))
            let remoteByID = Dictionary(uniqueKeysWithValues: remoteCatalog.map { ($0.id, $0) })
            let newEntries = remoteCatalog.filter { !localIDs.contains($0.id) }
            var correctedCount = 0

            catalogEntries = catalogEntries.map { localEntry in
                guard let remoteEntry = remoteByID[localEntry.id], remoteEntry != localEntry else {
                    return localEntry
                }
                correctedCount += 1
                return remoteEntry
            }

            guard !newEntries.isEmpty || correctedCount > 0 else {
                lastVocabularyUpdateCheckDate = Date()
                vocabularyUpdateSummary = "Keine neuen oder korrigierten Vokabeln"
                setSyncMessage("Keine neuen Vokabeln gefunden", result: .success)
                return
            }

            catalogEntries.append(contentsOf: newEntries)
            catalogEntries.sort { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
            rebuildEntries()
            try persistCatalog()
            try persistProgressCache()

            let messageParts = [
                updateMessagePart(count: newEntries.count, singular: "neue Vokabel", plural: "neue Vokabeln"),
                updateMessagePart(count: correctedCount, singular: "korrigierte Vokabel", plural: "korrigierte Vokabeln")
            ].compactMap { $0 }
            lastVocabularyUpdateCheckDate = Date()
            vocabularyUpdateSummary = messageParts.joined(separator: ", ")
            setSyncMessage("\(messageParts.joined(separator: ", ")) uebernommen", result: .success)
        } catch {
            setSyncMessage("Vokabel-Update fehlgeschlagen: \(error.localizedDescription)", result: .failure)
        }
    }

    public func update(
        entryID: String,
        grade: AnswerGrade,
        learner: Learner,
        correctLevelDelta: Double = 1,
        date: Date = Date()
    ) {
        let event = ProgressEvent(
            entryID: entryID,
            learner: learner,
            timestamp: date,
            grade: grade,
            correctLevelDelta: correctLevelDelta
        )

        var learnerEvents = loadLocalEvents(for: learner)
        learnerEvents.append(event)
        try? persistLocalEvents(learnerEvents, for: learner)

        knownProgressEvents = deduplicateEvents(knownProgressEvents + [event])
        rebuildEntries()
        try? persistProgressCache()
    }

    public func setSyncMessage(_ message: String) {
        setSyncMessage(message, result: .failure)
    }

    public func setSyncMessage(_ message: String, result: SyncResult) {
        lastSyncMessage = message
        lastSyncResult = result
        lastSyncDate = Date()
    }

    private func synchronizeWithDrive(accessToken: String) async {
        isSyncing = true
        setSyncMessage("Synchronisiere mit Google Drive ...", result: .working)
        defer { isSyncing = false }

        do {
            let configuration = try await ensureRemoteStructure(accessToken: accessToken)

            let catalogText = try await driveClient.downloadText(fileID: configuration.masterFile.id, accessToken: accessToken)
            catalogEntries = try codec.decode(catalogText).map(\.strippingProgress)
            lastVocabularyUpdateCheckDate = Date()
            vocabularyUpdateSummary = "\(catalogEntries.count) Vokabeln im lokalen Katalog"

            let remoteProgressFiles = try await loadRemoteProgressFiles(
                folderID: configuration.progressFolder.id,
                accessToken: accessToken
            )

            var mergedByFileName = remoteProgressFiles.eventsByFileName

            for learner in Learner.allCases {
                let fileName = progressFileName(for: learner)
                let localEvents = loadLocalEvents(for: learner)
                let remoteEvents = remoteProgressFiles.eventsByFileName[fileName] ?? []
                let mergedEvents = deduplicateEvents(remoteEvents + localEvents)

                if let remoteFile = remoteProgressFiles.filesByName[fileName] {
                    try await driveClient.uploadText(
                        encodeEvents(mergedEvents),
                        fileID: remoteFile.id,
                        mimeType: "application/json; charset=utf-8",
                        accessToken: accessToken
                    )
                } else {
                    _ = try await driveClient.createTextFile(
                        name: fileName,
                        text: encodeEvents(mergedEvents),
                        mimeType: "application/json",
                        parentID: configuration.progressFolder.id,
                        accessToken: accessToken
                    )
                }

                mergedByFileName[fileName] = mergedEvents
                try persistLocalEvents(mergedEvents, for: learner)
            }

            knownProgressEvents = deduplicateEvents(mergedByFileName.values.flatMap { $0 })
            rebuildEntries()
            try persistCatalog()
            try persistProgressCache()

            let message = configuration.migratedLegacyMaster
                ? "Drive-Struktur migriert und Daten synchronisiert"
                : "Mit Google Drive synchronisiert"
            setSyncMessage(message, result: .success)
        } catch {
            setSyncMessage("Drive-Sync fehlgeschlagen: \(error.localizedDescription)", result: .failure)
        }
    }

    private func rebuildEntries() {
        var derivedEntries = catalogEntries.map(\.strippingProgress)
        let indexByID = Dictionary(uniqueKeysWithValues: derivedEntries.enumerated().map { ($0.element.id, $0.offset) })
        let events = knownProgressEvents.sorted {
            if $0.timestamp == $1.timestamp {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.timestamp < $1.timestamp
        }

        for event in events {
            guard let index = indexByID[event.entryID] else { continue }
            derivedEntries[index].apply(
                event.grade,
                learner: event.learner,
                correctLevelDelta: event.correctLevelDelta,
                date: event.timestamp
            )
        }

        entries = derivedEntries
    }

    private func ensureRemoteStructure(accessToken: String) async throws -> RemoteDriveConfiguration {
        let progressFolder = try await driveClient.createFolderIfNeeded(named: progressFolderName, accessToken: accessToken)

        if let folderMaster = try await findLatestFile(named: remoteMasterName, parentID: progressFolder.id, accessToken: accessToken) {
            let contents = try await driveClient.downloadText(fileID: folderMaster.id, accessToken: accessToken)
            if looksLikeLegacyMaster(contents) {
                let archivedName = try await archiveLegacyMaster(folderMaster, accessToken: accessToken)
                let newMaster = try await createCatalogMaster(
                    fromLegacyCSV: contents,
                    parentID: progressFolder.id,
                    accessToken: accessToken
                )
                return RemoteDriveConfiguration(masterFile: newMaster, progressFolder: progressFolder, migratedLegacyMaster: archivedName != nil)
            }
            return RemoteDriveConfiguration(masterFile: folderMaster, progressFolder: progressFolder, migratedLegacyMaster: false)
        }

        if let existingMaster = try await findLatestFile(named: remoteMasterName, accessToken: accessToken) {
            let contents = try await driveClient.downloadText(fileID: existingMaster.id, accessToken: accessToken)
            if looksLikeLegacyMaster(contents) {
                let archivedName = try await archiveLegacyMaster(existingMaster, accessToken: accessToken)
                let newMaster = try await createCatalogMaster(
                    fromLegacyCSV: contents,
                    parentID: progressFolder.id,
                    accessToken: accessToken
                )
                return RemoteDriveConfiguration(masterFile: newMaster, progressFolder: progressFolder, migratedLegacyMaster: archivedName != nil)
            }
            let folderMaster = try await createCatalogMaster(
                fromCatalogCSV: contents,
                parentID: progressFolder.id,
                accessToken: accessToken
            )
            return RemoteDriveConfiguration(masterFile: folderMaster, progressFolder: progressFolder, migratedLegacyMaster: true)
        }

        if let archived = try await findLatestArchivedMaster(accessToken: accessToken) {
            let contents = try await driveClient.downloadText(fileID: archived.id, accessToken: accessToken)
            let newMaster = try await createCatalogMaster(
                fromLegacyCSV: contents,
                parentID: progressFolder.id,
                accessToken: accessToken
            )
            return RemoteDriveConfiguration(masterFile: newMaster, progressFolder: progressFolder, migratedLegacyMaster: true)
        }

        if let legacy = try? await driveClient.getFile(fileID: legacyDriveFileID, accessToken: accessToken) {
            let contents = try await driveClient.downloadText(fileID: legacy.id, accessToken: accessToken)
            if legacy.name == remoteMasterName || looksLikeLegacyMaster(contents) {
                _ = try await archiveLegacyMaster(legacy, accessToken: accessToken)
                let newMaster = try await createCatalogMaster(
                    fromLegacyCSV: contents,
                    parentID: progressFolder.id,
                    accessToken: accessToken
                )
                return RemoteDriveConfiguration(masterFile: newMaster, progressFolder: progressFolder, migratedLegacyMaster: true)
            }
        }

        if !catalogEntries.isEmpty {
            let newMaster = try await driveClient.createTextFile(
                name: remoteMasterName,
                text: codec.encodeCatalog(catalogEntries),
                mimeType: "text/csv",
                parentID: progressFolder.id,
                accessToken: accessToken
            )
            return RemoteDriveConfiguration(masterFile: newMaster, progressFolder: progressFolder, migratedLegacyMaster: true)
        }

        throw VocabularyStoreError.remoteMasterNotFound
    }

    private func archiveLegacyMaster(_ file: GoogleDriveFile, accessToken: String) async throws -> String? {
        let targetName: String
        if try await findLatestFile(named: archivedMasterName, accessToken: accessToken) == nil {
            targetName = archivedMasterName
        } else {
            let stamp = Self.archiveTimestampFormatter.string(from: Date())
            targetName = "MASTER_vokabelheft_norwegisch_alt_\(stamp).csv"
        }
        try await driveClient.renameFile(fileID: file.id, newName: targetName, accessToken: accessToken)
        return targetName
    }

    private func createCatalogMaster(fromLegacyCSV legacyCSV: String, parentID: String?, accessToken: String) async throws -> GoogleDriveFile {
        let decoded = try codec.decode(legacyCSV)
        return try await createCatalogMaster(
            fromCatalogCSV: codec.encodeCatalog(decoded.map(\.strippingProgress)),
            parentID: parentID,
            accessToken: accessToken
        )
    }

    private func createCatalogMaster(fromCatalogCSV catalogCSV: String, parentID: String?, accessToken: String) async throws -> GoogleDriveFile {
        let file = try await driveClient.createTextFile(
            name: remoteMasterName,
            text: catalogCSV,
            mimeType: "text/csv",
            parentID: parentID,
            accessToken: accessToken
        )
        guard file.name == remoteMasterName else {
            throw VocabularyStoreError.remoteMasterCreationFailed
        }
        return file
    }

    private func loadRemoteProgressFiles(folderID: String, accessToken: String) async throws -> RemoteProgressFiles {
        let query = "'\(folderID)' in parents and trashed = false"
        let files = try await driveClient.listFiles(query: query, accessToken: accessToken)
            .filter { $0.name.hasPrefix("progress_") && $0.name.hasSuffix(".json") }

        var filesByName: [String: GoogleDriveFile] = [:]
        var eventsByFileName: [String: [ProgressEvent]] = [:]

        for file in files {
            filesByName[file.name] = file
            let text = try await driveClient.downloadText(fileID: file.id, accessToken: accessToken)
            eventsByFileName[file.name] = decodeEvents(text)
        }

        return RemoteProgressFiles(filesByName: filesByName, eventsByFileName: eventsByFileName)
    }

    private func findLatestFile(named name: String, accessToken: String) async throws -> GoogleDriveFile? {
        let query = "trashed = false and name = '\(escapeDriveQuery(name))'"
        return try await driveClient.listFiles(query: query, accessToken: accessToken)
            .sorted { ($0.modifiedTime ?? .distantPast) > ($1.modifiedTime ?? .distantPast) }
            .first
    }

    private func findLatestFile(named name: String, parentID: String, accessToken: String) async throws -> GoogleDriveFile? {
        let query = "trashed = false and name = '\(escapeDriveQuery(name))' and '\(escapeDriveQuery(parentID))' in parents"
        return try await driveClient.listFiles(query: query, accessToken: accessToken)
            .sorted { ($0.modifiedTime ?? .distantPast) > ($1.modifiedTime ?? .distantPast) }
            .first
    }

    private func findLatestArchivedMaster(accessToken: String) async throws -> GoogleDriveFile? {
        let exact = try await findLatestFile(named: archivedMasterName, accessToken: accessToken)
        if let exact { return exact }
        let query = "trashed = false and name contains 'MASTER_vokabelheft_norwegisch_alt'"
        return try await driveClient.listFiles(query: query, accessToken: accessToken)
            .sorted { ($0.modifiedTime ?? .distantPast) > ($1.modifiedTime ?? .distantPast) }
            .first
    }

    private func looksLikeLegacyMaster(_ csv: String) -> Bool {
        csv.contains("Level_Papa") || csv.contains("Richtig_Papa") || csv.contains("Zuletzt_Papa")
    }

    private func escapeDriveQuery(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "\\'")
    }

    private func updateMessagePart(count: Int, singular: String, plural: String) -> String? {
        guard count > 0 else { return nil }
        return "\(count) \(count == 1 ? singular : plural)"
    }

    private func encodeEvents(_ events: [ProgressEvent]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = (try? encoder.encode(events.sorted { $0.timestamp < $1.timestamp })) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private func decodeEvents(_ text: String) -> [ProgressEvent] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = text.data(using: .utf8),
              let events = try? decoder.decode([ProgressEvent].self, from: data) else {
            return []
        }
        return deduplicateEvents(events)
    }

    private func deduplicateEvents<S: Sequence>(_ events: S) -> [ProgressEvent] where S.Element == ProgressEvent {
        var byID: [UUID: ProgressEvent] = [:]
        for event in events {
            byID[event.id] = event
        }
        return byID.values.sorted {
            if $0.timestamp == $1.timestamp {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.timestamp < $1.timestamp
        }
    }

    private func progressFileName(for learner: Learner) -> String {
        "progress_\(learner.rawValue.lowercased())_\(deviceID).json"
    }

    private func loadCachedEvents() -> [ProgressEvent] {
        let cached = ((try? String(contentsOf: progressCacheURL(), encoding: .utf8)).map(decodeEvents) ?? [])
        let local = Learner.allCases.flatMap { loadLocalEvents(for: $0) }
        return deduplicateEvents(cached + local)
    }

    private func loadLocalEvents(for learner: Learner) -> [ProgressEvent] {
        ((try? String(contentsOf: localEventsURL(for: learner), encoding: .utf8)).map(decodeEvents) ?? [])
    }

    private func persistCatalog() throws {
        try FileManager.default.createDirectory(at: documentsURL(), withIntermediateDirectories: true)
        try codec.encodeCatalog(catalogEntries).write(to: catalogLocalURL(), atomically: true, encoding: .utf8)
    }

    private func persistProgressCache() throws {
        try FileManager.default.createDirectory(at: documentsURL(), withIntermediateDirectories: true)
        try encodeEvents(knownProgressEvents).write(to: progressCacheURL(), atomically: true, encoding: .utf8)
    }

    private func persistLocalEvents(_ events: [ProgressEvent], for learner: Learner) throws {
        try FileManager.default.createDirectory(at: documentsURL(), withIntermediateDirectories: true)
        try encodeEvents(events).write(to: localEventsURL(for: learner), atomically: true, encoding: .utf8)
    }

    private func documentsURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func catalogLocalURL() -> URL {
        documentsURL().appendingPathComponent(localFileName)
    }

    private func progressCacheURL() -> URL {
        documentsURL().appendingPathComponent(".progress_cache.json")
    }

    private func localEventsURL(for learner: Learner) -> URL {
        documentsURL().appendingPathComponent(progressFileName(for: learner))
    }

    private static func resolveDeviceID() -> String {
        let defaults = UserDefaults.standard
        let key = "vokabelapp.deviceID"
        if let existing = defaults.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let generated = UUID().uuidString.lowercased()
        defaults.set(generated, forKey: key)
        return generated
    }

    private static var archiveTimestampFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
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

private struct RemoteDriveConfiguration {
    let masterFile: GoogleDriveFile
    let progressFolder: GoogleDriveFile
    let migratedLegacyMaster: Bool
}

private struct RemoteProgressFiles {
    var filesByName: [String: GoogleDriveFile]
    var eventsByFileName: [String: [ProgressEvent]]
}

public enum SyncResult: Equatable {
    case idle
    case working
    case success
    case failure
}

public enum VocabularyStoreError: LocalizedError {
    case remoteMasterNotFound
    case remoteMasterCreationFailed

    public var errorDescription: String? {
        switch self {
        case .remoteMasterNotFound:
            "Keine passende Masterdatei auf Google Drive gefunden"
        case .remoteMasterCreationFailed:
            "Neue Masterdatei konnte nicht sichtbar auf Google Drive erstellt werden"
        }
    }
}

import Foundation
import RepoPeekCore

struct MenuSnapshotStore {
    private let fileManager: FileManager
    private let fileURL: URL?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default, baseURL: URL? = nil) {
        self.fileManager = fileManager
        self.fileURL = (baseURL ?? Self.defaultBaseURL(fileManager: fileManager))?
            .appending(path: "menu-snapshot.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func load() -> MenuSnapshot? {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL)
        else { return nil }

        do {
            let snapshot = try self.decoder.decode(MenuSnapshot.self, from: data)
            return snapshot.repositories.isEmpty ? nil : snapshot
        } catch {
            try? self.fileManager.removeItem(at: fileURL)
            return nil
        }
    }

    func save(_ snapshot: MenuSnapshot) {
        guard snapshot.repositories.isEmpty == false,
              let fileURL
        else { return }

        do {
            try self.fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try self.encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            return
        }
    }

    func clear() {
        guard let fileURL else { return }

        try? self.fileManager.removeItem(at: fileURL)
    }

    private static func defaultBaseURL(fileManager: FileManager) -> URL? {
        guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        return support
            .appending(path: RepoPeekProductConstants.applicationSupportDirectoryName)
            .appending(path: "MenuSnapshot")
    }
}

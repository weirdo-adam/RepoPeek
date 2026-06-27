import Foundation

/// Simple ETag cache keyed by URL string, backed by an optional persistent store.
actor ETagCache {
    private static let defaultMaxEntries = 512

    private let maxEntries: Int
    private let persistentStore: HTTPResponseDiskCache?
    private var store: [String: PersistentHTTPResponse] = [:]
    private var entryOrder: [String] = []
    private var rateLimitedUntil: Date?

    init(maxEntries: Int = ETagCache.defaultMaxEntries, persistentStore: HTTPResponseDiskCache? = nil) {
        self.maxEntries = max(0, maxEntries)
        self.persistentStore = persistentStore
    }

    static func persistent(maxEntries: Int = ETagCache.defaultMaxEntries, accountID: String? = nil) -> ETagCache {
        ETagCache(maxEntries: maxEntries, persistentStore: HTTPResponseDiskCache.standard(accountID: accountID))
    }

    func cached(for url: URL) -> (etag: String, data: Data)? {
        guard let cached = self.cachedResponse(for: url) else { return nil }

        return (cached.etag, cached.data)
    }

    func cachedResponse(for url: URL) -> PersistentHTTPResponse? {
        let key = url.absoluteString
        if let cached = self.store[key] {
            self.touch(key)
            return cached
        }

        guard let cached = self.persistentStore?.cached(url: url) else { return nil }

        self.store[key] = cached
        self.touch(key)
        self.evictIfNeeded()
        return cached
    }

    func save(url: URL, etag: String?, data: Data, response: HTTPURLResponse? = nil) {
        guard let etag else { return }

        let key = url.absoluteString
        if self.maxEntries > 0 {
            self.store[key] = PersistentHTTPResponse(
                etag: etag,
                data: data,
                fetchedAt: Date(),
                statusCode: response?.statusCode,
                headers: response.map(Self.headers) ?? [:]
            )
            self.touch(key)
            self.evictIfNeeded()
        }
        self.persistentStore?.save(url: url, etag: etag, data: data, response: response)
    }

    func recordResponse(url: URL, data: Data, response: HTTPURLResponse) {
        let etag = response.value(forHTTPHeaderField: "ETag")
        if etag?.isEmpty == false {
            self.save(url: url, etag: etag, data: data, response: response)
            return
        }

        guard Self.hasRateLimitHeaders(response) else { return }

        self.persistentStore?.save(url: url, etag: nil, data: data, response: response)
    }

    func setRateLimitReset(resource: String = "core", date: Date, message: String? = nil) {
        self.rateLimitedUntil = date
        self.persistentStore?.setRateLimitReset(resource: resource, date: date, message: message)
    }

    func rateLimitUntil(now: Date = Date()) -> Date? {
        if let until = self.rateLimitedUntil {
            guard until <= now else { return until }

            self.rateLimitedUntil = nil
        }
        return self.persistentStore?.rateLimitUntil(now: now)
    }

    func isRateLimited(now: Date = Date()) -> Bool {
        guard let until = self.rateLimitUntil(now: now) else { return false }

        return until > now
    }

    func clear() {
        self.store.removeAll()
        self.entryOrder.removeAll()
        self.rateLimitedUntil = nil
        self.persistentStore?.clear()
    }

    func count() -> Int {
        self.persistentStore?.count() ?? self.store.count
    }

    private func touch(_ key: String) {
        self.entryOrder.removeAll { $0 == key }
        self.entryOrder.append(key)
    }

    private func evictIfNeeded() {
        while self.store.count > self.maxEntries, let oldest = self.entryOrder.first {
            self.entryOrder.removeFirst()
            self.store[oldest] = nil
        }
    }

    private static func headers(from response: HTTPURLResponse) -> [String: String] {
        response.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            guard let key = pair.key as? String else { return }

            result[key] = "\(pair.value)"
        }
    }

    private static func hasRateLimitHeaders(_ response: HTTPURLResponse) -> Bool {
        response.value(forHTTPHeaderField: "X-RateLimit-Resource") != nil
            || response.value(forHTTPHeaderField: "X-RateLimit-Limit") != nil
            || response.value(forHTTPHeaderField: "X-RateLimit-Remaining") != nil
            || response.value(forHTTPHeaderField: "X-RateLimit-Reset") != nil
    }
}

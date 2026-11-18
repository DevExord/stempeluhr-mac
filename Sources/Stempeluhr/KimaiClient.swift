// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

enum KimaiError: Error, LocalizedError, Equatable {
    case network(String)
    case unauthorized
    case notFound
    case validation([String])
    case redirect
    case server(Int)
    case client(Int)
    case unexpectedResponse(String)

    /// Transient errors are safe to retry for idempotent GETs.
    var isTransient: Bool {
        switch self {
        case .network, .server: return true
        default: return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .network(let m): return "Can't reach the server (\(m))"
        case .unauthorized: return "Sign-in required — the token was rejected"
        case .notFound: return "Not found"
        case .validation(let msgs): return msgs.isEmpty ? "The server rejected the request" : msgs.joined(separator: "\n")
        case .redirect: return "The server redirected the request"
        case .server(let c): return "Server error (HTTP \(c))"
        case .client(let c): return "Request failed (HTTP \(c))"
        case .unexpectedResponse(let m): return "Unexpected answer: \(m)"
        }
    }
}

/// A parsed answer plus what we learned about the server clock.
struct Reply<T> {
    var value: T
    /// Value of the HTTP `Date` header, if present.
    var serverDate: Date?
    /// Local wall clock when the answer arrived.
    var received: Date
}

/// A thin, dependency-free client for the Kimai 2.x REST API. Mirrors the
/// behaviour of the original `core/src/kimai/client.rs`: Bearer auth, tolerant
/// parsing, idempotent GET retries, and writes that are never retried.
actor KimaiClient {
    let baseURL: String
    private let token: String
    private let session: URLSession
    private var cachedTimeZone: TimeZone?

    private let retryDelays: [UInt64] = [400_000_000, 1_500_000_000] // ns

    init(baseURL: String, token: String) {
        self.baseURL = KimaiClient.normalize(baseURL)
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 30
        cfg.waitsForConnectivity = false
        self.session = URLSession(configuration: cfg)
    }

    /// Strips a trailing slash and a trailing `/api`, like `normalize_base_url`.
    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        if s.hasSuffix("/api") { s.removeLast(4) }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    // MARK: - Endpoints

    func version() async throws -> Reply<KimaiVersion> {
        try await getJSON("/api/version")
    }

    func me() async throws -> Reply<KimaiUser> {
        let r: Reply<KimaiUser> = try await getJSON("/api/users/me")
        if let name = r.value.timezone, let tz = TimeZone(identifier: name) {
            cachedTimeZone = tz
        }
        return r
    }

    /// Reachable, authenticated, and a real Kimai answer.
    func testConnection() async throws -> (KimaiVersion, KimaiUser) {
        let v = try await version().value
        let u = try await me().value
        return (v, u)
    }

    /// The Kimai user's time zone (cached). Kimai reads and writes naive
    /// date-times in this zone, so it must come from the server.
    func userTimeZone() async throws -> TimeZone {
        if let tz = cachedTimeZone { return tz }
        let u = try await me().value
        if let name = u.timezone, let tz = TimeZone(identifier: name) { return tz }
        return TimeZone.current
    }

    func active() async throws -> Reply<[Timesheet]> {
        try await getJSON("/api/timesheets/active")
    }

    func projects() async throws -> [Project] {
        let all: [Project] = try await getPaged("/api/projects", query: [
            "visible": "1", "order": "ASC", "orderBy": "name",
        ])
        return all.filter { $0.visible }
    }

    func activities(project: Int) async throws -> [Activity] {
        let all: [Activity] = try await getPaged("/api/activities", query: [
            "project": String(project), "visible": "1", "order": "ASC", "orderBy": "name",
        ])
        return all.filter { $0.visible }
    }

    /// Finished timesheets since `since`, newest first.
    func history(since: Date) async throws -> [Timesheet] {
        let tz = try await userTimeZone()
        let list: [Timesheet] = try await getPaged("/api/timesheets", query: [
            "begin": KimaiTime.formatBegin(since, timeZone: tz),
            "active": "0", "full": "1", "order": "DESC", "orderBy": "begin",
        ])
        return list.filter { $0.end != nil }
    }

    /// `POST /api/timesheets`. Never retried. `now` should be server-adjusted.
    func start(_ req: StartRequest, now: Date) async throws -> Reply<Timesheet> {
        let tz = try await userTimeZone()
        var body: [String: Any] = [
            "project": req.project,
            "activity": req.activity,
            "begin": KimaiTime.formatBegin(now, timeZone: tz),
        ]
        if let d = req.description?.trimmingCharacters(in: .whitespaces), !d.isEmpty {
            body["description"] = d
        }
        let raw = try await send(.post, "/api/timesheets", body: body)
        return try decode(raw)
    }

    /// `PATCH /api/timesheets/{id}/stop`. Never retried.
    func stop(id: Int) async throws -> Reply<Timesheet> {
        let raw = try await send(.patch, "/api/timesheets/\(id)/stop")
        return try decode(raw)
    }

    /// `DELETE /api/timesheets/{id}`. Never retried.
    func delete(id: Int) async throws {
        _ = try await send(.delete, "/api/timesheets/\(id)")
    }

    // MARK: - Plumbing

    private enum HTTPMethod: String { case get = "GET", post = "POST", patch = "PATCH", delete = "DELETE" }

    private struct Raw {
        var body: Data
        var serverDate: Date?
        var received: Date
        var totalPages: Int?
    }

    private func getJSON<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> Reply<T> {
        var attempt = 0
        while true {
            do {
                let raw = try await send(.get, path, query: query)
                return try decode(raw)
            } catch let e as KimaiError where e.isTransient && attempt < retryDelays.count {
                try? await Task.sleep(nanoseconds: retryDelays[attempt])
                attempt += 1
            }
        }
    }

    private func getPaged<T: Decodable>(_ path: String, query: [String: String]) async throws -> [T] {
        let size = 100
        var out: [T] = []
        for page in 1...50 {
            var q = query
            q["page"] = String(page)
            q["size"] = String(size)
            var attempt = 0
            let raw: Raw = try await {
                while true {
                    do { return try await send(.get, path, query: q) }
                    catch let e as KimaiError where e.isTransient && attempt < retryDelays.count {
                        try? await Task.sleep(nanoseconds: retryDelays[attempt]); attempt += 1
                    }
                }
            }()
            let chunk: [T] = try decode(raw).value
            out.append(contentsOf: chunk)
            let done = raw.totalPages.map { page >= $0 } ?? (chunk.count < size)
            if done || chunk.isEmpty { break }
        }
        return out
    }

    private func send(_ method: HTTPMethod, _ path: String, query: [String: String] = [:], body: [String: Any]? = nil) async throws -> Raw {
        guard var comps = URLComponents(string: baseURL + path) else {
            throw KimaiError.unexpectedResponse("bad URL")
        }
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = comps.url else { throw KimaiError.unexpectedResponse("bad URL") }

        var req = URLRequest(url: url)
        req.httpMethod = method.rawValue
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("stempeluhr-mac/1.0", forHTTPHeaderField: "User-Agent")
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else if method != .get {
            req.setValue("0", forHTTPHeaderField: "Content-Length")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw KimaiError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw KimaiError.unexpectedResponse("no HTTP response")
        }
        let received = Date()
        let serverDate = (http.value(forHTTPHeaderField: "Date")).flatMap(KimaiTime.httpDate(_:))
        let totalPages = (http.value(forHTTPHeaderField: "x-total-pages")).flatMap { Int($0) }

        if (200...299).contains(http.statusCode) {
            return Raw(body: data, serverDate: serverDate, received: received, totalPages: totalPages)
        }
        throw KimaiClient.errorForStatus(http.statusCode, data)
    }

    private func decode<T: Decodable>(_ raw: Raw) throws -> Reply<T> {
        if T.self == Empty.self {
            return Reply(value: Empty() as! T, serverDate: raw.serverDate, received: raw.received)
        }
        do {
            let value = try JSONDecoder().decode(T.self, from: raw.body)
            return Reply(value: value, serverDate: raw.serverDate, received: raw.received)
        } catch {
            throw KimaiError.unexpectedResponse("JSON: \(error)")
        }
    }

    private static func errorForStatus(_ code: Int, _ body: Data) -> KimaiError {
        switch code {
        case 401, 403: return .unauthorized
        case 404: return .notFound
        case 400, 422: return .validation(validationMessages(body))
        case 300...399: return .redirect
        case 500...599: return .server(code)
        default: return .client(code)
        }
    }

    /// Extracts human-readable messages from Symfony-style validation answers.
    private static func validationMessages(_ body: Data) -> [String] {
        guard let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return [] }
        var out: [String] = []
        func collect(_ v: Any?) {
            guard let dict = v as? [String: Any] else { return }
            if let arr = dict["errors"] as? [Any] {
                out.append(contentsOf: arr.compactMap { $0 as? String })
            }
            if let children = dict["children"] as? [String: Any] {
                for c in children.values { collect(c) }
            }
        }
        collect(obj["errors"])
        if out.isEmpty, let m = obj["message"] as? String { out.append(m) }
        return out
    }
}

/// Placeholder for endpoints with no body (DELETE).
struct Empty: Decodable {}

extension KimaiTime {
    /// Parses an HTTP-date header (RFC 9110 IMF-fixdate). Tolerates a
    /// multi-value header that URLSession joined with ", " (some servers emit
    /// two `Date` lines) by parsing the first value.
    static func httpDate(_ raw: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        if let d = f.date(from: raw) { return d }
        // Fall back to the substring through the first "GMT".
        if let g = raw.range(of: "GMT") {
            return f.date(from: String(raw[..<g.upperBound]))
        }
        return nil
    }

    /// Server clock offset derived from an HTTP `Date` header (one-second
    /// resolution, so sub-two-second differences are treated as "in sync").
    static func clockOffset(serverDate: Date, received: Date) -> TimeInterval {
        let est = serverDate.addingTimeInterval(0.5)
        let off = est.timeIntervalSince(received)
        return abs(off) < 2 ? 0 : (off < 0 ? -floor(-off) : floor(off))
    }
}

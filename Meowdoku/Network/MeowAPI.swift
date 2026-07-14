import Foundation

/// Thin PostgREST client for the `meow_matches` table. No SDK dependency — plain
/// URLSession — so the app stays lightweight and build-robust. Realtime is done
/// by lightweight polling (see `RaceStore`), which is plenty for a 2-player race.
enum MeowAPI {

    enum APIError: Error, LocalizedError {
        case badResponse(Int, String)
        case decoding(String)
        case codeInUse
        case matchNotFound
        case matchFull

        var errorDescription: String? {
            switch self {
            case .badResponse(let code, let body): return "Server error \(code): \(body)"
            case .decoding(let m): return "Couldn't read server response: \(m)"
            case .codeInUse: return "That game code is already taken."
            case .matchNotFound: return "No game found with that code."
            case .matchFull: return "That game already has two players."
            }
        }
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private static func request(
        path: String,
        method: String,
        query: [URLQueryItem] = [],
        body: [String: Any]? = nil,
        prefer: String? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        var comps = URLComponents(url: MeowConfig.restURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue(MeowConfig.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(MeowConfig.anonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { req.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.badResponse(-1, "no response")
        }
        return (data, http)
    }

    private static func decodeRows(_ data: Data) throws -> [Match] {
        do { return try decoder.decode([Match].self, from: data) }
        catch { throw APIError.decoding(String(describing: error)) }
    }

    // MARK: - Operations

    /// Host creates a match. Retries a couple of times if the random code collides.
    static func createMatch(hostName: String, size: Int, seed: Int64) async throws -> Match {
        for _ in 0..<4 {
            let code = randomCode()
            let (data, http) = try await request(
                path: "meow_matches",
                method: "POST",
                body: [
                    "code": code,
                    "size": size,
                    "seed": seed,
                    "status": "waiting",
                    "host_name": hostName,
                ],
                prefer: "return=representation"
            )
            if http.statusCode == 201 {
                if let match = try decodeRows(data).first { return match }
            }
            if http.statusCode == 409 { continue } // unique code collision, retry
            throw APIError.badResponse(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        throw APIError.codeInUse
    }

    /// Guest joins by code. Atomically claims the empty guest slot and flips the
    /// match to `playing`. Returns the started match, or throws if not joinable.
    static func joinMatch(code: String, guestName: String) async throws -> Match {
        let (data, http) = try await request(
            path: "meow_matches",
            method: "PATCH",
            query: [
                .init(name: "code", value: "eq.\(code)"),
                .init(name: "guest_name", value: "is.null"),
                .init(name: "status", value: "eq.waiting"),
            ],
            body: [
                "guest_name": guestName,
                "status": "playing",
                "started_at": iso8601Now(),
            ],
            prefer: "return=representation"
        )
        guard http.statusCode == 200 else {
            throw APIError.badResponse(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        if let match = try decodeRows(data).first { return match }
        // No row updated → either the code doesn't exist or it's already full.
        if let existing = try await fetchMatch(code: code) {
            throw existing.guestName == nil ? APIError.matchNotFound : APIError.matchFull
        }
        throw APIError.matchNotFound
    }

    static func fetchMatch(code: String) async throws -> Match? {
        let (data, http) = try await request(
            path: "meow_matches",
            method: "GET",
            query: [
                .init(name: "code", value: "eq.\(code)"),
                .init(name: "limit", value: "1"),
            ]
        )
        guard http.statusCode == 200 else {
            throw APIError.badResponse(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return try decodeRows(data).first
    }

    static func fetchMatch(id: String) async throws -> Match? {
        let (data, http) = try await request(
            path: "meow_matches",
            method: "GET",
            query: [.init(name: "id", value: "eq.\(id)"), .init(name: "limit", value: "1")]
        )
        guard http.statusCode == 200 else {
            throw APIError.badResponse(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return try decodeRows(data).first
    }

    /// Push my current progress (cats correctly placed).
    static func updateProgress(id: String, role: PlayerRole, progress: Int) async throws {
        let field = role == .host ? "host_progress" : "guest_progress"
        _ = try await request(
            path: "meow_matches",
            method: "PATCH",
            query: [.init(name: "id", value: "eq.\(id)")],
            body: [field: progress]
        )
    }

    /// Atomically claim victory. Only the *first* writer succeeds because the
    /// filter requires `winner` to still be null. Returns true iff I won the race
    /// to finish; false means my opponent already ended it.
    @discardableResult
    static func claimResult(id: String, winnerName: String, reason: String, aliveField: PlayerRole?, alive: Bool) async throws -> Bool {
        var body: [String: Any] = [
            "winner": winnerName,
            "status": "finished",
            "end_reason": reason,
            "finished_at": iso8601Now(),
        ]
        if let aliveField {
            body[aliveField == .host ? "host_alive" : "guest_alive"] = alive
        }
        let (data, http) = try await request(
            path: "meow_matches",
            method: "PATCH",
            query: [
                .init(name: "id", value: "eq.\(id)"),
                .init(name: "winner", value: "is.null"),
            ],
            body: body,
            prefer: "return=representation"
        )
        guard http.statusCode == 200 else {
            throw APIError.badResponse(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return !(try decodeRows(data).isEmpty)
    }

    // MARK: - Helpers

    /// Unambiguous code alphabet (no O/0/I/1) for easy sharing out loud.
    private static func randomCode(length: Int = 4) -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var s = ""
        for _ in 0..<length { s.append(alphabet.randomElement()!) }
        return s
    }

    private static func iso8601Now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

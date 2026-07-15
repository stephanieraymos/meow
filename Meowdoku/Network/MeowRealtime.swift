import Foundation

/// Supabase Realtime (Phoenix) websocket client scoped to a single match row.
/// Pushes `meow_matches` changes to the app instantly, with automatic
/// reconnection. On every (re)connect it fires `onReconnect` so the caller can
/// re-fetch current state and never miss a change that happened while offline.
@MainActor
final class MeowRealtime {
    private var task: URLSessionWebSocketTask?
    private var heartbeatTask: Task<Void, Never>?
    private var matchId: String?
    private var onChange: ((Match) -> Void)?
    private var onReconnect: (() -> Void)?
    private var running = false
    private var ref = 0

    private let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase; return d
    }()

    func start(matchId: String, onChange: @escaping (Match) -> Void, onReconnect: @escaping () -> Void) {
        self.matchId = matchId
        self.onChange = onChange
        self.onReconnect = onReconnect
        running = true
        connect()
    }

    func stop() {
        running = false
        heartbeatTask?.cancel(); heartbeatTask = nil
        task?.cancel(with: .goingAway, reason: nil); task = nil
    }

    // MARK: - Connection

    private func connect() {
        guard running, let matchId else { return }
        let base = MeowConfig.supabaseURL.absoluteString
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
        guard let url = URL(string: "\(base)/realtime/v1/websocket?apikey=\(MeowConfig.anonKey)&vsn=1.0.0") else { return }

        let ws = URLSession.shared.webSocketTask(with: url)
        task = ws
        ws.resume()
        join(matchId: matchId)
        receive()
        startHeartbeat()
        // Sync any change we may have missed while disconnected.
        onReconnect?()
    }

    private func join(matchId: String) {
        let payload: [String: Any] = [
            "topic": "realtime:meow-\(matchId)",
            "event": "phx_join",
            "payload": ["config": ["postgres_changes": [[
                "event": "*", "schema": "public", "table": "meow_matches",
                "filter": "id=eq.\(matchId)",
            ]]]],
            "ref": "\(nextRef())",
        ]
        send(payload)
    }

    private func receive() {
        task?.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.running else { return }
                switch result {
                case .success(let message):
                    if case .string(let text) = message { self.handle(text) }
                    self.receive()
                case .failure:
                    self.reconnectSoon()
                }
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["event"] as? String == "postgres_changes",
              let payload = obj["payload"] as? [String: Any],
              let inner = payload["data"] as? [String: Any],
              let record = inner["record"] as? [String: Any],
              let recordData = try? JSONSerialization.data(withJSONObject: record),
              let match = try? decoder.decode(Match.self, from: recordData)
        else { return }
        onChange?(match)
    }

    private func reconnectSoon() {
        guard running else { return }
        heartbeatTask?.cancel()
        task = nil
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self?.connect()
        }
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 25_000_000_000)
                guard let self, self.running else { return }
                self.send(["topic": "phoenix", "event": "heartbeat", "payload": [:], "ref": "\(self.nextRef())"])
            }
        }
    }

    private func send(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(string)) { _ in }
    }

    private func nextRef() -> Int { ref += 1; return ref }
}

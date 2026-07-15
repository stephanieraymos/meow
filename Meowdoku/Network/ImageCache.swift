import SwiftUI
import CryptoKit

/// Memory + disk cache for remote images. Every URL is downloaded from Supabase
/// at most once, then served from disk forever — never a bare `AsyncImage`, so
/// Supabase egress can't run away from repeated views.
actor ImageCache {
    static let shared = ImageCache()

    private let memory = NSCache<NSString, UIImage>()
    private let dir: URL
    private var inflight: [String: Task<UIImage?, Never>] = [:]

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        dir = caches.appendingPathComponent("meow-avatars", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func key(_ url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func image(for url: URL) async -> UIImage? {
        let k = key(url)
        if let img = memory.object(forKey: k as NSString) { return img }

        // Disk hit — no network, no egress.
        let file = dir.appendingPathComponent(k)
        if let data = try? Data(contentsOf: file), let img = UIImage(data: data) {
            memory.setObject(img, forKey: k as NSString)
            return img
        }

        // Coalesce concurrent requests for the same URL.
        if let task = inflight[k] { return await task.value }
        let task = Task<UIImage?, Never> { [dir] in
            guard let (data, resp) = try? await URLSession.shared.data(from: url),
                  (resp as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
                  let img = UIImage(data: data) else { return nil }
            try? data.write(to: dir.appendingPathComponent(k), options: .atomic)
            return img
        }
        inflight[k] = task
        let img = await task.value
        inflight[k] = nil
        if let img { memory.setObject(img, forKey: k as NSString) }
        return img
    }
}

/// A circular avatar backed by the disk cache, with a colored initials fallback.
struct CachedAvatar: View {
    let urlString: String?
    let name: String
    var size: CGFloat = 40

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Circle().fill(fallbackColor)
                Text(initials).font(.system(size: size * 0.4, weight: .bold)).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 2))
        .task(id: urlString) {
            guard let urlString, let url = URL(string: urlString) else { image = nil; return }
            image = await ImageCache.shared.image(for: url)
        }
    }

    private var initials: String {
        let parts = name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? "?"
        let last = parts.count > 1 ? (parts.last?.first.map(String.init) ?? "") : ""
        return (first + last).uppercased()
    }

    private var fallbackColor: Color {
        let hash = abs(name.hashValue)
        return MeowPalettes.classic.colors[hash % MeowPalettes.classic.colors.count]
    }
}

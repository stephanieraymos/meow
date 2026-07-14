import Foundation

/// Supabase connection details, read from Info.plist (populated by build settings
/// in project.yml) so no credentials live in Swift source. The value here is the
/// project's *publishable* anon key — safe to ship in a client; all access is
/// gated by row-level security on the server.
enum MeowConfig {
    static let supabaseURL: URL = {
        let str = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String ?? ""
        return URL(string: str) ?? URL(string: "https://ihvljgwfslxorxsorzpi.supabase.co")!
    }()

    static let anonKey: String = {
        Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? ""
    }()

    static var restURL: URL { supabaseURL.appendingPathComponent("rest/v1") }
}

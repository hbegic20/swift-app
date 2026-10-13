import Foundation
import Supabase

/// Where the Supabase backend is and how to create a client for it.
public struct SupabaseSettings: Sendable {
    public let url: URL
    /// The public key that identifies the project. Safe to ship in an app;
    /// row-level security decides what each user may read.
    public let publishableKey: String

    public init(url: URL, publishableKey: String) {
        self.url = url
        self.publishableKey = publishableKey
    }

    /// The local project in `Supabase/` (`supabase start`). The simulator
    /// reaches it at 127.0.0.1; a real phone needs the Mac's network address.
    /// This key is the CLI's fixed local development key, not a secret.
    public static let local = SupabaseSettings(
        url: URL(string: "http://127.0.0.1:55321")!,
        publishableKey: "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH"
    )

    public func makeClient() -> SupabaseClient {
        SupabaseClient(supabaseURL: url, supabaseKey: publishableKey)
    }
}

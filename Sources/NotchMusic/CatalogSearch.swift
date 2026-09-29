import Foundation

struct CatalogSong: Identifiable, Equatable {
    var id: Int
    var title: String
    var artist: String
    var artworkURL: URL?
    var largeArtworkURL: URL?
    var pageURL: URL
    var duration: Double   // seconds

    var matchKey: String { SearchKey.make(title, artist) }

    /// `music://` opens the song in Music.app itself rather than in the browser.
    var musicAppURL: URL {
        var c = URLComponents(url: pageURL, resolvingAgainstBaseURL: false)
        c?.scheme = "music"
        return c?.url ?? pageURL
    }
}

enum SearchKey {
    /// Loose title+artist key so the same song from both sources dedupes.
    static func make(_ title: String, _ artist: String) -> String {
        (title + "|" + artist).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

/// Apple's public, unauthenticated catalog search (the iTunes Search API):
/// https://performance-partners.apple.com/search-api
enum CatalogSearch {
    private struct Response: Decodable {
        struct Item: Decodable {
            var trackId: Int
            var trackName: String
            var artistName: String
            var artworkUrl100: String?
            var trackViewUrl: String
            var trackTimeMillis: Double?
        }
        var results: [Item]
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        return URLSession(configuration: config)
    }()

    static func songs(matching query: String) async throws -> [CatalogSong] {
        var c = URLComponents(string: "https://itunes.apple.com/search")!
        c.queryItems = [
            .init(name: "term", value: query),
            .init(name: "media", value: "music"),
            .init(name: "entity", value: "song"),
            .init(name: "limit", value: "25"),
            .init(name: "country", value: Locale.current.region?.identifier ?? "US"),
        ]
        let (data, _) = try await session.data(from: c.url!)
        let items = try JSONDecoder().decode(Response.self, from: data).results
        return items.compactMap { item in
            guard let page = URL(string: item.trackViewUrl) else { return nil }
            // Artwork URLs encode their pixel size in the path.
            func art(_ px: Int) -> URL? {
                item.artworkUrl100.flatMap { URL(string: $0.replacingOccurrences(of: "100x100bb", with: "\(px)x\(px)bb")) }
            }
            return CatalogSong(id: item.trackId, title: item.trackName, artist: item.artistName,
                               artworkURL: art(120), largeArtworkURL: art(600), pageURL: page,
                               duration: (item.trackTimeMillis ?? 0) / 1000)
        }
    }
}

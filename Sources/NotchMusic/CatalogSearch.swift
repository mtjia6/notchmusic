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
            var collectionName: String?
        }
        var results: [Item]
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        return URLSession(configuration: config)
    }()

    private static func search(_ query: String, limit: Int) async throws -> [Response.Item] {
        var c = URLComponents(string: "https://itunes.apple.com/search")!
        c.queryItems = [
            .init(name: "term", value: query),
            .init(name: "media", value: "music"),
            .init(name: "entity", value: "song"),
            .init(name: "limit", value: String(limit)),
            .init(name: "country", value: Locale.current.region?.identifier ?? "US"),
        ]
        let (data, _) = try await session.data(from: c.url!)
        return try JSONDecoder().decode(Response.self, from: data).results
    }

    /// Cover art for a track Music won't give us artwork for (streamed
    /// "URL tracks" report zero artworks over AppleScript).
    static func artworkURL(title: String, artist: String, album: String) async -> URL? {
        guard let items = try? await search("\(title) \(artist)", limit: 10), !items.isEmpty else { return nil }
        let fold = { (s: String) in s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        let t = fold(title), a = fold(artist), al = fold(album)
        // Best: same title, artist and album; then title+artist; then title; then the top hit.
        let best = items.first { fold($0.trackName) == t && fold($0.artistName) == a && fold($0.collectionName ?? "") == al }
            ?? items.first { fold($0.trackName) == t && fold($0.artistName) == a }
            ?? items.first { fold($0.trackName) == t }
            ?? items[0]
        return best.artworkUrl100.flatMap { URL(string: $0.replacingOccurrences(of: "100x100bb", with: "600x600bb")) }
    }

    static func songs(matching query: String) async throws -> [CatalogSong] {
        let items = try await search(query, limit: 25)
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

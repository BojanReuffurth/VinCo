import Foundation
import MediaPlayer
import ComposableArchitecture

// MARK: – Domain types

nonisolated enum MusicProvider: String, CaseIterable, Equatable, Hashable, Codable, Sendable {
    case collectionDNA = "collection"
    case appleMusic    = "appleMusic"
    case spotify       = "spotify"

    var displayName: String {
        switch self {
        case .collectionDNA: return "Collection DNA"
        case .appleMusic:    return "Apple Music"
        case .spotify:       return "Spotify"
        }
    }

    var icon: String {
        switch self {
        case .collectionDNA: return "square.stack.3d.up"
        case .appleMusic:    return "music.note"
        case .spotify:       return "headphones"
        }
    }
}

/// Lightweight value type for a suggested vinyl record — not a SwiftData @Model.
nonisolated struct SuggestedRecord: Equatable, Identifiable, Sendable {
    /// Stable identity: "artist|album" (lowercased) for dedup + SwiftUI tracking.
    var id:          String { "\(artist.lowercased())|\(album.lowercased())" }
    let artist:      String
    let album:       String
    let year:        String
    let genre:       String
    let coverURL:    String
    let discogsId:   Int
    let provider:    MusicProvider
    let vinylFormat: String
}

struct SuggestionRequest: Sendable {
    let genres:       [String]         // top genres from user's collection
    let artists:      [String]         // top artists from user's collection
    let excluded:     Set<String>      // "artist|album" keys already owned/wishlisted
    let providers:    Set<MusicProvider>
    let seed:         Int              // rotated each refresh for variety
    let discogsToken: String
    let spotifyToken: String
}

// MARK: – Client

struct SuggestionsClient {
    var suggest: @Sendable (SuggestionRequest) async -> [SuggestedRecord]
}

extension SuggestionsClient: DependencyKey {
    static let liveValue = SuggestionsClient { req in
        var all: [SuggestedRecord] = []

        await withTaskGroup(of: [SuggestedRecord].self) { group in
            if req.providers.contains(.collectionDNA) {
                group.addTask { await fetchCollectionDNA(req) }
            }
            if req.providers.contains(.appleMusic) {
                group.addTask { await fetchAppleMusic(req) }
            }
            if req.providers.contains(.spotify) && !req.spotifyToken.isEmpty {
                group.addTask { await fetchSpotify(req) }
            }
            for await batch in group { all.append(contentsOf: batch) }
        }

        // Deduplicate + filter excluded + seed-shuffle for variety
        var seen = Set<String>()
        var unique: [SuggestedRecord] = []
        for r in all {
            guard !seen.contains(r.id), !req.excluded.contains(r.id),
                  !r.artist.isEmpty, !r.album.isEmpty else { continue }
            seen.insert(r.id)
            unique.append(r)
        }
        var rng = SeededRNG(seed: UInt64(bitPattern: Int64(req.seed &* 6364136223846793005 &+ 1)))
        unique.shuffle(using: &rng)
        return Array(unique.prefix(20))
    }
}

extension DependencyValues {
    var suggestions: SuggestionsClient {
        get { self[SuggestionsClient.self] }
        set { self[SuggestionsClient.self] = newValue }
    }
}

// MARK: – Seeded RNG (for reproducible shuffle per seed, variety across refreshes)

nonisolated struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    nonisolated init(seed: UInt64) { state = seed == 0 ? 0xDEADBEEF : seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

// MARK: – Collection DNA

/// Seeds suggestions from the user's own collection genres and artists via Discogs vinyl search.
/// Requires no external authentication — always available.
private func fetchCollectionDNA(_ req: SuggestionRequest) async -> [SuggestedRecord] {
    let fallbackGenres = ["Rock", "Jazz", "Electronic", "Soul", "Blues", "Folk"]
    let genres  = req.genres.isEmpty  ? fallbackGenres : req.genres
    let artists = req.artists

    var results: [SuggestedRecord] = []
    let page = (req.seed % 5) + 1

    // Rotate the genre/artist lists so each refresh seeds differently
    let rotatedGenres  = genres.rotated(by: req.seed)
    let rotatedArtists = artists.rotated(by: req.seed)

    // 3 genre-based searches
    for genre in rotatedGenres.prefix(3) {
        let items = await discogsVinylSearch(param: "genre", value: genre, page: page, token: req.discogsToken)
        results += items.map { SuggestedRecord(artist: $0.artist, album: $0.album, year: $0.year,
            genre: genre, coverURL: $0.thumbURL, discogsId: $0.id,
            provider: .collectionDNA, vinylFormat: $0.format) }
        try? await Task.sleep(nanoseconds: 80_000_000) // be polite to Discogs
        if results.count >= 8 { break }
    }

    // 2 artist-based searches (cross-artist discovery)
    for artist in rotatedArtists.prefix(2) {
        let items = await discogsVinylSearch(param: "artist", value: artist, page: page + 1, token: req.discogsToken)
        results += items.prefix(3).map { SuggestedRecord(artist: $0.artist, album: $0.album, year: $0.year,
            genre: $0.genre, coverURL: $0.thumbURL, discogsId: $0.id,
            provider: .collectionDNA, vinylFormat: $0.format) }
        try? await Task.sleep(nanoseconds: 80_000_000)
    }

    return results
}

// MARK: – Apple Music (MPMediaLibrary — local device library)

/// Reads the device's local music library for genres and artists, then
/// cross-references with Discogs for vinyl availability.
private func fetchAppleMusic(_ req: SuggestionRequest) async -> [SuggestedRecord] {
    guard MPMediaLibrary.authorizationStatus() == .authorized else { return [] }

    // MPMediaQuery is synchronous and potentially slow; run off main thread
    let (libraryArtists, libraryGenres): ([String], [String]) = await Task.detached(priority: .userInitiated) {
        let artists = (MPMediaQuery.artists().collections ?? [])
            .compactMap { $0.representativeItem?.artist }
            .filter { !$0.isEmpty }
        let genres = (MPMediaQuery.genres().collections ?? [])
            .compactMap { $0.representativeItem?.genre }
            .filter { !$0.isEmpty }
        return (artists, genres)
    }.value

    var results: [SuggestedRecord] = []
    let page = max(1, (req.seed % 4) + 1)

    // Prefer artists that are NOT already in the user's vinyl collection
    let newArtists = libraryArtists
        .filter { a in !req.artists.contains(where: { $0.lowercased() == a.lowercased() }) }
        .rotated(by: req.seed)

    for artist in newArtists.prefix(2) {
        let items = await discogsVinylSearch(param: "artist", value: artist, page: page, token: req.discogsToken)
        results += items.prefix(3).map { SuggestedRecord(artist: $0.artist, album: $0.album, year: $0.year,
            genre: $0.genre, coverURL: $0.thumbURL, discogsId: $0.id,
            provider: .appleMusic, vinylFormat: $0.format) }
        try? await Task.sleep(nanoseconds: 80_000_000)
    }

    // Also by library genres not already in collection
    let newGenres = libraryGenres
        .filter { g in !req.genres.contains(where: { $0.lowercased() == g.lowercased() }) }
        .rotated(by: req.seed)

    for genre in newGenres.prefix(2) {
        let items = await discogsVinylSearch(param: "genre", value: genre, page: page, token: req.discogsToken)
        results += items.prefix(2).map { SuggestedRecord(artist: $0.artist, album: $0.album, year: $0.year,
            genre: genre, coverURL: $0.thumbURL, discogsId: $0.id,
            provider: .appleMusic, vinylFormat: $0.format) }
        try? await Task.sleep(nanoseconds: 80_000_000)
    }

    return results
}

// MARK: – Spotify (top artists via access token)

/// Fetches the user's top artists from Spotify and discovers vinyl for those artists on Discogs.
private func fetchSpotify(_ req: SuggestionRequest) async -> [SuggestedRecord] {
    guard !req.spotifyToken.isEmpty else { return [] }

    guard let url = URL(string: "https://api.spotify.com/v1/me/top/artists?limit=20&time_range=medium_term")
    else { return [] }

    var urlReq = URLRequest(url: url)
    urlReq.setValue("Bearer \(req.spotifyToken)", forHTTPHeaderField: "Authorization")
    urlReq.setValue("VinCo/1.0 iOS", forHTTPHeaderField: "User-Agent")

    do {
        let (data, _) = try await URLSession.shared.data(for: urlReq)
        // Check for 401 (expired token) gracefully
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errObj = json["error"] as? [String: Any],
           errObj["status"] as? Int == 401 {
            return []
        }
        let resp = try JSONDecoder().decode(SpotifyTopArtistsResp.self, from: data)
        let topArtists = Array(resp.items.prefix(10).map { $0.name }.rotated(by: req.seed))
        let page = max(1, (req.seed % 4) + 1)

        var results: [SuggestedRecord] = []
        for artist in topArtists.prefix(3) {
            guard !req.artists.contains(where: { $0.lowercased() == artist.lowercased() }) else { continue }
            let items = await discogsVinylSearch(param: "artist", value: artist, page: page, token: req.discogsToken)
            results += items.prefix(3).map { SuggestedRecord(artist: $0.artist, album: $0.album, year: $0.year,
                genre: $0.genre, coverURL: $0.thumbURL, discogsId: $0.id,
                provider: .spotify, vinylFormat: $0.format) }
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
        return results
    } catch { return [] }
}

private nonisolated struct SpotifyTopArtistsResp: Decodable { let items: [SpotifyArtistItem] }
private nonisolated struct SpotifyArtistItem:      Decodable { let name: String; let genres: [String] }

// MARK: – Discogs vinyl search (shared by all providers)

private struct DiscogsVinylItem: Sendable {
    let id: Int; let artist: String; let album: String
    let year: String; let genre: String; let thumbURL: String; let format: String
}

/// Searches Discogs for vinyl releases using a specific parameter (genre, artist, q).
/// The `format=Vinyl` filter guarantees only vinyl releases are returned.
private func discogsVinylSearch(param: String, value: String, page: Int, token: String) async -> [DiscogsVinylItem] {
    guard !value.isEmpty,
          let enc = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
    else { return [] }

    let urlStr = "https://api.discogs.com/database/search?\(param)=\(enc)&type=release&format=Vinyl&per_page=8&page=\(page)"
    guard let url = URL(string: urlStr) else { return [] }

    var req = URLRequest(url: url)
    req.setValue("VinCo/1.0 iOS", forHTTPHeaderField: "User-Agent")
    if !token.isEmpty { req.setValue("Discogs token=\(token)", forHTTPHeaderField: "Authorization") }

    do {
        let (data, _) = try await URLSession.shared.data(for: req)
        let resp = try JSONDecoder().decode(DVSearchResp.self, from: data)
        return resp.results.compactMap { r -> DiscogsVinylItem? in
            // Split "Artist - Album" title
            let parts = r.title.components(separatedBy: " - ")
            let artist = parts.first?.trimmingCharacters(in: .whitespaces) ?? ""
            let album  = parts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespaces)
            guard !artist.isEmpty, !album.isEmpty else { return nil }

            // Pick the most specific vinyl format label for display
            let fmts = r.format ?? []
            let vinylFmt = fmts.first(where: { ["LP","7\"","12\"","10\"","EP","Single","Album"].contains($0) }) ?? "Vinyl"

            return DiscogsVinylItem(
                id: r.id, artist: artist, album: album,
                year: r.year ?? "", genre: r.genre?.first ?? "",
                thumbURL: r.thumb ?? "", format: vinylFmt)
        }
    } catch { return [] }
}

private nonisolated struct DVSearchResp:   Decodable { let results: [DVReleaseItem] }
private nonisolated struct DVReleaseItem:  Decodable {
    let id: Int; let title: String; let year: String?
    let genre: [String]?; let format: [String]?; let thumb: String?
}

// MARK: – Array rotation helper (for seed-based variety)

private extension Array {
    func rotated(by offset: Int) -> [Element] {
        guard count > 1 else { return self }
        let n = ((offset % count) + count) % count
        return Array(self[n...] + self[..<n])
    }
}

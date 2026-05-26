import Foundation
import ComposableArchitecture
import MediaPlayer

@Reducer
struct SuggestionsFeature {

    // MARK: – Apple Music authorization state

    nonisolated enum AppleMusicStatus: Equatable, Sendable {
        case notDetermined, authorized, denied

        nonisolated init(_ raw: MPMediaLibraryAuthorizationStatus) {
            switch raw {
            case .authorized:             self = .authorized
            case .denied, .restricted:   self = .denied
            default:                     self = .notDetermined
            }
        }
    }

    // MARK: – State

    @ObservableState
    struct State: Equatable {
        var suggestions:      [SuggestedRecord]  = []
        var isLoading:        Bool               = false
        var enabledProviders: Set<MusicProvider> = [.collectionDNA]
        var refreshSeed:      Int                = 0
        var appleMusicStatus: AppleMusicStatus   = .notDetermined
        var spotifyConnected: Bool               = false
        var spotifyExpired:   Bool               = false   // token present but expired
    }

    // MARK: – Action

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        /// Called once when the sheet appears; seeds the first fetch.
        case appeared(genres: [String], artists: [String], excluded: Set<String>)
        /// User tapped the refresh button.
        case refreshTapped(genres: [String], artists: [String], excluded: Set<String>)
        /// Toggle a provider chip.
        case providerToggled(MusicProvider, genres: [String], artists: [String], excluded: Set<String>)
        /// Result from the suggestions effect.
        case suggestionsLoaded([SuggestedRecord])
        /// Request Apple Music library permission, then re-fetch.
        case requestAppleMusic(genres: [String], artists: [String], excluded: Set<String>)
        case appleMusicStatusChanged(AppleMusicStatus)
        /// Called from the view after Spotify OAuth completes.
        case spotifyTokenSaved
        /// Called when a Spotify request returns 401 (expired token).
        case spotifyTokenExpired
    }

    // MARK: – Dependency

    @Dependency(\.suggestions) var suggestionClient

    // MARK: – Reducer

    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {

            case .appeared(let genres, let artists, let excluded):
                state.enabledProviders = loadPersistedProviders()
                state.appleMusicStatus = AppleMusicStatus(MPMediaLibrary.authorizationStatus())
                state.spotifyConnected = isSpotifyConnected()
                state.spotifyExpired   = false
                guard !state.isLoading, state.suggestions.isEmpty else { return .none }
                state.isLoading = true
                return fetchEffect(state: state, genres: genres, artists: artists, excluded: excluded)

            case .refreshTapped(let genres, let artists, let excluded):
                state.isLoading = true
                state.refreshSeed += 1
                return fetchEffect(state: state, genres: genres, artists: artists, excluded: excluded)

            case .providerToggled(let provider, let genres, let artists, let excluded):
                if state.enabledProviders.contains(provider) {
                    guard state.enabledProviders.count > 1 else { return .none } // keep at least one
                    state.enabledProviders.remove(provider)
                } else {
                    state.enabledProviders.insert(provider)
                }
                persistProviders(state.enabledProviders)
                // Re-fetch with the new provider set
                state.isLoading = true
                return fetchEffect(state: state, genres: genres, artists: artists, excluded: excluded)

            case .suggestionsLoaded(let list):
                state.isLoading = false
                state.suggestions = list
                return .none

            case .requestAppleMusic(let genres, let artists, let excluded):
                return .run { send in
                    let status = await withCheckedContinuation { cont in
                        MPMediaLibrary.requestAuthorization { s in cont.resume(returning: s) }
                    }
                    let mapped = AppleMusicStatus(status)
                    await send(.appleMusicStatusChanged(mapped))
                    if mapped == .authorized {
                        await send(.refreshTapped(genres: genres, artists: artists, excluded: excluded))
                    }
                }

            case .appleMusicStatusChanged(let s):
                state.appleMusicStatus = s
                return .none

            case .spotifyTokenSaved:
                state.spotifyConnected = true
                state.spotifyExpired   = false
                return .none

            case .spotifyTokenExpired:
                state.spotifyExpired = true
                return .none

            case .binding:
                return .none
            }
        }
    }

    // MARK: – Helpers

    private func fetchEffect(state: State,
                             genres: [String], artists: [String],
                             excluded: Set<String>) -> Effect<Action> {
        let providers    = state.enabledProviders
        let seed         = state.refreshSeed
        let discogsToken = UserDefaults.standard.string(forKey: "rb_discogs") ?? ""
        let spotifyToken = UserDefaults.standard.string(forKey: "rb_sp_token") ?? ""
        let client       = suggestionClient

        return .run { send in
            let req = SuggestionRequest(
                genres: genres, artists: artists, excluded: excluded,
                providers: providers, seed: seed,
                discogsToken: discogsToken, spotifyToken: spotifyToken
            )
            let results = await client.suggest(req)
            await send(.suggestionsLoaded(results))
        }
    }

    private func isSpotifyConnected() -> Bool {
        guard let token = UserDefaults.standard.string(forKey: "rb_sp_token"), !token.isEmpty else { return false }
        let expiry = UserDefaults.standard.double(forKey: "rb_sp_expiry")
        return expiry == 0 || Date().timeIntervalSince1970 < expiry
    }

    // MARK: – Provider persistence

    private func loadPersistedProviders() -> Set<MusicProvider> {
        guard let raw = UserDefaults.standard.string(forKey: "rb_providers"),
              let arr = try? JSONDecoder().decode([String].self, from: Data(raw.utf8))
        else { return [.collectionDNA] }
        let set = Set(arr.compactMap { MusicProvider(rawValue: $0) })
        return set.isEmpty ? [.collectionDNA] : set
    }

    private func persistProviders(_ providers: Set<MusicProvider>) {
        guard let data = try? JSONEncoder().encode(providers.map(\.rawValue)),
              let str  = String(data: data, encoding: .utf8)
        else { return }
        UserDefaults.standard.set(str, forKey: "rb_providers")
    }
}

import SwiftUI
import SwiftData
import ComposableArchitecture
import AuthenticationServices
import CryptoKit
import MediaPlayer

// MARK: – Spotify app credentials (developer-set, not user-entered)
// 1. Register VinCo at developer.spotify.com (free).
// 2. Add redirect URI: vinco-app://spotify
// 3. Paste your Client ID below — users just tap "Connect with Spotify" in the app.
private let kSpotifyClientId = ""

struct SuggestionsView: View {
    @Bindable var store: StoreOf<SuggestionsFeature>
    @Environment(\.modelContext) private var ctx
    @Environment(Settings.self)  private var settings

    @Query private var allRecords: [Record]

    // MARK: – Derived collection data (passed into the TCA actions)

    private var topGenres: [String] {
        var counts: [String: Int] = [:]
        allRecords.filter { !$0.isWishlist }.forEach { counts[$0.genre, default: 0] += 1 }
        return counts.sorted { $0.value > $1.value }.map(\.key).filter { !$0.isEmpty }
    }

    private var topArtists: [String] {
        var counts: [String: Int] = [:]
        allRecords.filter { !$0.isWishlist }.forEach { counts[$0.artist, default: 0] += 1 }
        return counts.sorted { $0.value > $1.value }.map(\.key).filter { !$0.isEmpty }
    }

    private var excludedKeys: Set<String> {
        Set(allRecords.map { "\($0.artist.lowercased())|\($0.album.lowercased())" })
    }

    // Tracks which suggestions were added this session (for immediate card feedback)
    @State private var addedIds:            Set<String>      = []
    @State private var selectedSuggestion:  SuggestedRecord? = nil
    @State private var spotifyAuthError:    String?          = nil
    @State private var isAuthenticatingSpotify               = false
    @State private var pkceVerifier:        String           = ""

    private let cols = [GridItem(.adaptive(minimum: 158), spacing: 12)]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                providerStrip
                Rectangle().fill(Theme.divide).frame(height: 1)

                if store.isLoading {
                    loadingView
                } else if store.suggestions.isEmpty {
                    emptyView
                } else {
                    suggestionsGrid
                }
            }
            .background(settings.bg0.ignoresSafeArea())
            .navigationTitle("Record Suggestions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settings.bg1, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    CloseButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.send(.refreshTapped(
                            genres: topGenres, artists: topArtists, excluded: excludedKeys))
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(store.isLoading ? Theme.textT : settings.accentColor)
                    }
                    .disabled(store.isLoading)
                }
            }
        }
        .task {
            store.send(.appeared(genres: topGenres, artists: topArtists, excluded: excludedKeys))
        }
        // Detail sheet — opens when a card cover is tapped
        .sheet(item: $selectedSuggestion) { suggestion in
            SuggestionDetailSheet(
                suggestion: suggestion,
                onAdd: { addToWishlist(suggestion) }
            )
            .environment(settings)
            .preferredColorScheme(settings.preferredScheme)
            .environment(\.font, Theme.courier(14))
        }
        .alert("Spotify Error", isPresented: .constant(spotifyAuthError != nil)) {
            Button("OK") { spotifyAuthError = nil }
        } message: {
            Text(spotifyAuthError ?? "")
        }
    }

    // MARK: – Provider strip

    private var providerStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(MusicProvider.allCases, id: \.self) { provider in
                    providerChip(provider)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(settings.bg1)
    }

    @ViewBuilder
    private func providerChip(_ provider: MusicProvider) -> some View {
        let enabled   = store.enabledProviders.contains(provider)
        let available = isAvailable(provider)

        Button {
            handleProviderTap(provider)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: available ? provider.icon : "lock.fill")
                    .font(.system(size: 12))
                Text(provider.displayName)
                    .font(Theme.courier(12, enabled && available ? .semibold : .regular))

                if provider == .spotify && store.spotifyExpired {
                    Text("EXPIRED")
                        .font(Theme.courier(8, .bold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.orange.opacity(0.2))
                        .clipShape(Capsule())
                }
                if isAuthenticatingSpotify && provider == .spotify {
                    ProgressView().scaleEffect(0.7).tint(.white)
                }
            }
            .foregroundStyle(chipForeground(provider: provider, enabled: enabled, available: available))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(chipBackground(provider: provider, enabled: enabled, available: available))
            .clipShape(Capsule())
            .overlay {
                if !available {
                    Capsule().stroke(Theme.divide, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func chipForeground(provider: MusicProvider, enabled: Bool, available: Bool) -> Color {
        if !available { return Theme.textT }
        return enabled ? .black : Theme.textS
    }

    private func chipBackground(provider: MusicProvider, enabled: Bool, available: Bool) -> Color {
        if !available { return settings.bg2 }
        if enabled {
            switch provider {
            case .collectionDNA: return settings.accentColor
            case .appleMusic:    return Color(hex: "#FC3C44")
            case .spotify:       return Color(hex: "#1DB954")
            }
        }
        return settings.bg2
    }

    // MARK: – Provider availability

    private func isAvailable(_ provider: MusicProvider) -> Bool {
        switch provider {
        case .collectionDNA: return true
        case .appleMusic:    return store.appleMusicStatus == .authorized
        case .spotify:       return store.spotifyConnected
        }
    }

    // MARK: – Provider tap handling

    private func handleProviderTap(_ provider: MusicProvider) {
        switch provider {
        case .collectionDNA:
            store.send(.providerToggled(provider, genres: topGenres, artists: topArtists, excluded: excludedKeys))

        case .appleMusic:
            switch store.appleMusicStatus {
            case .authorized:
                store.send(.providerToggled(provider, genres: topGenres, artists: topArtists, excluded: excludedKeys))
            case .denied:
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            case .notDetermined:
                store.send(.requestAppleMusic(genres: topGenres, artists: topArtists, excluded: excludedKeys))
            }

        case .spotify:
            if store.spotifyConnected && !store.spotifyExpired {
                store.send(.providerToggled(provider, genres: topGenres, artists: topArtists, excluded: excludedKeys))
            } else {
                startSpotifyAuth()
            }
        }
    }

    // MARK: – Loading & empty states

    private var loadingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView().scaleEffect(1.4).tint(settings.accentColor)
            Text("Discovering vinyl…")
                .font(Theme.courier(14))
                .foregroundStyle(Theme.textT)
            Spacer()
        }
    }

    private var emptyView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "waveform.slash")
                .font(.system(size: 52))
                .foregroundStyle(Theme.textT)
            Text("No suggestions found")
                .font(Theme.courier(16))
                .foregroundStyle(Theme.textS)
            Text("Try enabling more providers above,\nor add records to your collection\nso we can learn your taste.")
                .font(Theme.courier(12))
                .foregroundStyle(Theme.textT)
                .multilineTextAlignment(.center)
            Button {
                store.send(.refreshTapped(genres: topGenres, artists: topArtists, excluded: excludedKeys))
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .font(Theme.courier(14, .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 24).padding(.vertical, 11)
                    .background(settings.accentColor)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: – Suggestions grid

    private var suggestionsGrid: some View {
        ScrollView {
            LazyVGrid(columns: cols, spacing: 12) {
                ForEach(store.suggestions) { suggestion in
                    suggestionCard(suggestion)
                }
            }
            .padding(12)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func suggestionCard(_ rec: SuggestedRecord) -> some View {
        let alreadyAdded = addedIds.contains(rec.id) || excludedKeys.contains(rec.id)

        VStack(spacing: 0) {

            // ── Tappable cover area → opens detail sheet ──────────────────
            Button { selectedSuggestion = rec } label: {
                ZStack(alignment: .bottomLeading) {
                    coverImage(for: rec)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .clipped()

                    // Bottom gradient so text is legible over any cover
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.75)],
                        startPoint: .center, endPoint: .bottom)
                        .aspectRatio(1, contentMode: .fit)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(rec.album)
                            .font(Theme.courier(13, .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(rec.artist)
                            .font(Theme.courier(11))
                            .foregroundStyle(.white.opacity(0.80))
                            .lineLimit(1)
                    }
                    .padding(10)
                }
            }
            .buttonStyle(.plain)

            // ── Meta row + quick-add heart ────────────────────────────────
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 3) {
                    if !rec.year.isEmpty {
                        Text(rec.year)
                            .font(Theme.courier(10))
                            .foregroundStyle(Theme.textT)
                    }
                    if !rec.genre.isEmpty {
                        Text(rec.genre)
                            .font(Theme.courier(10, .semibold))
                            .foregroundStyle(Theme.textS)
                            .lineLimit(1)
                    }
                }
                Spacer()

                if alreadyAdded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.green)
                } else {
                    Button {
                        addToWishlist(rec)
                    } label: {
                        Image(systemName: "heart.badge.plus")
                            .font(.system(size: 20))
                            .foregroundStyle(settings.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(settings.bg1)

            // ── Provider badge ────────────────────────────────────────────
            providerBadge(rec.provider)
        }
        .background(settings.bg2)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardR))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardR)
                .stroke(alreadyAdded ? Color.green.opacity(0.4) : Color.clear, lineWidth: 1.5)
        )
    }

    @ViewBuilder
    private func coverImage(for rec: SuggestedRecord) -> some View {
        if rec.coverURL.isEmpty {
            ZStack {
                settings.bg3
                VinylView(color: Record.randomColor()).padding(28)
            }
        } else {
            AsyncImage(url: URL(string: rec.coverURL)) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                case .failure:
                    ZStack { settings.bg3; VinylView(color: Record.randomColor()).padding(28) }
                default:
                    ZStack { settings.bg3; ProgressView().tint(settings.accentColor) }
                }
            }
        }
    }

    private func providerBadge(_ provider: MusicProvider) -> some View {
        HStack(spacing: 4) {
            Image(systemName: provider.icon).font(.system(size: 9))
            Text(provider.displayName.uppercased()).font(Theme.courier(8, .semibold))
        }
        .foregroundStyle(Theme.textT)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(settings.bg1)
    }

    // MARK: – Add to wishlist (quick-add from grid)

    private func addToWishlist(_ suggestion: SuggestedRecord) {
        let record = Record(
            artist:    suggestion.artist,
            album:     suggestion.album,
            year:      suggestion.year,
            genre:     suggestion.genre,
            label:     "",
            format:    suggestion.vinylFormat,
            country:   "",
            notes:     "",
            condition: "VG",
            isWishlist: true
        )
        record.discogsId = suggestion.discogsId > 0 ? suggestion.discogsId : nil
        record.coverURL  = suggestion.coverURL
        ctx.insert(record)

        // Fetch and cache cover art asynchronously
        if !suggestion.coverURL.isEmpty {
            Task {
                guard let url = URL(string: suggestion.coverURL),
                      let (data, _) = try? await URLSession.shared.data(from: url)
                else { return }
                await MainActor.run { record.coverData = data }
            }
        }

        _ = withAnimation(.spring(response: 0.3)) {
            addedIds.insert(suggestion.id)
        }
    }

    // MARK: – Spotify PKCE Auth

    private func startSpotifyAuth() {
        guard !kSpotifyClientId.isEmpty else {
            spotifyAuthError = "Spotify Client ID not configured. Open SuggestionsView.swift and paste your Client ID into kSpotifyClientId."
            return
        }
        guard !isAuthenticatingSpotify else { return }

        let verifier  = generatePKCEVerifier()
        let challenge = generatePKCEChallenge(from: verifier)
        pkceVerifier  = verifier

        let redirectURI = "vinco-app://spotify"
        guard let encodedURI = redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let authURL = URL(string:
                "https://accounts.spotify.com/authorize" +
                "?client_id=\(kSpotifyClientId)" +
                "&response_type=code" +
                "&redirect_uri=\(encodedURI)" +
                "&code_challenge=\(challenge)" +
                "&code_challenge_method=S256" +
                "&scope=user-top-read")
        else { return }

        isAuthenticatingSpotify = true

        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "vinco-app"
        ) { callbackURL, error in
            isAuthenticatingSpotify = false
            if let error = error as? ASWebAuthenticationSessionError,
               error.code == .canceledLogin { return }
            guard let callbackURL,
                  let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                  let code = components.queryItems?.first(where: { $0.name == "code" })?.value
            else {
                spotifyAuthError = "Spotify login failed. Make sure 'vinco-app://spotify' is registered as a redirect URI."
                return
            }
            Task { await exchangeSpotifyCode(code: code, verifier: verifier) }
        }
        session.prefersEphemeralWebBrowserSession = false
        session.presentationContextProvider = SpotifyAuthPresenter.shared
        session.start()
    }

    private func exchangeSpotifyCode(code: String, verifier: String) async {
        guard let url = URL(string: "https://accounts.spotify.com/api/token") else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let redirectURI = "vinco-app://spotify"
        let body = [
            "client_id=\(kSpotifyClientId)",
            "grant_type=authorization_code",
            "code=\(code)",
            "redirect_uri=\(redirectURI)",
            "code_verifier=\(verifier)"
        ].joined(separator: "&")
        req.httpBody = body.data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let resp = try JSONDecoder().decode(SpotifyTokenResp.self, from: data)
            UserDefaults.standard.set(resp.access_token, forKey: "rb_sp_token")
            let expiry = Date().timeIntervalSince1970 + Double(resp.expires_in)
            UserDefaults.standard.set(expiry, forKey: "rb_sp_expiry")
            if let rt = resp.refresh_token {
                UserDefaults.standard.set(rt, forKey: "rb_sp_refresh")
            }
            await MainActor.run {
                store.send(.spotifyTokenSaved)
                if !store.enabledProviders.contains(.spotify) {
                    store.send(.providerToggled(.spotify,
                        genres: topGenres, artists: topArtists, excluded: excludedKeys))
                } else {
                    store.send(.refreshTapped(genres: topGenres, artists: topArtists, excluded: excludedKeys))
                }
            }
        } catch {
            await MainActor.run {
                spotifyAuthError = "Token exchange failed. Please try again."
            }
        }
    }

    // MARK: – PKCE helpers

    private func generatePKCEVerifier() -> String {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        return String((0..<64).map { _ in chars.randomElement()! })
    }

    private func generatePKCEChallenge(from verifier: String) -> String {
        let data   = Data(verifier.utf8)
        let digest = SHA256.hash(data: data)
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: – Spotify ASWebAuthenticationSession presentation context

private final class SpotifyAuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding, @unchecked Sendable {
    static let shared = SpotifyAuthPresenter()
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        if let active {
            return ASPresentationAnchor(windowScene: active)
        }
        // Last resort: find any key window (unreachable in practice on iOS 13+)
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })
        ?? UIWindow(frame: .zero)
    }
}

// MARK: – Spotify token response

private nonisolated struct SpotifyTokenResp: Decodable {
    let access_token:  String
    let expires_in:    Int
    let refresh_token: String?
}

// MARK: – Suggestion detail sheet

struct SuggestionDetailSheet: View {
    let suggestion: SuggestedRecord
    let onAdd:      () -> Void

    @Environment(Settings.self)  private var settings
    @Environment(\.dismiss)      private var dismiss
    @Environment(\.modelContext) private var ctx

    @Query private var allRecords: [Record]

    private var alreadyAdded: Bool {
        allRecords.contains {
            $0.artist.lowercased() == suggestion.artist.lowercased() &&
            $0.album.lowercased()  == suggestion.album.lowercased()  &&
            ($0.isWishlist || !$0.isWishlist) // either collection OR wishlist counts as "have it"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    coverSection
                    infoSection
                }
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .background(settings.bg0.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settings.bg0, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CloseButton()
                }
            }
        }
    }

    // MARK: – Cover section

    private var coverSection: some View {
        ZStack(alignment: .bottom) {
            // Cover image
            Group {
                if suggestion.coverURL.isEmpty {
                    ZStack {
                        settings.bg2
                        VinylView(color: Record.randomColor()).padding(50)
                    }
                } else {
                    AsyncImage(url: URL(string: suggestion.coverURL)) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        case .failure:
                            ZStack { settings.bg2; VinylView(color: Record.randomColor()).padding(50) }
                        default:
                            ZStack { settings.bg2; ProgressView().tint(settings.accentColor) }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .clipped()

            // Gradient fade into background at bottom
            LinearGradient(
                colors: [.clear, settings.bg0],
                startPoint: .center, endPoint: .bottom)
                .frame(height: 140)
        }
    }

    // MARK: – Info section

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Artist & Album
            VStack(alignment: .leading, spacing: 4) {
                Text(suggestion.artist.uppercased())
                    .font(Theme.courier(11, .semibold))
                    .foregroundStyle(Theme.textT)
                    .tracking(1)
                Text(suggestion.album)
                    .font(Theme.courier(22, .bold))
                    .foregroundStyle(Theme.textP)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 16)

            // Meta pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if !suggestion.year.isEmpty {
                        metaPill(suggestion.year, icon: "calendar")
                    }
                    if !suggestion.genre.isEmpty {
                        metaPill(suggestion.genre, icon: "music.note")
                    }
                    metaPill(suggestion.vinylFormat, icon: "opticaldisc")
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 20)

            // Divider
            Rectangle().fill(Theme.divide).frame(height: 1).padding(.horizontal, 20)

            // Provider row
            HStack(spacing: 8) {
                Image(systemName: suggestion.provider.icon)
                    .font(.system(size: 12))
                Text("Suggested via \(suggestion.provider.displayName)")
                    .font(Theme.courier(13))
            }
            .foregroundStyle(Theme.textT)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Rectangle().fill(Theme.divide).frame(height: 1).padding(.horizontal, 20)

            // CTA — Add to Wishlist or Already Added
            if alreadyAdded {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                    Text("Already in your collection or wishlist")
                        .font(Theme.courier(14, .semibold))
                }
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Color.green.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 20)
                .padding(.top, 20)
            } else {
                Button {
                    onAdd()
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "heart.badge.plus")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Add to Wishlist")
                            .font(Theme.courier(16, .semibold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(settings.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: settings.accentColor.opacity(0.35), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
        }
    }

    private func metaPill(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10))
            Text(text).font(Theme.courier(12, .semibold))
        }
        .foregroundStyle(Theme.textS)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(settings.bg2)
        .clipShape(Capsule())
    }
}

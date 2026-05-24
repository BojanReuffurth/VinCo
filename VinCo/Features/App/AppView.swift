import SwiftUI
import SwiftData
import ComposableArchitecture

struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>
    @Environment(Settings.self) private var settings
    @Query(filter: #Predicate<Record> { $0.isWishlist == false }) private var collectionRecords: [Record]
    @Query(filter: #Predicate<Record> { $0.isWishlist == true })  private var wishlistRecords: [Record]
    @State private var showStats    = false
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            appHeader
            Rectangle().fill(Theme.divide).frame(height: 1)
            TabView(selection: $store.tab.sending(\.tabSelected)) {
                CollectionView(store: store.scope(state: \.collection, action: \.collection))
                    .tag(AppFeature.Tab.collection)
                    .toolbar(.hidden, for: .tabBar)
                CollectionView(store: store.scope(state: \.wishlist, action: \.wishlist))
                    .tag(AppFeature.Tab.wishlist)
                    .toolbar(.hidden, for: .tabBar)
            }
        }
        .background(Theme.bg0)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomCounts }
        .overlay(alignment: .bottomTrailing) {
            fab.padding(.trailing, 20).padding(.bottom, 16)
        }
        .fontDesign(.monospaced)
        .preferredColorScheme(settings.preferredScheme)
        .onChange(of: settings.accentHex)  { _, new in AppearanceSetup.apply(accent: new) }
        .onChange(of: settings.schemeKey)  { _, _   in AppearanceSetup.apply(accent: settings.accentHex) }
        .sheet(isPresented: $showStats) {
            StatsView(store: store.scope(state: \.stats, action: \.stats))
                .preferredColorScheme(settings.preferredScheme)
                .fontDesign(.monospaced)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(store: store.scope(state: \.settings, action: \.settings))
                .preferredColorScheme(settings.preferredScheme)
                .fontDesign(.monospaced)
        }
    }

    // MARK: – App header
    private var appHeader: some View {
        HStack(spacing: 10) {
            // Logo
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(settings.accentColor.opacity(0.15)).frame(width: 32, height: 32)
                    Image(systemName: "opticaldisc.fill")
                        .font(.system(size: 15)).foregroundStyle(settings.accentColor)
                }
                Text("VinCo")
                    .font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.textP)
            }
            Spacer()

            // Pinned stat badges
            if !pinnedStatItems.isEmpty {
                HStack(spacing: 6) {
                    ForEach(pinnedStatItems, id: \.0) { key, label, value in
                        VStack(spacing: 1) {
                            Text(value)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(settings.accentColor)
                            Text(label)
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(Theme.textT)
                        }
                        .frame(minWidth: 28)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Theme.bg2)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Stats button
            Button { showStats = true } label: {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textS)
                    .frame(width: 34, height: 34)
                    .background(Theme.bg2)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            // Settings button
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textS)
                    .frame(width: 34, height: 34)
                    .background(Theme.bg2)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Theme.bg1)
    }

    // MARK: – Pinned stat items for header display
    private var pinnedStatItems: [(String, String, String)] {
        var items: [(String, String, String)] = []
        let pinned = settings.pinnedStats
        if pinned.contains("records")  { items.append(("records",  "REC",  "\(collectionRecords.count)")) }
        if pinned.contains("wishlist") { items.append(("wishlist", "WL",   "\(wishlistRecords.count)")) }
        if pinned.contains("genres")   {
            let gc = Set(collectionRecords.compactMap { $0.genre.isEmpty ? nil : $0.genre }).count
            items.append(("genres", "GNRS", "\(gc)"))
        }
        if pinned.contains("value") {
            let v = collectionRecords.compactMap(\.currentValue).reduce(0, +)
            items.append(("value", "VAL", "\(settings.currency)\(Int(v))"))
        }
        return items
    }

    // MARK: – Bottom counts bar
    private var bottomCounts: some View {
        HStack(spacing: 0) {
            Button { store.send(.tabSelected(.collection)) } label: {
                VStack(spacing: 2) {
                    Text("\(collectionRecords.count)")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(store.tab == .collection ? settings.accentColor : Theme.textT)
                    Text("COLLECTION")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.textT)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            Rectangle().fill(Theme.divide).frame(width: 1, height: 32)

            Button { store.send(.tabSelected(.wishlist)) } label: {
                VStack(spacing: 2) {
                    Text("\(wishlistRecords.count)")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(store.tab == .wishlist ? settings.accentColor : Theme.textT)
                    Text("WISHLIST")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.textT)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
        .background(Theme.bg1.ignoresSafeArea(edges: .bottom))
    }

    // MARK: – Floating action button
    private var fab: some View {
        Button {
            store.send(store.tab == .wishlist ? .wishlist(.addTapped) : .collection(.addTapped))
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 56, height: 56)
                .background(settings.accentColor)
                .clipShape(Circle())
                .shadow(color: settings.accentColor.opacity(0.4), radius: 12, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

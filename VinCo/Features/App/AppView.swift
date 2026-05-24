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
            collectionTabs
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
        .preferredColorScheme(.dark)
        .onChange(of: settings.accentHex) { _, new in AppearanceSetup.apply(accent: new) }
        .sheet(isPresented: $showStats) {
            StatsView(store: store.scope(state: \.stats, action: \.stats))
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(store: store.scope(state: \.settings, action: \.settings))
                .preferredColorScheme(.dark)
        }
    }

    // MARK: – App header
    private var appHeader: some View {
        HStack(spacing: 12) {
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
            Button { showStats = true } label: {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textS)
                    .frame(width: 34, height: 34)
                    .background(Theme.bg2)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
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

    // MARK: – Collection / Wishlist top tabs
    private var collectionTabs: some View {
        HStack(spacing: 0) {
            tabBtn(.collection, "COLLECTION", collectionRecords.count)
            tabBtn(.wishlist,   "WISHLIST",   wishlistRecords.count)
            Spacer()
        }
        .background(Theme.bg1)
    }

    private func tabBtn(_ tab: AppFeature.Tab, _ label: String, _ count: Int) -> some View {
        Button { store.send(.tabSelected(tab)) } label: {
            VStack(spacing: 0) {
                Text("\(label) (\(count))")
                    .font(.system(size: 12,
                                  weight: store.tab == tab ? .semibold : .regular,
                                  design: .monospaced))
                    .foregroundStyle(store.tab == tab ? settings.accentColor : Theme.textT)
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)
                Rectangle()
                    .fill(store.tab == tab ? settings.accentColor : Color.clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: – Bottom counts bar
    private var bottomCounts: some View {
        HStack(spacing: 0) {
            Button { store.send(.tabSelected(.collection)) } label: {
                VStack(spacing: 2) {
                    Text("\(collectionRecords.count)")
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundStyle(store.tab == .collection ? settings.accentColor : Theme.textT)
                    Text("COLLECTION")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.textT)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            Rectangle().fill(Theme.divide).frame(width: 1, height: 32)
            Button { store.send(.tabSelected(.wishlist)) } label: {
                VStack(spacing: 2) {
                    Text("\(wishlistRecords.count)")
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundStyle(store.tab == .wishlist ? settings.accentColor : Theme.textT)
                    Text("WISHLIST")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
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

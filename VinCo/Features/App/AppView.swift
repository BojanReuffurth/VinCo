import SwiftUI
import ComposableArchitecture

struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>
    @Environment(Settings.self) private var settings

    var body: some View {
        TabView(selection: $store.tab.sending(\.tabSelected)) {
            CollectionView(store: store.scope(state: \.collection, action: \.collection))
                .tag(AppFeature.Tab.collection)
                .toolbar(.hidden, for: .tabBar)
            CollectionView(store: store.scope(state: \.wishlist, action: \.wishlist))
                .tag(AppFeature.Tab.wishlist)
                .toolbar(.hidden, for: .tabBar)
            StatsView(store: store.scope(state: \.stats, action: \.stats))
                .tag(AppFeature.Tab.stats)
                .toolbar(.hidden, for: .tabBar)
            SettingsView(store: store.scope(state: \.settings, action: \.settings))
                .tag(AppFeature.Tab.settings)
                .toolbar(.hidden, for: .tabBar)
        }
        .preferredColorScheme(.dark)
        .onChange(of: settings.accentHex) { _, new in AppearanceSetup.apply(accent: new) }
        .safeAreaInset(edge: .bottom, spacing: 0) { tabBar }
    }

    private var tabBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.divide).frame(height: 1)
            HStack(spacing: 0) {
                tabBtn(.collection, "Collection", "opticaldisc")
                tabBtn(.wishlist,   "Wishlist",   "heart.fill")
                tabBtn(.stats,      "Stats",      "chart.bar.fill")
                tabBtn(.settings,   "Settings",   "gearshape.fill")
            }
            .frame(height: Theme.tabBarHeight)
        }
        .background(Theme.bg1.ignoresSafeArea(edges: .bottom))
    }

    private func tabBtn(_ tab: AppFeature.Tab, _ label: String, _ icon: String) -> some View {
        Button { store.send(.tabSelected(tab)) } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 22))
                Text(label).font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(store.tab == tab ? settings.accentColor : Theme.textS)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        }
        .buttonStyle(.plain)
    }
}

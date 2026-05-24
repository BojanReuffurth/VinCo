import SwiftUI
import SwiftData
import ComposableArchitecture

struct CollectionView: View {
    @Bindable var store: StoreOf<CollectionFeature>
    @Environment(\.modelContext) private var ctx
    @Environment(Settings.self) private var settings

    @Query(sort: \Record.dateAdded, order: .reverse) private var allRecords: [Record]

    private var records: [Record] { allRecords.filter { $0.isWishlist == store.isWishlist } }
    private var genres: [String] {
        ["All"] + Set(records.compactMap { $0.genre.isEmpty ? nil : $0.genre }).sorted()
    }
    private var displayed: [Record] {
        var r = records
        if !store.search.isEmpty {
            r = r.filter { $0.artist.localizedCaseInsensitiveContains(store.search) ||
                           $0.album.localizedCaseInsensitiveContains(store.search) }
        }
        if store.genre != "All" { r = r.filter { $0.genre == store.genre } }
        switch store.sortBy {
        case .dateAdded: r.sort { $0.dateAdded > $1.dateAdded }
        case .artistAZ:  r.sort { $0.artist.lowercased() < $1.artist.lowercased() }
        case .artistZA:  r.sort { $0.artist.lowercased() > $1.artist.lowercased() }
        case .albumAZ:   r.sort { $0.album.lowercased()  < $1.album.lowercased()  }
        case .yearAsc:   r.sort { $0.year < $1.year }
        case .yearDesc:  r.sort { $0.year > $1.year }
        }
        return r
    }
    private let cols = [GridItem(.adaptive(minimum: 155), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            header
            searchBar
            filterBar
            Rectangle().fill(Theme.divide).frame(height: 1)
            if displayed.isEmpty { emptyState }
            else if settings.layout == "list" { listContent }
            else { gridContent }
        }
        .background(Theme.bg0)
        .sheet(item: $store.scope(state: \.detail, action: \.detail)) { s in
            DetailView(store: s)
        }
        .sheet(item: $store.scope(state: \.edit, action: \.edit)) { s in
            EditView(store: s)
        }
    }

    // MARK: – Header
    private var header: some View {
        HStack(spacing: 10) {
            Text(store.isWishlist ? "Wishlist" : "Collection")
                .font(.system(size: 28, weight: .bold)).foregroundStyle(Theme.textP)
            Spacer()
            Text("\(displayed.count)")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textT)
            Button { store.send(.addTapped) } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3).foregroundStyle(settings.accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)
        .background(Theme.bg1)
    }

    // MARK: – Search bar
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.textT).font(.system(size: 14))
            TextField("Search…", text: $store.search.sending(\.searchChanged))
                .font(.system(size: 14)).foregroundStyle(Theme.textP)
                .autocorrectionDisabled()
            if !store.search.isEmpty {
                Button { store.send(.searchChanged("")) } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textT)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Theme.bg2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Theme.bg1)
    }

    // MARK: – Filter bar
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(CollectionFeature.SortBy.allCases, id: \.self) { opt in
                        Button { store.send(.sortSelected(opt)) } label: {
                            if store.sortBy == opt {
                                Label(opt.rawValue, systemImage: "checkmark")
                            } else {
                                Text(opt.rawValue)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.arrow.down").font(.system(size: 11, weight: .semibold))
                        Text(store.sortBy.rawValue).font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Theme.textS)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Theme.bg2).clipShape(Capsule())
                }
                .buttonStyle(.plain)
                ForEach(genres, id: \.self) { g in
                    Button { store.send(.genreSelected(g)) } label: {
                        Text(g)
                            .font(.system(size: 13, weight: store.genre == g ? .semibold : .regular))
                            .foregroundStyle(store.genre == g ? Color.black : Theme.textS)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(store.genre == g ? settings.accentColor : Theme.bg2)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .background(Theme.bg1)
    }

    // MARK: – Grid / List
    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: cols, spacing: 12) {
                ForEach(displayed) { rec in
                    CardView(
                        record: rec,
                        onEdit:   { store.send(.editTapped(rec)) },
                        onMove:   { rec.isWishlist.toggle() },
                        onDelete: { ctx.delete(rec) }
                    )
                    .contextMenu { ctxMenu(rec) }
                }
            }
            .padding(12)
        }
        .scrollIndicators(.hidden)
    }

    private var listContent: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(displayed) { rec in
                    listRow(rec)
                }
            }
            .padding(12)
        }
        .scrollIndicators(.hidden)
    }

    private func listRow(_ rec: Record) -> some View {
        HStack(spacing: 12) {
            Group {
                if let d = rec.coverData, let img = UIImage(data: d) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    ZStack { Theme.bg2; VinylView(color: rec.colorHex) }
                }
            }
            .frame(width: 54, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(rec.artist).font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textP).lineLimit(1)
                Text(rec.album).font(.system(size: 12))
                    .foregroundStyle(Theme.textS).lineLimit(1)
                if !rec.condition.isEmpty {
                    Text(rec.condition)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(.white.opacity(0.25))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            Spacer()
            Button { store.send(.editTapped(rec)) } label: {
                Image(systemName: "pencil").foregroundStyle(Theme.textT)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Theme.bg1)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: – Empty state
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: store.isWishlist ? "heart.slash" : "square.stack.3d.up.slash")
                .font(.system(size: 56)).foregroundStyle(Theme.textT)
            Text(store.isWishlist ? "Wishlist is empty" : "Collection is empty")
                .font(.system(size: 17, weight: .medium)).foregroundStyle(Theme.textS)
            Button { store.send(.addTapped) } label: {
                Label("Add a Record", systemImage: "plus")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.black)
                    .padding(.horizontal, 24).padding(.vertical, 11)
                    .background(settings.accentColor).clipShape(Capsule())
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    @ViewBuilder
    private func ctxMenu(_ rec: Record) -> some View {
        Button { store.send(.editTapped(rec)) } label: { Label("Edit", systemImage: "pencil") }
        Button { rec.isWishlist.toggle() } label: {
            Label(rec.isWishlist ? "Move to Collection" : "Move to Wishlist",
                  systemImage: rec.isWishlist ? "square.stack.3d.up" : "heart")
        }
        Divider()
        Button(role: .destructive) { ctx.delete(rec) } label: { Label("Delete", systemImage: "trash") }
    }
}

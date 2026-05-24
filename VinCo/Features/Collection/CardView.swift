import SwiftUI

struct CardView: View {
    let record: Record
    var onInfo:   () -> Void = {}
    var onEdit:   () -> Void = {}
    var onMove:   () -> Void = {}
    var onDelete: () -> Void = {}
    @Environment(Settings.self) private var settings
    @State private var isFlipped = false

    var body: some View {
        ZStack {
            front
                .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
                .opacity(isFlipped ? 0 : 1)
            back
                .rotation3DEffect(.degrees(isFlipped ? 0 : -180), axis: (x: 0, y: 1, z: 0))
                .opacity(isFlipped ? 1 : 0)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardR))
        .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 4)
        .onTapGesture {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { isFlipped.toggle() }
        }
    }

    private var front: some View {
        ZStack(alignment: .bottomLeading) {
            // Cover art or vinyl placeholder
            Group {
                if let d = record.coverData, let img = UIImage(data: d) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    ZStack { Theme.bg1; VinylView(color: record.colorHex).padding(24) }
                }
            }
            .aspectRatio(1, contentMode: .fit).frame(maxWidth: .infinity).clipped()

            // Bottom gradient: album bold, artist secondary
            VStack(alignment: .leading, spacing: 2) {
                Text(record.album)
                    .font(.system(size: 13, weight: .bold)).lineLimit(1)
                Text(record.artist)
                    .font(.system(size: 11)).lineLimit(1).opacity(0.80)
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardGrad()).foregroundStyle(.white)
        }
        // Year + genre badges — top left
        .overlay(alignment: .topLeading) {
            HStack(spacing: 4) {
                if !record.year.isEmpty {
                    Text(record.year)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.black.opacity(0.60))
                        .clipShape(Capsule())
                }
                if !record.genre.isEmpty {
                    Text(record.genre)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(settings.accentColor.opacity(0.85))
                        .clipShape(Capsule())
                }
            }
            .padding(8)
        }
        // Info icon — top right → opens detail
        .overlay(alignment: .topTrailing) {
            Button { onInfo() } label: {
                ZStack {
                    Circle().fill(Color.black.opacity(0.40)).frame(width: 28, height: 28)
                    Image(systemName: "opticaldisc")
                        .font(.system(size: 12)).foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .padding(8)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var back: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(record.artist)
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.textP).lineLimit(1)
                    Text(record.album)
                        .font(.system(size: 11)).foregroundStyle(Theme.textS).lineLimit(1)
                        .padding(.top, 2)
                    Rectangle().fill(Theme.divide).frame(height: 1).padding(.vertical, 8)
                    VStack(alignment: .leading, spacing: 5) {
                        if !record.year.isEmpty    { infoRow("Year",    record.year)    }
                        if !record.genre.isEmpty   { infoRow("Genre",   record.genre)   }
                        if !record.label.isEmpty   { infoRow("Label",   record.label)   }
                        if !record.format.isEmpty  { infoRow("Format",  record.format)  }
                        if !record.country.isEmpty { infoRow("Country", record.country) }
                        if !record.notes.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("NOTES")
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Theme.textT)
                                Text(record.notes)
                                    .font(.system(size: 11)).foregroundStyle(Theme.textS).lineLimit(4)
                            }
                        }
                    }
                }
                .padding(12)
            }

            Rectangle().fill(Theme.divide).frame(height: 1)
            HStack(spacing: 0) {
                actionBtn("pencil",  color: settings.accentColor) { onEdit() }
                Rectangle().fill(Theme.divide).frame(width: 1).frame(maxHeight: .infinity)
                actionBtn(record.isWishlist ? "square.stack.3d.up" : "heart", color: Theme.textS) { onMove() }
                Rectangle().fill(Theme.divide).frame(width: 1).frame(maxHeight: .infinity)
                actionBtn("trash",   color: .red) { onDelete() }
            }
            .frame(height: 44)
        }
        .background(Theme.bg2)
        .aspectRatio(1, contentMode: .fit)
    }

    private func infoRow(_ key: String, _ val: String) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(key.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textT).frame(width: 50, alignment: .leading)
            Text(val).font(.system(size: 11)).foregroundStyle(Theme.textS).lineLimit(1)
        }
    }

    private func actionBtn(_ icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(color)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
    }
}

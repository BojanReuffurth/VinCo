import SwiftUI

struct CardView: View {
    let record: Record
    var onInfo:   () -> Void = {}
    var onEdit:   () -> Void = {}
    var onMove:   () -> Void = {}
    var onDelete: () -> Void = {}
    @Environment(Settings.self) private var settings

    var body: some View {
        front
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardR))
            .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 4)
            // Tapping anywhere on the card opens the detail sheet
            .onTapGesture { onInfo() }
    }

    // MARK: – Front face
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

            // Bottom gradient: album bold first, then artist
            VStack(alignment: .leading, spacing: 2) {
                Text(record.album)
                    .font(.system(size: 13, weight: .bold)).lineLimit(1)
                Text(record.artist)
                    .font(.system(size: 11)).lineLimit(1).opacity(0.80)
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardGrad()).foregroundStyle(.white)
        }
        // Year + genre badges – top left
        .overlay(alignment: .topLeading) {
            HStack(spacing: 4) {
                if !record.year.isEmpty {
                    Text(record.year)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.black.opacity(0.60))
                        .clipShape(Capsule())
                }
                if !record.genre.isEmpty {
                    Text(record.genre)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(settings.accentColor.opacity(0.85))
                        .clipShape(Capsule())
                }
            }
            .padding(8)
        }
        // Condition badge + edit shortcut – top right
        .overlay(alignment: .topTrailing) {
            VStack(alignment: .trailing, spacing: 4) {
                if !record.condition.isEmpty {
                    Text(record.condition)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 3)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Capsule())
                }
            }
            .padding(8)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

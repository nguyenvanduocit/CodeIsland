import SwiftUI

// MARK: - App Logo

struct AppLogoView: View {
    var size: CGFloat = 100
    var showBackground: Bool = true
    private let orange = Color(red: 0.96, green: 0.65, blue: 0.14)

    var body: some View {
        Canvas { ctx, sz in
            // macOS icon standard: ~10% padding on each side
            let inset = sz.width * 0.1
            let contentRect = CGRect(x: inset, y: inset, width: sz.width - inset * 2, height: sz.height - inset * 2)
            let px = contentRect.width / 16
            if showBackground {
                let bgPath = Path(roundedRect: contentRect, cornerRadius: contentRect.width * 0.22, style: .continuous)
                ctx.fill(bgPath, with: .color(.white))
            }
            // Notch pill
            let pillColor = showBackground ? Color(white: 0.1) : Color(white: 0.5)
            let pillRect = CGRect(x: contentRect.minX + px * 3, y: contentRect.minY + px * 6, width: px * 10, height: px * 4)
            ctx.fill(Path(roundedRect: pillRect, cornerRadius: px * 2, style: .continuous), with: .color(pillColor))
            // Eyes
            ctx.fill(Path(CGRect(x: contentRect.minX + px * 5, y: contentRect.minY + px * 7, width: px * 2, height: px * 2)), with: .color(orange))
            ctx.fill(Path(CGRect(x: contentRect.minX + px * 9, y: contentRect.minY + px * 7, width: px * 2, height: px * 2)), with: .color(orange))
            // Pupils
            ctx.fill(Path(CGRect(x: contentRect.minX + px * 6, y: contentRect.minY + px * 7, width: px, height: px)), with: .color(.white))
            ctx.fill(Path(CGRect(x: contentRect.minX + px * 10, y: contentRect.minY + px * 7, width: px, height: px)), with: .color(.white))
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(showBackground ? 0.15 : 0), radius: size * 0.12, y: size * 0.04)
    }
}

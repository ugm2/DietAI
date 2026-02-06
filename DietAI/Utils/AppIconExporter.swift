import SwiftUI

// MARK: - App Icon Exporter
/// Utility to export app icons as PNG images
/// Usage: Call AppIconExporter.exportIcons() from a button or debug menu
@MainActor
struct AppIconExporter {

    /// Export all app icon variants to the Documents directory
    static func exportIcons() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!

        print("")
        print("🎨 ========== APP ICON EXPORT ==========")
        print("")

        // Export light mode icon (1024x1024)
        if let lightIcon = renderIcon(AppIconView(size: 1024), size: 1024) {
            let lightURL = documentsPath.appendingPathComponent("AppIcon-Light-1024.png")
            saveImage(lightIcon, to: lightURL)
            print("✅ Light icon: AppIcon-Light-1024.png")
        }

        // Export dark mode icon (1024x1024)
        if let darkIcon = renderIcon(AppIconDarkView(size: 1024), size: 1024) {
            let darkURL = documentsPath.appendingPathComponent("AppIcon-Dark-1024.png")
            saveImage(darkIcon, to: darkURL)
            print("✅ Dark icon: AppIcon-Dark-1024.png")
        }

        // Export tinted icon (same as dark for now)
        if let tintedIcon = renderIcon(AppIconDarkView(size: 1024), size: 1024) {
            let tintedURL = documentsPath.appendingPathComponent("AppIcon-Tinted-1024.png")
            saveImage(tintedIcon, to: tintedURL)
            print("✅ Tinted icon: AppIcon-Tinted-1024.png")
        }

        print("")
        print("📁 LOCATION: \(documentsPath.path)")
        print("")
        print("📋 TO ADD ICONS TO YOUR APP:")
        print("   1. Open Finder and press Cmd+Shift+G")
        print("   2. Paste the path above")
        print("   3. Drag the PNG files into Xcode's Assets.xcassets/AppIcon.appiconset")
        print("")
        print("🎨 =====================================")
        print("")
    }

    /// Render a SwiftUI view to UIImage
    private static func renderIcon<V: View>(_ view: V, size: CGFloat) -> UIImage? {
        let renderer = ImageRenderer(content: view.frame(width: size, height: size))
        renderer.scale = 1.0 // We want exact pixel size
        return renderer.uiImage
    }

    /// Save UIImage as PNG to disk
    private static func saveImage(_ image: UIImage, to url: URL) {
        guard let data = image.pngData() else {
            print("❌ Failed to create PNG data")
            return
        }
        do {
            try data.write(to: url)
        } catch {
            print("❌ Failed to save image: \(error)")
        }
    }
}

// MARK: - Debug View for Icon Export
#if DEBUG
struct IconExportView: View {
    @State private var exported = false
    @State private var exportPath = ""

    var body: some View {
        VStack(spacing: 24) {
            Text("App Icon Preview")
                .font(.headline)

            HStack(spacing: 20) {
                VStack {
                    AppIconView(size: 120)
                    Text("Light")
                        .font(.caption)
                }

                VStack {
                    AppIconDarkView(size: 120)
                    Text("Dark")
                        .font(.caption)
                }
            }

            Button {
                AppIconExporter.exportIcons()
                exportPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? ""
                exported = true
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.down")
                    Text("Export Icons (1024x1024)")
                }
                .padding()
                .background(Color.blue)
                .foregroundStyle(.white)
                .cornerRadius(10)
            }

            if exported {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title)

                    Text("Icons exported!")
                        .font(.subheadline)

                    Text(exportPath)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            Text("After exporting, use Finder to navigate to the app's Documents folder and drag the icons into Xcode's Asset Catalog.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
        }
        .padding()
    }
}

#Preview("Icon Export") {
    IconExportView()
}
#endif

import SwiftUI
import AppKit

/// Brand identity: the Conetxo mark, the About panel, and the shared brand strings.
/// The logo ships as a white rounded plate (Resources/BrandLogo*.png) because the source
/// artwork has an opaque light background and light inner seams — cutting the background
/// out would break the mark apart on dark themes.
enum Brand {
    static let appName = "Conetxo Listener"
    static let company = "Conetxo Solutions"
    static let website = "https://www.conetxosolutions.com"
    static let tagline = "Transcripción de voz 100% en tu Mac"

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
            ?? "© 2026 \(company)"
    }

    /// Bundled logo; nil only if the Resources copy step was skipped in build.sh.
    static let logo: NSImage? = {
        guard let url = Bundle.main.url(forResource: "BrandLogo", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()
}

/// The Conetxo mark at a given point size, with a graceful fallback so a missing
/// resource degrades to the mic glyph instead of leaving a hole in the layout.
struct BrandLogo: View {
    let size: CGFloat

    var body: some View {
        Group {
            if let logo = Brand.logo {
                Image(nsImage: logo).resizable().interpolation(.high)
            } else {
                Image(systemName: "mic.fill").resizable().scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225))
    }
}

// MARK: - About panel

struct AboutView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @Environment(\.colorScheme) private var systemColorScheme

    private var isDark: Bool {
        settings.theme == "system" ? systemColorScheme == .dark : settings.theme == "dark"
    }

    var body: some View {
        VStack(spacing: 0) {
            BrandLogo(size: 78)
                .padding(.bottom, 12)

            Text(Brand.appName)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Color.themeAccent(isDark: isDark))

            Text("Versión \(Brand.version) · \(Brand.tagline)")
                .font(.system(size: 12))
                .foregroundColor(Color.themeSubtext(isDark: isDark))
                .multilineTextAlignment(.center)
                .padding(.top, 3)

            Divider()
                .background(Color.themeSurface(isDark: isDark))
                .padding(.vertical, 16)

            Text("DEVELOPED BY")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundColor(Color.themeSubtext(isDark: isDark))

            Text(Brand.company)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color.themeAccent(isDark: isDark))
                .padding(.top, 4)

            Button(action: {
                if let url = URL(string: Brand.website) { NSWorkspace.shared.open(url) }
            }) {
                Text("conetxosolutions.com")
                    .font(.system(size: 12))
                    .underline()
                    .foregroundColor(Color.themeAccent(isDark: isDark))
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.top, 9)

            Text(Brand.copyright)
                .font(.system(size: 10.5))
                .foregroundColor(Color.themeSubtext(isDark: isDark).opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.top, 16)

            // Franja con los colores del logo.
            LinearGradient(
                colors: [Color(hex: "00516B"), Color(hex: "0077A3"), Color(hex: "00AEEF"),
                         Color(hex: "2E8B37"), Color(hex: "FF7A00"), Color(hex: "B0004D")],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: 120, height: 3)
            .cornerRadius(2)
            .padding(.top, 18)
        }
        .padding(EdgeInsets(top: 26, leading: 22, bottom: 20, trailing: 22))
        .frame(width: 340)
        .background(Color.themeCard(isDark: isDark))
        .preferredColorScheme(settings.theme == "system" ? nil : (settings.theme == "dark" ? .dark : .light))
    }
}

/// Single reusable About window — reopening brings the existing one forward
/// instead of stacking duplicates.
final class AboutWindowController {
    static let shared = AboutWindowController()
    private var window: NSWindow?

    func show() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: AboutView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Acerca de \(Brand.appName)"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

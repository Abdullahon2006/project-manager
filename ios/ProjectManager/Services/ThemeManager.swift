import SwiftUI
import Combine

public struct WallpaperPreset: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let urlString: String
    public let thumbnail: String
    
    public init(id: String, name: String, urlString: String, thumbnail: String) {
        self.id = id
        self.name = name
        self.urlString = urlString
        self.thumbnail = thumbnail
    }
}

public class ThemeManager: ObservableObject {
    public static let shared = ThemeManager()
    
    public static let presets: [WallpaperPreset] = [
        WallpaperPreset(
            id: "alpine",
            name: "Alpine Peaks",
            urlString: "https://images.unsplash.com/photo-1506744038136-46273834b3fb?auto=format&fit=crop&w=1920&q=80",
            thumbnail: "🏔️"
        ),
        WallpaperPreset(
            id: "sunset",
            name: "Golden Sunset",
            urlString: "https://images.unsplash.com/photo-1495616811223-4d98c6e9c869?auto=format&fit=crop&w=1920&q=80",
            thumbnail: "🌅"
        ),
        WallpaperPreset(
            id: "forest",
            name: "Emerald Forest",
            urlString: "https://images.unsplash.com/photo-1448375240586-882707db888b?auto=format&fit=crop&w=1920&q=80",
            thumbnail: "🌲"
        ),
        WallpaperPreset(
            id: "cyberpunk",
            name: "Midnight City",
            urlString: "https://images.unsplash.com/photo-1519501025264-65ba15a82390?auto=format&fit=crop&w=1920&q=80",
            thumbnail: "🌃"
        ),
        WallpaperPreset(
            id: "minimal",
            name: "Architectural Minimal",
            urlString: "https://images.unsplash.com/photo-1600585154340-be6161a56a0c?auto=format&fit=crop&w=1920&q=80",
            thumbnail: "🏛️"
        )
    ]
    
    @Published public var selectedWallpaperId: String {
        didSet { UserDefaults.standard.set(selectedWallpaperId, forKey: "pm_selected_wallpaper_id") }
    }
    
    @Published public var customWallpaperUrl: String {
        didSet { UserDefaults.standard.set(customWallpaperUrl, forKey: "pm_custom_wallpaper_url") }
    }
    
    @Published public var appearanceMode: String {
        didSet { UserDefaults.standard.set(appearanceMode, forKey: "pm_appearance_mode") }
    }
    
    @Published public var wallpaperDimming: Double {
        didSet { UserDefaults.standard.set(wallpaperDimming, forKey: "pm_wallpaper_dimming") }
    }
    
    public init() {
        self.selectedWallpaperId = UserDefaults.standard.string(forKey: "pm_selected_wallpaper_id") ?? "alpine"
        self.customWallpaperUrl = UserDefaults.standard.string(forKey: "pm_custom_wallpaper_url") ?? ""
        self.appearanceMode = UserDefaults.standard.string(forKey: "pm_appearance_mode") ?? "system"
        self.wallpaperDimming = UserDefaults.standard.object(forKey: "pm_wallpaper_dimming") as? Double ?? 0.25
    }
    
    public var activeWallpaperURL: URL? {
        if selectedWallpaperId == "custom" {
            let trimmed = customWallpaperUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            return URL(string: trimmed)
        }
        if selectedWallpaperId == "none" {
            return nil
        }
        if let preset = Self.presets.first(where: { $0.id == selectedWallpaperId }) {
            return URL(string: preset.urlString)
        }
        return nil
    }
    
    public var preferredColorScheme: ColorScheme? {
        switch appearanceMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}

// MARK: - App Wallpaper Background Modifier
public struct AppWallpaperBackground: ViewModifier {
    @ObservedObject private var theme = ThemeManager.shared
    
    public func body(content: Content) -> some View {
        content
            .background {
                wallpaperView
            }
    }

    @ViewBuilder
    private var wallpaperView: some View {
        if let url = theme.activeWallpaperURL {
            GeometryReader { geo in
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    case .empty:
                        Color.black.opacity(0.85)
                    default:
                        Color(.systemGroupedBackground)
                    }
                }
                .overlay(
                    Color.black.opacity(theme.wallpaperDimming)
                )
            }
            .ignoresSafeArea()
        } else {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
        }
    }
}

public extension View {
    func withAppWallpaper() -> some View {
        modifier(AppWallpaperBackground())
    }
}

// MARK: - Color Hex Initializer
public extension Color {
    init(hex: String) {
        let cleanHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleanHex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch cleanHex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 59, 130, 246)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

import SwiftUI

@main
struct VnuaConnectApp: App {
    @State private var app: AppState

    init() {
        FontRegistrar.registerBundledFonts()
        FontRegistrar.applyAppearance()
        // Real backend when VnuaConnect/Config/Supabase.plist exists; otherwise the offline demo.
        var api: any VnuaAPI = SupabaseConfig.load().map { SupabaseAPI(config: $0) } ?? MockAPI()
        #if DEBUG
        // `-mock` (Scheme → Arguments) forces the offline demo even when Supabase is configured.
        if ProcessInfo.processInfo.arguments.contains("-mock") { api = MockAPI() }
        #endif
        _app = State(initialValue: AppState(api: api))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .onOpenURL { url in Task { await app.handleOpenURL(url) } }
                .tint(Palette.accent)
        }
    }
}

/// Light/dark choice. `.automatic` follows the phone's Settings → Display & Brightness.
enum Appearance: String, CaseIterable, Identifiable {
    case automatic, light, dark
    var id: String { rawValue }
    var label: String { switch self { case .automatic: "Automatic"; case .light: "Light"; case .dark: "Dark" } }
    var colorScheme: ColorScheme? { switch self { case .automatic: nil; case .light: .light; case .dark: .dark } }
}

struct RootView: View {
    @Environment(AppState.self) private var app
    @AppStorage("appearance") private var appearance: Appearance = .automatic

    var body: some View {
        Group {
            if app.isRestoring {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.background)
            } else if app.user == nil {
                SignInView()
            } else {
                MainTabView()
            }
        }
        .overlay(alignment: .top) {
            if let banner = app.banner {
                BannerView(banner: banner)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 4)
            }
        }
        .preferredColorScheme(appearance.colorScheme)
        .animation(.snappy, value: app.banner)
        .animation(.default, value: app.user == nil)
        .task {
            await app.restore()
            #if DEBUG
            // Launch with `-demoSignIn` (Scheme → Arguments) to skip sign-in in the offline demo.
            guard ProcessInfo.processInfo.arguments.contains("-demoSignIn"), app.isDemo, app.user == nil else { return }
            if let u = try? await app.api.verify(email: "alex@pride.hofstra.edu", name: "Alex Rivera",
                                                 code: "123456", campus: app.campus) {
                await app.signedIn(u)
            }
            #endif
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            DiscoverView()
                .tabItem { Label("Discover", systemImage: "sparkle.magnifyingglass") }
            EventsView()
                .tabItem { Label("Events", systemImage: "calendar") }
            MyClubsView()
                .tabItem { Label("My Clubs", systemImage: "person.3") }
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
    }
}

/// Shared navigation destinations so any stack can push a club or an event.
extension View {
    func vnuaDestinations() -> some View {
        self
            .navigationDestination(for: Club.self) { ClubDetailView(club: $0) }
            .navigationDestination(for: ClubEvent.self) { EventDetailView(event: $0) }
    }
}

extension Date {
    var vnuaDay: String { formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) }
    var vnuaTime: String { formatted(.dateTime.hour().minute()) }
    var vnuaFull: String { formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()) }
}

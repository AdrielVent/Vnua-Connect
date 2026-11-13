import SwiftUI

@main
struct VnuaConnectApp: App {
    @State private var app: AppState

    init() {
        FontRegistrar.registerBundledFonts()
        FontRegistrar.applyAppearance()
        // Swap MockAPI() for SupabaseAPI(...) once the backend exists. Nothing else changes.
        _app = State(initialValue: AppState(api: MockAPI()))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .tint(Palette.accent)
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        Group {
            if app.user == nil {
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
        .animation(.snappy, value: app.banner)
        .animation(.default, value: app.user == nil)
        #if DEBUG
        // Launch with `-demoSignIn` (Scheme → Arguments) to skip sign-in during development.
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-demoSignIn"), app.user == nil else { return }
            if let u = try? await app.api.verify(email: "alex@pride.hofstra.edu", name: "Alex Rivera",
                                                 code: "123456", campus: app.campus) {
                await app.signedIn(u)
            }
        }
        #endif
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

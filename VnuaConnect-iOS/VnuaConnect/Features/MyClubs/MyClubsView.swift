import SwiftUI

struct MyClubsView: View {
    @Environment(AppState.self) private var app
    @State private var startingClub = false

    private func clubs(where match: (Membership) -> Bool) -> [Club] {
        app.visibleClubs.filter { app.membership($0.id).map(match) ?? false }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    let leading = clubs { $0.role == .officer && $0.status == .active }
                    let member = clubs { $0.role != .officer && $0.status == .active }
                    let pending = clubs { $0.status == .pending }

                    if leading.isEmpty && member.isEmpty && pending.isEmpty {
                        ContentUnavailableView {
                            Label("No clubs yet", systemImage: "person.3")
                        } description: {
                            Text("Find a club in Discover and join, or help found one.")
                        } actions: {
                            Button("Start a club") { startingClub = true }.buttonStyle(.vnuaPrimary).frame(maxWidth: 240)
                        }
                        .padding(.top, 60)
                    }
                    group("Clubs you lead", leading)
                    group("Member", member)
                    group("Waiting for approval", pending)
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 24)
            }
            .background(Palette.background)
            .navigationTitle("My Clubs")
            .toolbar {
                Button { startingClub = true } label: { Label("Start a club", systemImage: "plus") }
            }
            .sheet(isPresented: $startingClub) { StartClubSheet() }
            .refreshable { await app.refresh() }
            .vnuaDestinations()
        }
    }

    @ViewBuilder private func group(_ title: String, _ list: [Club]) -> some View {
        if !list.isEmpty {
            SectionHeader(title: title)
            ForEach(list) { c in
                NavigationLink(value: c) { ClubRow(club: c) }.buttonStyle(.plain)
            }
        }
    }
}

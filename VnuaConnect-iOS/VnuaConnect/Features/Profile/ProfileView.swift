import SwiftUI

struct ProfileView: View {
    @Environment(AppState.self) private var app
    @State private var involvement: [AttendanceRecord] = []
    @State private var confirmDelete = false
    @AppStorage("appearance") private var appearance: Appearance = .automatic

    var body: some View {
        NavigationStack {
            List {
                if let u = app.user {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(u.name).font(VnuaFont.font(.title2, .bold))
                            Text(u.email).font(VnuaFont.font(.subheadline)).foregroundStyle(Palette.secondaryText)
                            Text(app.campus.name).font(VnuaFont.font(.footnote)).foregroundStyle(Palette.secondaryText)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    LabeledContent("Events attended", value: "\(involvement.count)")
                    LabeledContent("Clubs", value: "\(app.memberships.values.filter { $0.status == .active }.count)")
                    ForEach(involvement) { r in
                        let e = app.events.first { $0.id == r.eventId }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e?.title ?? "Event").font(VnuaFont.font(.subheadline, .medium))
                            Text(r.recordedAt.vnuaDay).font(VnuaFont.font(.footnote)).foregroundStyle(Palette.secondaryText)
                        }
                    }
                } header: {
                    Text("Involvement record")
                } footer: {
                    Text("Your check-ins, kept so you can show what you've been part of.")
                }

                if !app.blockedClubIds.isEmpty {
                    Section("Blocked clubs") {
                        ForEach(app.clubs.filter { app.blockedClubIds.contains($0.id) }) { c in
                            HStack {
                                Text(c.name)
                                Spacer()
                                Button("Unblock") { Task { await app.setBlocked(c, false) } }
                            }
                        }
                    }
                }

                Section {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Automatic follows your iPhone's light/dark setting.")
                }

                Section("About") {
                    Text("Vnua-connect is student-run. It is not affiliated with or endorsed by \(app.campus.name).")
                    Text("Being listed here is not official university recognition. To run the service and see whether it's working, Vnua-connect's founder can see activity across all clubs: who joined which clubs, check-ins, RSVPs and when people last signed in. It is never sold or shared.")
                        .font(VnuaFont.font(.footnote)).foregroundStyle(Palette.secondaryText)
                }

                Section("Help") {
                    Link("Contact support", destination: URL(string: "mailto:support@vnuaconnect.example")!)
                    Link("Privacy policy", destination: URL(string: "https://adrielvent.github.io/Vnua-Connect/")!)
                    LabeledContent("Font", value: FontRegistrar.summary)
                }

                Section {
                    Button("Sign out") { Task { await app.signOut() } }
                    Button("Delete account", role: .destructive) { confirmDelete = true }
                }
            }
            .font(VnuaFont.font(.body))
            .navigationTitle("Profile")
            .task { await loadInvolvement() }
            .refreshable { await loadInvolvement() }
            .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete account", role: .destructive) { Task { await app.deleteAccount() } }
            } message: {
                Text("This removes your profile, memberships and RSVPs. It can't be undone.")
            }
        }
    }

    private func loadInvolvement() async {
        if let r = await app.run({ try await app.api.involvement() }) { involvement = r }
    }
}

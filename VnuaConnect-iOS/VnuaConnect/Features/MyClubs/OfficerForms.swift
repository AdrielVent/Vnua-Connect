import SwiftUI

/// "Help found one": start a new club. It stays hidden from other students until a moderator reviews it.
struct StartClubSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ClubDraft()
    @State private var busy = false

    private var valid: Bool { draft.name.trimmingCharacters(in: .whitespaces).count >= 2 && !draft.blurb.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Text(draft.monogram)
                            .font(VnuaFont.fixed(size: 20, .bold)).foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(Color(hex: draft.accentHex), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .accessibilityHidden(true)
                        TextField("Club name", text: $draft.name).font(VnuaFont.font(.headline, .medium))
                    }
                    TextField("One line about the club", text: $draft.blurb)
                        .onChange(of: draft.blurb) { _, v in if v.count > 160 { draft.blurb = String(v.prefix(160)) } }
                    Picker("Interest", selection: $draft.interest) {
                        ForEach(ClubDraft.interests, id: \.self) { Text($0) }
                    }
                }
                Section("Color") {
                    HStack(spacing: 12) {
                        ForEach(ClubDraft.accents, id: \.0) { hex, name in
                            Button { draft.accentHex = hex } label: {
                                Circle().fill(Color(hex: hex)).frame(width: 34, height: 34)
                                    .overlay(Circle().strokeBorder(Palette.text, lineWidth: draft.accentHex == hex ? 3 : 0))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(name)
                            .accessibilityAddTraits(draft.accentHex == hex ? .isSelected : [])
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Section("About") {
                    TextField("What you do, who it's for, how often you meet", text: $draft.about, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section {
                    Toggle("Officers approve new members", isOn: $draft.requiresApproval)
                } footer: {
                    Text("You'll be the club's first officer. Other students see it after a quick review, usually within a day.")
                }
            }
            .navigationTitle("Start a club")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        busy = true
                        Task {
                            defer { busy = false }
                            if await app.run({ try await app.api.createClub(draft) }) != nil {
                                await app.refresh()
                                app.show("\(draft.name) created. It's waiting for review.")
                                dismiss()
                            }
                        }
                    }
                    .disabled(!valid || busy)
                }
            }
        }
    }
}

/// Officers schedule an event for their club.
struct NewEventSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let club: Club
    @State private var draft: EventDraft
    @State private var coHosts: Set<String> = []
    @State private var busy = false
    @State private var requestId = UUID().uuidString     // same id across retries → no duplicate events

    init(club: Club) {
        self.club = club
        var d = EventDraft(hostClubIds: [club.id])
        let cal = Calendar.current
        d.start = cal.date(bySettingHour: 18, minute: 0, second: 0,
                           of: cal.date(byAdding: .day, value: 1, to: .now)!) ?? d.start
        _draft = State(initialValue: d)
    }

    /// Other clubs you also run, which can co-host (joint events count each person once).
    private var otherClubsYouRun: [Club] {
        app.clubs.filter { $0.id != club.id && app.isOfficer(of: $0.id) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Event title", text: $draft.title).font(VnuaFont.font(.headline, .medium))
                    DatePicker("Starts", selection: $draft.start, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                    Picker("Length", selection: $draft.durationMinutes) {
                        ForEach([30, 45, 60, 90, 120, 180, 240], id: \.self) { m in
                            Text(m < 60 ? "\(m) min" : m % 60 == 0 ? "\(m / 60) hr" : "\(m / 60) hr \(m % 60) min").tag(m)
                        }
                    }
                    TextField("Where", text: $draft.location)
                }
                Section("Details") {
                    TextField("What to expect, what to bring", text: $draft.details, axis: .vertical).lineLimit(3...8)
                }
                if !otherClubsYouRun.isEmpty {
                    Section {
                        ForEach(otherClubsYouRun) { c in
                            Toggle(c.name, isOn: Binding(
                                get: { coHosts.contains(c.id) },
                                set: { on in if on { coHosts.insert(c.id) } else { coHosts.remove(c.id) } }))
                        }
                    } header: { Text("Co-host with") } footer: {
                        Text("Joint events show up for both clubs. Each person is counted once.")
                    }
                }
            }
            .navigationTitle(club.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") {
                        busy = true
                        var d = draft
                        d.hostClubIds = [club.id] + coHosts.sorted()
                        Task {
                            defer { busy = false }
                            if await app.run({ try await app.api.createEvent(d, requestId: requestId) }) != nil {
                                await app.refresh()
                                app.show("Event posted")
                                dismiss()
                            }
                        }
                    }
                    .disabled(draft.title.trimmingCharacters(in: .whitespaces).count < 2 || busy)
                }
            }
        }
    }
}

import SwiftUI

struct ClubDetailView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let club: Club
    @State private var showJoin = false
    @State private var showReport = false
    @State private var confirmLeave = false
    @State private var confirmBlock = false

    private var membership: Membership? { app.membership(club.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                membershipCard
                aboutCard
                if !club.officers.isEmpty { officersCard }
                eventsSection
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 32)
        }
        .background(Palette.background)
        .navigationTitle(club.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                ShareLink(item: "Check out \(club.name) on Vnua-connect")
                Button("Report club", systemImage: "flag") { showReport = true }
                Button("Block club", systemImage: "hand.raised", role: .destructive) { confirmBlock = true }
            } label: {
                Image(systemName: "ellipsis.circle").accessibilityLabel("More")
            }
        }
        .sheet(isPresented: $showJoin) { JoinSheet(club: club) }
        .sheet(isPresented: $showReport) { ReportSheet(targetId: club.id, targetName: club.name) }
        .confirmationDialog("Leave \(club.name)?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave club", role: .destructive) { Task { await app.leave(club) } }
        }
        .confirmationDialog("Block \(club.name)?", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("Block", role: .destructive) { app.block(club); dismiss() }
        } message: {
            Text("You won't see this club or its events. You can undo this in Profile.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            ClubMonogram(club: club, size: 72)
            Text(club.name).font(VnuaFont.font(.title, .bold))
            Text(club.blurb).font(VnuaFont.font(.body)).foregroundStyle(Palette.secondaryText)
            FlowBadges(club: club)
        }
        .padding(.top, 8)
    }

    @ViewBuilder private var membershipCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let m = membership {
                if m.status == .pending {
                    Label("Join request sent. An officer will review it.", systemImage: "clock")
                        .font(VnuaFont.font(.subheadline, .medium)).foregroundStyle(Palette.warning)
                } else {
                    Label("You're a \(m.role.label.lowercased())", systemImage: "checkmark.seal.fill")
                        .font(VnuaFont.font(.headline, .medium)).foregroundStyle(Palette.success)
                }
                Picker("Emails from this club", selection: Binding(
                    get: { m.contact },
                    set: { new in Task { await app.updateContact(club, new) } })) {
                    ForEach(ContactPreference.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
                .font(VnuaFont.font(.subheadline))
                Button(m.status == .pending ? "Cancel request" : "Leave club", role: .destructive) { confirmLeave = true }
                    .font(VnuaFont.font(.subheadline, .medium))
            } else {
                Button(club.requiresApproval ? "Request to join" : "Join club") { showJoin = true }
                    .buttonStyle(.vnuaPrimary)
                if club.requiresApproval {
                    Text("Officers approve new members for this club.")
                        .font(VnuaFont.font(.footnote)).foregroundStyle(Palette.secondaryText)
                }
            }
        }
        .card()
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "About")
            Text(club.about).font(VnuaFont.font(.body))
            if let a = club.affiliation {
                Label(a, systemImage: "link").font(VnuaFont.font(.footnote)).foregroundStyle(Palette.secondaryText)
            }
        }
        .card()
    }

    private var officersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Officers")
            ForEach(club.officers, id: \.name) { o in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(o.name) · \(o.title)").font(VnuaFont.font(.subheadline, .medium))
                    Text("Ask about: \(o.askAbout)").font(VnuaFont.font(.footnote)).foregroundStyle(Palette.secondaryText)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Events")
            let list = app.events(for: club.id)
            if list.isEmpty {
                Text("No upcoming events").font(VnuaFont.font(.subheadline)).foregroundStyle(Palette.secondaryText)
            }
            ForEach(list) { e in
                NavigationLink(value: e) { EventRow(event: e) }.buttonStyle(.plain)
            }
        }
    }
}

struct FlowBadges: View {
    let club: Club
    var body: some View {
        HStack(spacing: 6) {
            Badge(text: club.interest)
            Badge(text: club.recognition.label,
                  systemImage: club.recognition == .recognized ? "checkmark.seal" : nil,
                  tone: club.recognition == .recognized ? .success : .neutral)
            if club.funded == true { Badge(text: "Funded", tone: .accent) }
        }
    }
}

struct JoinSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let club: Club
    @State private var role: MemberRole = .member
    @State private var contact: ContactPreference = .events
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("How do you want to join?", selection: $role) {
                        Text("Member").tag(MemberRole.member)
                        Text("Founding member").tag(MemberRole.founding)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: { Text("Join as") } footer: {
                    Text(club.recognition == .recognized
                         ? "Founding members help run the club day to day."
                         : "Founding members count toward the number of students a club needs to apply for recognition.")
                }
                Section("Emails from \(club.name)") {
                    Picker("Emails", selection: $contact) {
                        ForEach(ContactPreference.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .font(VnuaFont.font(.body))
            .navigationTitle(club.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(club.requiresApproval ? "Request" : "Join") {
                        busy = true
                        Task { await app.join(club, role: role, contact: contact); busy = false; dismiss() }
                    }
                    .disabled(busy)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct ReportSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let targetId: String
    let targetName: String
    @State private var reason: ReportReason?
    @State private var detail = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("What's wrong with \(targetName)?") {
                    Picker("Reason", selection: $reason) {
                        ForEach(ReportReason.allCases) { Text($0.rawValue).tag(Optional($0)) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("Details (optional)") {
                    TextField("Anything that helps a moderator", text: $detail, axis: .vertical).lineLimit(3...6)
                }
            }
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        guard let reason else { return }
                        Task {
                            if await app.run({ try await app.api.report(targetId: targetId, reason: reason, detail: detail) }) != nil {
                                app.show("Report sent. A moderator will review it.")
                                dismiss()
                            }
                        }
                    }
                    .disabled(reason == nil)
                }
            }
        }
    }
}

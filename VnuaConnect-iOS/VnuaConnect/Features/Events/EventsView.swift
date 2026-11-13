import SwiftUI
import EventKit

struct EventsView: View {
    @Environment(AppState.self) private var app
    @State private var scope: Scope = .all
    enum Scope: String, CaseIterable { case all = "All events", mine = "My clubs", going = "Going" }

    private var filtered: [ClubEvent] {
        app.visibleEvents.filter { e in
            switch scope {
            case .all: return true
            case .mine: return e.hostClubIds.contains { app.membership($0)?.status == .active }
            case .going: return app.rsvps.contains(e.id)
            }
        }
    }

    private var byDay: [(Date, [ClubEvent])] {
        let groups = Dictionary(grouping: filtered) { Calendar.current.startOfDay(for: $0.start) }
        return groups.keys.sorted().map { ($0, groups[$0]!.sorted { $0.start < $1.start }) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16, pinnedViews: []) {
                    Picker("Show", selection: $scope) {
                        ForEach(Scope.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)

                    if byDay.isEmpty {
                        ContentUnavailableView("No events", systemImage: "calendar",
                                               description: Text("Join a club or RSVP to see events here."))
                    }
                    ForEach(byDay, id: \.0) { day, events in
                        SectionHeader(title: Calendar.current.isDateInToday(day) ? "Today" : day.vnuaDay)
                        ForEach(events) { e in
                            NavigationLink(value: e) { EventRow(event: e) }.buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 24)
            }
            .background(Palette.background)
            .navigationTitle("Events")
            .refreshable { await app.refresh() }
            .vnuaDestinations()
        }
    }
}

struct EventRow: View {
    @Environment(AppState.self) private var app
    let event: ClubEvent

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Text(event.start.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(VnuaFont.font(.caption2, .medium)).foregroundStyle(Palette.accent)
                Text(event.start.formatted(.dateTime.day()))
                    .font(VnuaFont.font(.title2, .bold))
            }
            .frame(width: 48, height: 56)
            .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title).font(VnuaFont.font(.headline, .bold))
                    .strikethrough(event.status == .cancelled)
                Text("\(event.start.vnuaTime) · \(event.location)")
                    .font(VnuaFont.font(.subheadline)).foregroundStyle(Palette.secondaryText)
                Text(app.hostNames(event)).font(VnuaFont.font(.footnote)).foregroundStyle(Palette.secondaryText)
                HStack(spacing: 6) {
                    EventStatusBadge(event: event)
                    if app.rsvps.contains(event.id) { Badge(text: "Going", systemImage: "checkmark", tone: .success) }
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Palette.text)
        .card()
        .accessibilityElement(children: .combine)
    }
}

struct EventStatusBadge: View {
    let event: ClubEvent
    var body: some View {
        switch event.status {
        case .scheduled: EmptyView()
        case .rescheduled: Badge(text: "Rescheduled", systemImage: "arrow.triangle.2.circlepath", tone: .warning)
        case .cancelled: Badge(text: "Cancelled", systemImage: "xmark", tone: .warning)
        }
    }
}

struct EventDetailView: View {
    @Environment(AppState.self) private var app
    let event: ClubEvent
    @State private var showReport = false
    @State private var confirmCancel = false
    @Environment(\.dismiss) private var dismiss

    private var going: Bool { app.rsvps.contains(event.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    EventStatusBadge(event: event)
                    Text(event.title).font(VnuaFont.font(.title, .bold))
                    Text(app.hostNames(event)).font(VnuaFont.font(.subheadline, .medium)).foregroundStyle(Palette.accent)
                }
                .padding(.top, 8)

                if event.status == .rescheduled, let was = event.previousStart {
                    Label("Moved from \(was.vnuaFull)", systemImage: "info.circle")
                        .font(VnuaFont.font(.subheadline)).foregroundStyle(Palette.warning)
                }
                if event.status == .cancelled {
                    Label("This event was cancelled.", systemImage: "xmark.octagon")
                        .font(VnuaFont.font(.subheadline, .medium)).foregroundStyle(Palette.warning)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Label(event.start.vnuaFull, systemImage: "clock")
                    Label(event.location, systemImage: "mappin.and.ellipse")
                    Label("Organized by \(event.organizer)", systemImage: "person")
                }
                .font(VnuaFont.font(.body))
                .card()

                Text(event.details).font(VnuaFont.font(.body))

                if event.status != .cancelled {
                    VStack(spacing: 12) {
                        Button {
                            Task { await app.toggleRSVP(event) }
                        } label: {
                            Label(going ? "Going" : "RSVP", systemImage: going ? "checkmark" : "hand.raised")
                        }
                        .buttonStyle(going ? AnyButtonStyle(.vnuaSecondary) : AnyButtonStyle(.vnuaPrimary))
                        .sensoryFeedback(.success, trigger: going)

                        NavigationLink {
                            PassView(event: event)
                        } label: {
                            Label("Show my check-in pass", systemImage: "qrcode")
                        }
                        .buttonStyle(.vnuaSecondary)

                        Button {
                            Task { await addToCalendar() }
                        } label: {
                            Label("Add to Calendar", systemImage: "calendar.badge.plus")
                        }
                        .buttonStyle(.vnuaSecondary)
                    }
                }

                if app.canRunCheckIn(for: event) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Officer tools")
                        NavigationLink {
                            OfficerCheckInView(event: event)
                        } label: {
                            Label("Run check-in", systemImage: "qrcode.viewfinder")
                        }
                        .buttonStyle(.vnuaPrimary)
                        if event.status != .cancelled {
                            Button("Cancel event", role: .destructive) { confirmCancel = true }
                                .font(VnuaFont.font(.subheadline, .medium))
                                .frame(maxWidth: .infinity, minHeight: Metrics.minTap)
                        }
                    }
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 32)
        }
        .background(Palette.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button("Report event", systemImage: "flag") { showReport = true }
            } label: { Image(systemName: "ellipsis.circle").accessibilityLabel("More") }
        }
        .sheet(isPresented: $showReport) { ReportSheet(targetType: "event", targetId: event.id, targetName: event.title) }
        .confirmationDialog("Cancel \(event.title)?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Cancel event", role: .destructive) {
                Task {
                    if await app.run({ try await app.api.cancelEvent(eventId: event.id) }) != nil {
                        await app.refresh()
                        app.show("Event cancelled")
                        dismiss()
                    }
                }
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("Members will see it as cancelled. RSVPs and check-ins are kept.")
        }
    }

    private func addToCalendar() async {
        let store = EKEventStore()
        do {
            guard try await store.requestWriteOnlyAccessToEvents() else {
                app.show("Allow calendar access in Settings to add events.", error: true); return
            }
            let ek = EKEvent(eventStore: store)
            ek.title = event.title
            ek.startDate = event.start
            ek.endDate = event.end
            ek.location = event.location
            ek.notes = "\(app.hostNames(event))\n\n\(event.details)"
            ek.calendar = store.defaultCalendarForNewEvents
            try store.save(ek, span: .thisEvent)
            app.show("Added to your calendar")
        } catch {
            app.show("Couldn't add to Calendar.", error: true)
        }
    }
}

/// Type-erased ButtonStyle so a view can switch styles at runtime.
struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

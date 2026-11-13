import SwiftUI

struct DiscoverView: View {
    @Environment(AppState.self) private var app
    @State private var query = ""
    @State private var interest: String?

    private var results: [Club] {
        app.visibleClubs.filter { club in
            (interest == nil || club.interest == interest) &&
            (query.isEmpty || club.name.localizedCaseInsensitiveContains(query)
                || club.blurb.localizedCaseInsensitiveContains(query)
                || club.interest.localizedCaseInsensitiveContains(query))
        }
    }

    private var upcoming: [ClubEvent] {
        app.visibleEvents.filter { $0.status != .cancelled && $0.end > .now }.prefix(3).map { $0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    interestChips

                    if query.isEmpty && interest == nil && !upcoming.isEmpty {
                        SectionHeader(title: "Happening soon")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(upcoming) { event in
                                    NavigationLink(value: event) { EventCard(event: event) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                        .scrollClipDisabled()
                    }

                    SectionHeader(title: interest ?? "All clubs")
                    ForEach(results) { club in
                        NavigationLink(value: club) { ClubRow(club: club) }
                            .buttonStyle(.plain)
                    }
                    if results.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 24)
            }
            .background(Palette.background)
            .navigationTitle("Discover")
            .searchable(text: $query, prompt: "Clubs and interests")
            .refreshable { await app.refresh() }
            .overlay { if app.isLoading && app.clubs.isEmpty { ProgressView() } }
            .vnuaDestinations()
        }
    }

    private var interestChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", selected: interest == nil) { interest = nil }
                ForEach(app.interests, id: \.self) { i in
                    chip(i, selected: interest == i) { interest = (interest == i ? nil : i) }
                }
            }
        }
        .scrollClipDisabled()
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(VnuaFont.font(.subheadline, .medium))
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .foregroundStyle(selected ? Palette.onAccent : Palette.text)
                .background(selected ? Palette.accent : Palette.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? .clear : Palette.divider))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct ClubRow: View {
    @Environment(AppState.self) private var app
    let club: Club

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ClubMonogram(club: club)
            VStack(alignment: .leading, spacing: 4) {
                Text(club.name).font(VnuaFont.font(.headline, .bold)).foregroundStyle(Palette.text)
                Text(club.blurb).font(VnuaFont.font(.subheadline)).foregroundStyle(Palette.secondaryText)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Badge(text: club.interest)
                    if let m = app.membership(club.id) {
                        Badge(text: m.status == .pending ? "Requested" : m.role.label,
                              systemImage: m.status == .pending ? "clock" : "checkmark",
                              tone: m.status == .pending ? .warning : .success)
                    }
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.divider)
                .padding(.top, 4)
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

struct EventCard: View {
    @Environment(AppState.self) private var app
    let event: ClubEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(event.start.vnuaDay.uppercased())
                .font(VnuaFont.font(.caption, .medium)).foregroundStyle(Palette.accent)
            Text(event.title).font(VnuaFont.font(.headline, .bold)).foregroundStyle(Palette.text)
                .lineLimit(2, reservesSpace: true)
            Text("\(event.start.vnuaTime) · \(event.location)")
                .font(VnuaFont.font(.footnote)).foregroundStyle(Palette.secondaryText).lineLimit(1)
            if app.rsvps.contains(event.id) {
                Badge(text: "Going", systemImage: "checkmark", tone: .success)
            }
        }
        .frame(width: 240, alignment: .leading)
        .card()
    }
}

#Preview {
    let app = AppState(api: MockAPI())
    return DiscoverView().environment(app).task {
        if let u = try? await app.api.verify(email: "a@hofstra.edu", name: "Alex", code: "123456", campus: .hofstra) {
            await app.signedIn(u)
        }
    }
}

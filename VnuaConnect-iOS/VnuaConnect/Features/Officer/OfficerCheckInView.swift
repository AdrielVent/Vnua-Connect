import SwiftUI
import VisionKit

struct OfficerCheckInView: View {
    @Environment(AppState.self) private var app
    let event: ClubEvent

    @State private var mode: Mode = .scan
    @State private var lookupName = ""
    @State private var matches: [MemberSummary] = []
    @State private var guestName = ""
    @State private var records: [AttendanceRecord] = []
    @State private var lastResult: (String, Bool)?          // message, isNew
    @State private var fixing: AttendanceRecord?
    @State private var resultTick = 0

    enum Mode: String, CaseIterable { case scan = "Scan", lookup = "Look up", guest = "Guest" }

    private var live: [AttendanceRecord] { records.filter { $0.removedReason == nil } }

    var body: some View {
        List {
            Section {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                switch mode {
                case .scan: scanner
                case .lookup: lookup
                case .guest: entry("Guest's name", text: $guestName) { .guest(name: guestName) }
                }

                if let (msg, isNew) = lastResult {
                    Label(msg, systemImage: isNew ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .font(VnuaFont.font(.subheadline, .medium))
                        .foregroundStyle(isNew ? Palette.success : Palette.warning)
                }
            }

            Section {
                ForEach(records) { r in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.attendeeName)
                            .font(VnuaFont.font(.body, .medium))
                            .strikethrough(r.removedReason != nil)
                        Text("\(r.mode.rawValue) · \(r.recordedAt.vnuaTime) · by \(r.recordedBy)")
                            .font(VnuaFont.font(.footnote)).foregroundStyle(Palette.secondaryText)
                        if let why = r.removedReason {
                            Text("Removed: \(why)").font(VnuaFont.font(.footnote)).foregroundStyle(Palette.warning)
                        }
                    }
                    .swipeActions {
                        if r.removedReason == nil {
                            Button("Correct") { fixing = r }.tint(Palette.danger)
                        }
                    }
                }
            } header: {
                Text("Checked in · \(live.count)")
            } footer: {
                Text("Swipe left to correct a mistake. Corrections need a reason and the original stays in the record.")
            }
        }
        .navigationTitle("Check-in")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let url = csvFile() {
                ShareLink(item: url) { Label("Export CSV", systemImage: "square.and.arrow.up") }
            }
        }
        .sensoryFeedback(.success, trigger: resultTick)
        .task { await reload() }
        .sheet(item: $fixing) { r in CorrectionSheet(record: r) { await reload() } }
    }

    // MARK: modes

    @ViewBuilder private var scanner: some View {
        if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
            QRScanner { payload in Task { await checkIn(.pass(token: payload)) } }
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
        } else {
            Label("Camera scanning needs a physical iPhone with camera access. Use Look up instead.",
                  systemImage: "camera.badge.ellipsis")
                .font(VnuaFont.font(.subheadline)).foregroundStyle(Palette.secondaryText)
        }
    }

    @ViewBuilder private var lookup: some View {
        TextField("Search members and RSVPs", text: $lookupName)
            .textContentType(.name)
            .autocorrectionDisabled()
            .task(id: lookupName) {
                try? await Task.sleep(for: .milliseconds(250))      // debounce typing
                guard !Task.isCancelled else { return }
                matches = await app.run({ try await app.api.searchAttendees(eventId: event.id, query: lookupName) }) ?? []
            }
        ForEach(matches) { m in
            let isIn = live.contains { $0.attendeeName == m.name }
            Button {
                Task { await checkIn(.member(id: m.id, name: m.name)) }
            } label: {
                HStack {
                    Text(m.name).foregroundStyle(Palette.text)
                    Spacer()
                    Image(systemName: isIn ? "checkmark.circle.fill" : "plus.circle")
                        .foregroundStyle(isIn ? Palette.success : Palette.accent)
                }
            }
            .accessibilityLabel(isIn ? "\(m.name), checked in" : "Check in \(m.name)")
        }
    }

    private func entry(_ prompt: String, text: Binding<String>, subject: @escaping () -> CheckInSubject) -> some View {
        HStack {
            TextField(prompt, text: text)
                .textContentType(.name)
                .submitLabel(.done)
                .onSubmit { submit(text, subject()) }
            Button("Check in") { submit(text, subject()) }
                .buttonStyle(.borderedProminent)
                .disabled(text.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func submit(_ text: Binding<String>, _ subject: CheckInSubject) {
        Task {
            await checkIn(subject)
            text.wrappedValue = ""
        }
    }

    // MARK: actions

    private func checkIn(_ subject: CheckInSubject) async {
        let rid = UUID().uuidString
        guard let res = await app.run({ try await app.api.checkIn(eventId: event.id, subject: subject, requestId: rid) }) else { return }
        switch res.status {
        case .recorded:
            lastResult = ("\(res.record.attendeeName) checked in", true)
            resultTick += 1
        case .duplicate:
            lastResult = ("\(res.record.attendeeName) was already checked in", false)
        }
        await reload()
    }

    private func reload() async {
        if let r = await app.run({ try await app.api.attendance(eventId: event.id) }) { records = r }
    }

    private func csvFile() -> URL? {
        guard !records.isEmpty else { return nil }
        func esc(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var rows = ["name,mode,recorded_at,recorded_by,removed_reason"]
        for r in records.sorted(by: { $0.recordedAt < $1.recordedAt }) {
            rows.append([esc(r.attendeeName), r.mode.rawValue, r.recordedAt.ISO8601Format(),
                         esc(r.recordedBy), esc(r.removedReason ?? "")].joined(separator: ","))
        }
        let safe = event.title.prefix(30).replacingOccurrences(of: "[^A-Za-z0-9]+", with: "-", options: .regularExpression)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("attendance-\(safe).csv")
        try? rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

struct CorrectionSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let record: AttendanceRecord
    let onDone: () async -> Void
    @State private var reason = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Remove \(record.attendeeName) from attendance?")
                } footer: {
                    Text("The original record is kept with your reason so the club's history stays honest.")
                }
                Section("Reason (required)") {
                    TextField("e.g. Scanned the wrong person", text: $reason, axis: .vertical).lineLimit(2...4)
                }
            }
            .navigationTitle("Correct attendance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Remove", role: .destructive) {
                        Task {
                            let rid = UUID().uuidString
                            if await app.run({ try await app.api.correct(recordId: record.id, reason: reason, requestId: rid) }) != nil {
                                await onDone()
                                dismiss()
                            }
                        }
                    }
                    .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Live QR scanner using Apple's VisionKit (no third-party SDK).
struct QRScanner: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                           qualityLevel: .balanced,
                                           recognizesMultipleItems: false,
                                           isHighFrameRateTrackingEnabled: false,
                                           isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) {
        vc.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        private var last: (String, Date)?
        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            for case .barcode(let code) in items {
                guard let payload = code.payloadStringValue else { continue }
                // Ignore the same code for 3s so one pass isn't submitted repeatedly.
                if let (p, t) = last, p == payload, Date.now.timeIntervalSince(t) < 3 { continue }
                last = (payload, .now)
                onScan(payload)
            }
        }
    }
}

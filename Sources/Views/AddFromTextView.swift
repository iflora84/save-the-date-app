import SwiftUI
import UIKit
import PhotosUI

/// What the plus button offers. The choice is handed back so the list can open
/// the next sheet once this one has closed.
enum AddMethod {
    case typeIt, pasteText, screenshot, calendar
}

struct AddDateChooser: View {
    let onChoose: (AddMethod) -> Void
    @Environment(\.dismiss) private var dismiss

    init(onChoose: @escaping (AddMethod) -> Void) {
        self.onChoose = onChoose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ADD A DATE")
                .font(Theme.eyebrowFont)
                .tracking(2.4)
                .foregroundStyle(Theme.accent)
            Text("New date")
                .font(Theme.display(32))
                .padding(.bottom, 6)
            option(.typeIt, icon: "square.and.pencil", title: "Type it in", subtitle: "Name, day and reminders", ai: false)
            option(.pasteText, icon: "doc.on.clipboard", title: "Paste text", subtitle: "Emails, messages, tickets", ai: true)
            option(.screenshot, icon: "photo.on.rectangle", title: "From a screenshot", subtitle: "Bookings, invites, posts", ai: true)
            option(.calendar, icon: "calendar", title: "Find in Calendar", subtitle: "Birthdays, anniversaries, trips", ai: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .background(Theme.screenBackground)
    }

    private func option(_ method: AddMethod, icon: String, title: String, subtitle: String, ai: Bool) -> some View {
        Button {
            onChoose(method)
            dismiss()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
                    .background(Theme.chipBackground, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Theme.font(17, weight: .semibold))
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if ai && OnDeviceAI.isAvailable {
                    AIBadge()
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// The small tag on anything Apple Intelligence helps with.
struct AIBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
            Text("AI")
        }
        .font(Theme.font(11, weight: .bold))
        .foregroundStyle(Color.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.aurora, in: Capsule())
        .fixedSize()
    }
}

/// Paste text or pick a screenshot; the dates found are offered for the editor.
struct TextImportView: View {
    enum Source {
        case paste, screenshot
    }

    let source: Source
    let onPick: (FoundDate) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var text: String = ""
    @State private var screenshot: UIImage? = nil
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var phase: Phase = .input
    @State private var found: [FoundDate] = []
    @State private var usedAI: Bool = false

    enum Phase: Equatable {
        case input, reading, results
    }

    init(source: Source, onPick: @escaping (FoundDate) -> Void) {
        self.source = source
        self.onPick = onPick
    }

    var body: some View {
        NavigationStack {
            content
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Theme.screenBackground)
                .navigationTitle(source == .paste ? "Paste text" : "From a screenshot")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                .onChange(of: photoItem) { _, item in
                    Task { await loadScreenshot(item) }
                }
        }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .input:
            if source == .paste {
                pasteInput
            } else {
                screenshotInput
            }
        case .reading:
            reading
        case .results:
            results
        }
    }

    private var pasteInput: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Paste a booking, an invite or a message. The date is found on this iPhone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                if text.isEmpty {
                    Text("Your flight UA 837 to Osaka departs Thursday 4 February 2027…")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(16)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 200)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            // PasteButton reads the clipboard without iOS asking for permission.
            PasteButton(payloadType: String.self) { strings in
                text = strings.joined(separator: "\n")
            }
            .buttonBorderShape(.capsule)
            Spacer()
            Button {
                Task { await read(text) }
            } label: {
                Label(OnDeviceAI.isAvailable ? "Read with Apple Intelligence" : "Find the date", systemImage: "sparkles")
            }
            .buttonStyle(PillButtonStyle(.primary))
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            privacyLine
        }
    }

    private var screenshotInput: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Theme.accent)
            Text("Pick a screenshot of a booking, an invite or a post.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            PhotosPicker(selection: $photoItem, matching: .screenshots) {
                Label("Choose a screenshot", systemImage: "photo")
            }
            .buttonStyle(PillButtonStyle(.primary))
            privacyLine
        }
    }

    private var reading: some View {
        VStack(spacing: 20) {
            if let screenshot {
                Image(uiImage: screenshot)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        ScanShimmer()
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
            } else {
                ScanShimmer()
                    .frame(height: 160)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            HStack(spacing: 12) {
                ProgressView()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Finding dates…")
                        .font(Theme.font(17, weight: .semibold))
                    Text(OnDeviceAI.isAvailable ? "Apple Intelligence, on this iPhone" : "On this iPhone")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    @ViewBuilder private var results: some View {
        if found.isEmpty {
            VStack(spacing: 14) {
                Spacer()
                Text("No date found")
                    .font(Theme.display(26, weight: .semibold))
                Text("Try another screenshot or more of the text, or type the date in yourself.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Try again") {
                    phase = .input
                }
                .buttonStyle(PillButtonStyle(.secondary))
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(found.count == 1 ? "Found 1 date" : "Found \(found.count) dates")
                        .font(Theme.display(30))
                    Text(usedAI ? "Found with Apple Intelligence, on this iPhone. Check it before saving." : "Found on this iPhone. Check it before saving.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ForEach(found) { date in
                        foundRow(date)
                    }
                }
            }
        }
    }

    private func foundRow(_ date: FoundDate) -> some View {
        Button {
            onPick(date)
            dismiss()
        } label: {
            HStack(spacing: 14) {
                Text(date.emoji)
                    .font(.system(size: 30))
                    .frame(width: 52, height: 52)
                    .background(Theme.chipBackground, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(date.name)
                        .font(Theme.display(20))
                    Text("\(date.kindLabel) · \(OccasionMath.dateText(month: date.month, day: date.day, year: date.year, calendar: .current))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Review")
                    .font(Theme.font(14, weight: .semibold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Theme.accentFill, in: Capsule())
            }
            .padding(14)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var privacyLine: some View {
        Label("Read on this iPhone. Nothing is uploaded.", systemImage: "checkmark.shield")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
    }

    private func loadScreenshot(_ item: PhotosPickerItem?) async {
        guard let item = item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            return
        }
        photoItem = nil
        screenshot = image
        phase = .reading
        let recognized = await TextDateFinder.recognizeText(in: image)
        await finish(TextDateFinder.find(in: recognized))
    }

    private func read(_ pasted: String) async {
        phase = .reading
        await finish(TextDateFinder.find(in: pasted))
    }

    private func finish(_ result: TextDateFinder.Result) async {
        found = result.dates
        usedAI = result.usedAI
        phase = .results
    }
}

/// A slow band of aurora light sweeping across whatever is being read.
private struct ScanShimmer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep: CGFloat = -1

    var body: some View {
        GeometryReader { geometry in
            Theme.aurora
                .opacity(0.35)
                .frame(width: geometry.size.width * 0.6)
                .blur(radius: 24)
                .offset(x: sweep * geometry.size.width)
        }
        .allowsHitTesting(false)
        .onAppear {
            if reduceMotion { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                sweep = 1
            }
        }
    }
}
